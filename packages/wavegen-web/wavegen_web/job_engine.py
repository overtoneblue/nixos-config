"""Job queue with worker threads for WaveSpeedAPI image editing.

Copies the verified wavegen bot upload → submit → poll pattern.
"""

import json
import logging
import mimetypes
import queue
import threading
import time
from pathlib import Path
from typing import Any

import httpx

log = logging.getLogger("wavegen-web")

STATUS_TERMINAL = frozenset({"completed", "failed", "cancelled", "timeout"})

API_BASE = "https://api.wavespeed.ai/api/v3"
MODEL = "bytedance/seedream-v5.0-pro/edit"


class JobEngine:
    """FIFO queue with N parallel workers processing WaveSpeed jobs."""

    def __init__(self, storage, api_key: str, concurrency: int = 2,
                 poll_timeout: int = 300) -> None:
        self._storage = storage
        self._api_key = api_key
        self._poll_timeout = poll_timeout
        self._concurrency = concurrency
        self._queue: queue.Queue = queue.Queue()
        self._workers: list[threading.Thread] = []
        self._stop_event = threading.Event()

    def start(self) -> None:
        """Spawn worker threads."""
        self._stop_event.clear()
        for i in range(self._concurrency):
            t = threading.Thread(target=self._worker_loop,
                                 name=f"wavegen-web-{i}",
                                 daemon=True)
            t.start()
            self._workers.append(t)
        log.info("Job engine started (%d workers)", self._concurrency)

    def stop(self) -> None:
        """Signal workers to stop."""
        self._stop_event.set()

    def enqueue(self, run_id: str, input_files: list[tuple[str, bytes]],
                prompt: str) -> None:
        """Add a job to the queue."""
        self._queue.put((run_id, input_files, prompt))
        log.info("Queued run %s", run_id)

    # ── Worker ────────────────────────────────────────────────────────────

    def _worker_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                run_id, input_files, prompt = self._queue.get(timeout=2)
            except queue.Empty:
                continue

            # Persist input files to disk (they arrive as in-memory bytes)
            for i, (fname, data) in enumerate(input_files, 1):
                self._storage.store_input(run_id, i, fname, data)

            # Mark running
            self._storage.update_status(run_id, "running")
            log.info("Run %s started (%d image(s))", run_id, len(input_files))

            try:
                self._process_job(run_id, prompt,
                                  [d for _, d in input_files],
                                  [f for f, _ in input_files])
            except Exception as exc:
                err_text = self._error_detail(exc)
                self._storage.update_status(run_id, "failed", error=err_text)
                log.error("Run %s failed: %s", run_id, err_text)
            finally:
                self._queue.task_done()

    def _process_job(self, run_id: str, prompt: str,
                     data_list: list[bytes],
                     filenames: list[str]) -> None:
        """Upload images → submit → poll → save result.

        This is a sync port of the validated wavegen bot pattern
        (packages/wavegen/wavegen.py).
        """
        with httpx.Client(timeout=30) as client:
            # 1. Upload every input image
            download_urls: list[str] = []
            for data_bytes, fname in zip(data_list, filenames):
                url = self._wavespeed_upload(client, data_bytes, fname)
                download_urls.append(url)

            # 2. Submit the edit job (with retry)
            submit_data = self._wavespeed_submit(client, prompt, download_urls)
            task_id = submit_data.get("data", {}).get("id", "")
            get_url = submit_data.get("data", {}).get("urls", {}).get("get", "")
            if not task_id:
                raise RuntimeError("Submit OK but no task ID returned")

            # 3. Poll until terminal
            result = self._wavespeed_poll(client, task_id, get_url)
            status = result.get("data", {}).get("status", "unknown")

            if status == "completed":
                outputs = result.get("data", {}).get("outputs", [])
                if not outputs:
                    raise RuntimeError("Edit completed but no outputs")
                out_url = outputs[0]
                resp = client.get(out_url, timeout=60)
                resp.raise_for_status()
                out_ct = resp.headers.get("Content-Type",
                                           "image/png").split(";")[0].strip()
                self._storage.save_result(run_id, resp.content, out_ct)
                log.info("Run %s completed successfully", run_id)
            elif status in ("failed", "cancelled", "timeout"):
                err = result.get("data", {}).get("error",
                       result.get("message", status))
                raise RuntimeError(f"Edit {status}: {err}")
            else:
                raise RuntimeError(f"Unexpected status '{status}'")

    # ── WaveSpeed API (sync) ──────────────────────────────────────────────

    def _wavespeed_upload(self, client: httpx.Client, data_bytes: bytes,
                          filename: str) -> str:
        """Upload bytes → download_url (two-step ticket flow)."""
        if not Path(filename).suffix:
            ext = mimetypes.guess_extension("application/octet-stream") or ".jpg"
            filename = f"{filename}{ext}"

        # Step 1: ticket
        headers = {"Authorization": f"Bearer {self._api_key}",
                   "Content-Type": "application/json"}
        payload = {"filename": filename, "size": len(data_bytes)}
        resp = client.post(f"{API_BASE}/media/uploads", headers=headers,
                           json=payload, timeout=30)
        resp.raise_for_status()
        ticket = resp.json()["data"]
        upload_url = ticket["upload"]["url"]
        upload_method = ticket["upload"].get("method", "PUT")
        upload_headers = dict(ticket["upload"].get("headers", {}))

        if "Content-Type" not in upload_headers:
            guessed, _ = mimetypes.guess_type(filename)
            if guessed:
                upload_headers["Content-Type"] = guessed

        # Step 2: upload
        put_resp = client.request(upload_method, upload_url,
                                  headers=upload_headers, content=data_bytes,
                                  timeout=120)
        put_resp.raise_for_status()

        return ticket["download_url"]

    def _wavespeed_submit(self, client: httpx.Client, prompt: str,
                          image_urls: list[str]) -> dict[str, Any]:
        """Submit an edit job with retry."""
        headers = {"Authorization": f"Bearer {self._api_key}",
                   "Content-Type": "application/json"}
        body = {"prompt": prompt, "images": image_urls}
        for attempt in range(3):
            try:
                resp = client.post(
                    f"{API_BASE}/{MODEL.lstrip('/')}",
                    headers=headers, json=body, timeout=60,
                )
                resp.raise_for_status()
                return resp.json()
            except httpx.HTTPStatusError as e:
                if (attempt < 2
                        and e.response.status_code in (429, 500, 502, 503, 504)):
                    delay = 3 if attempt == 0 else 9
                    log.warning("Submit HTTP %d, retry in %ds",
                                e.response.status_code, delay)
                    time.sleep(delay)
                    continue
                raise
        raise RuntimeError("Submit failed after 3 attempts")

    def _wavespeed_poll(self, client: httpx.Client, task_id: str,
                        get_url: str) -> dict[str, Any]:
        """Poll a task until terminal or timeout."""
        headers = {"Authorization": f"Bearer {self._api_key}"}
        deadline = time.monotonic() + self._poll_timeout
        last_status = ""
        while time.monotonic() < deadline:
            resp = client.get(get_url, headers=headers, timeout=30)
            resp.raise_for_status()
            data = resp.json()
            status = data.get("data", {}).get("status", "unknown")
            if status != last_status:
                log.info("Task %s status: %s", task_id, status)
                last_status = status
            if status in STATUS_TERMINAL:
                return data
            time.sleep(3)
        return {"code": 408, "message": "timeout",
                "data": {"id": task_id, "status": "timeout"}}

    @staticmethod
    def _error_detail(exc: Exception) -> str:
        """Human-readable error text."""
        if isinstance(exc, httpx.HTTPStatusError):
            try:
                body = exc.response.text.strip()
            except Exception:
                body = ""
            return f"HTTP {exc.response.status_code}" + (
                f": {body[:300]}" if body else "")
        return str(exc)


_engine: JobEngine | None = None


def init(storage, api_key: str, concurrency: int = 2,
         poll_timeout: int = 300) -> JobEngine:
    """Initialise the global job engine. Call once at startup."""
    global _engine
    _engine = JobEngine(storage, api_key, concurrency, poll_timeout)
    return _engine


def get() -> JobEngine:
    """Return the global job engine instance."""
    assert _engine is not None, "JobEngine not initialised"
    return _engine