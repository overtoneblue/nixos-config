"""SQLite + file storage for wavegen-web runs.

Schema:
  runs —
    id             TEXT PRIMARY KEY   (uuid)
    prompt         TEXT               (edit prompt)
    status         TEXT               (queued / running / done / failed)
    error          TEXT               (error text when failed)
    created_at     REAL               (unix timestamp)
    started_at     REAL
    completed_at   REAL
    retry_of       TEXT               (original run id if this is a retry)
    num_inputs     INTEGER            (count of input images)
    input_filenames TEXT              (JSON array of filenames)
    result_filename TEXT              (filename of the result image)

File layout:
  /var/lib/wavegen-web/
    runs.db
    runs/<id>/input-01.ext ...
    runs/<id>/result.ext
"""

import json
import logging
import mimetypes
import sqlite3
import time
from pathlib import Path
from typing import Any

log = logging.getLogger("wavegen-web")

SQL_CREATE_TABLE = """
CREATE TABLE IF NOT EXISTS runs (
    id TEXT PRIMARY KEY,
    prompt TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued',
    error TEXT,
    created_at REAL NOT NULL,
    started_at REAL,
    completed_at REAL,
    retry_of TEXT,
    num_inputs INTEGER NOT NULL DEFAULT 0,
    input_filenames TEXT NOT NULL DEFAULT '[]',
    result_filename TEXT
)
"""

SQL_INSERT = """
INSERT INTO runs
    (id, prompt, status, created_at, num_inputs, input_filenames, retry_of)
VALUES (?, ?, 'queued', ?, ?, '[]', ?)
"""

SQL_UPDATE = "UPDATE runs SET {} WHERE id=?"

SQL_GET = """
SELECT id, prompt, status, error, created_at, started_at, completed_at,
       retry_of, num_inputs, input_filenames, result_filename
FROM runs WHERE id=?
"""

SQL_LIST = """
SELECT id, prompt, status, error, created_at, started_at, completed_at,
       retry_of, num_inputs, input_filenames, result_filename
FROM runs ORDER BY created_at DESC LIMIT ?
"""

SQL_STUCK = "SELECT id FROM runs WHERE status='running'"
SQL_SET_STUCK_FAILED = "UPDATE runs SET status='failed', error=?, completed_at=? WHERE status='running'"


class Storage:
    """Manages the SQLite database and run file storage."""

    def __init__(self, state_dir: str) -> None:
        self.state_dir = Path(state_dir)
        self.runs_dir = self.state_dir / "runs"
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.runs_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = self.state_dir / "runs.db"
        self._conn = sqlite3.connect(str(self.db_path))
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute(SQL_CREATE_TABLE)
        self._conn.commit()
        log.info("Storage ready — db=%s, dir=%s", self.db_path, self.state_dir)

    # ── Run CRUD ──────────────────────────────────────────────────────────

    def create_run(self, run_id: str, prompt: str, num_inputs: int,
                   retry_of: str | None = None) -> None:
        """Insert a new run record."""
        self._conn.execute(SQL_INSERT,
                           (run_id, prompt, time.time(), num_inputs, retry_of))
        self._conn.commit()

    def save_input_filename(self, run_id: str, input_name: str) -> None:
        """Append an input filename to the run's input_filenames JSON."""
        cur = self._conn.execute("SELECT input_filenames FROM runs WHERE id=?",
                                 (run_id,))
        row = cur.fetchone()
        if row:
            names = json.loads(row[0])
            names.append(input_name)
            self._conn.execute("UPDATE runs SET input_filenames=? WHERE id=?",
                               (json.dumps(names), run_id))
            self._conn.commit()

    def update_status(self, run_id: str, status: str, *,
                      error: str | None = None,
                      result_filename: str | None = None) -> None:
        """Transition a run's status and set timestamps."""
        now = time.time()
        updates: dict[str, object] = {"status": status}
        if status == "running":
            updates["started_at"] = now
        elif status in ("done", "failed"):
            updates["completed_at"] = now
        if error is not None:
            updates["error"] = error
        if result_filename is not None:
            updates["result_filename"] = result_filename
        set_clause = ", ".join(f"{k}=?" for k in updates)
        values = [*updates.values(), run_id]
        self._conn.execute(SQL_UPDATE.format(set_clause), values)
        self._conn.commit()

    def save_result(self, run_id: str, data: bytes,
                    content_type: str) -> str:
        """Write result bytes to disk and mark the run done."""
        ext = (mimetypes.guess_extension(content_type.split(";")[0].strip())
               or ".png")
        result_name = f"result{ext}"
        run_dir = self._run_dir(run_id)
        (run_dir / result_name).write_bytes(data)
        self.update_status(run_id, "done", result_filename=result_name)
        log.info("Saved result for run %s -> %s", run_id, result_name)
        return result_name

    def mark_stuck_as_failed(self) -> None:
        """On boot: any rows stuck in 'running' are marked failed."""
        now = time.time()
        self._conn.execute(SQL_SET_STUCK_FAILED,
                           ("interrupted by restart", now))
        self._conn.commit()
        changed = self._conn.total_changes
        if changed:
            log.info("Marked %d stuck run(s) as 'failed (interrupted by restart)'",
                     changed)

    def get_run(self, run_id: str) -> dict[str, Any] | None:
        """Return a single run dict, or None."""
        cur = self._conn.execute(SQL_GET, (run_id,))
        row = cur.fetchone()
        if not row:
            return None
        return self._row_to_dict(row)

    def list_runs(self, limit: int = 50) -> list[dict[str, Any]]:
        """Return newest-first runs."""
        cur = self._conn.execute(SQL_LIST, (limit,))
        return [self._row_to_dict(row) for row in cur.fetchall()]

    # ── File helpers ──────────────────────────────────────────────────────

    def _run_dir(self, run_id: str) -> Path:
        p = self.runs_dir / run_id
        p.mkdir(parents=True, exist_ok=True)
        return p

    def store_input(self, run_id: str, index: int, filename: str,
                    data: bytes) -> str:
        """Write an input image to disk and record it."""
        run_dir = self._run_dir(run_id)
        ext = Path(filename).suffix or ".jpg"
        input_name = f"input-{index:02d}{ext}"
        (run_dir / input_name).write_bytes(data)
        self.save_input_filename(run_id, input_name)
        return input_name

    def input_path(self, run_id: str, index: int) -> Path | None:
        """Return the path to an input image if it exists."""
        run = self.get_run(run_id)
        if not run:
            return None
        names = run["input_filenames"]
        if index < 0 or index >= len(names):
            return None
        return self.runs_dir / run_id / names[index]

    def result_path(self, run_id: str) -> Path | None:
        """Return the path to a result image if it exists."""
        run = self.get_run(run_id)
        if not run or not run.get("result_filename"):
            return None
        return self.runs_dir / run_id / run["result_filename"]

    # ── Internal ──────────────────────────────────────────────────────────

    @staticmethod
    def _row_to_dict(row: tuple) -> dict[str, Any]:
        return {
            "id": row[0],
            "prompt": row[1],
            "status": row[2],
            "error": row[3],
            "created_at": row[4],
            "started_at": row[5],
            "completed_at": row[6],
            "retry_of": row[7],
            "num_inputs": row[8],
            "input_filenames": json.loads(row[9]),
            "result_filename": row[10],
        }

    def close(self) -> None:
        self._conn.close()


_manager: Storage | None = None


def init(state_dir: str) -> Storage:
    """Initialise global storage. Call once at startup."""
    global _manager
    _manager = Storage(state_dir)
    return _manager


def get() -> Storage:
    """Return the global storage instance."""
    assert _manager is not None, "Storage not initialised"
    return _manager