"""Session-based single-password auth for wavegen-web."""

import hmac
import json
import logging
import secrets
import threading
import time
from pathlib import Path

log = logging.getLogger("wavegen-web")


class SessionManager:
    """Session store backed by a shared password.

    Sessions persist to a small JSON file so app restarts and deploys do
    not log users out.
    """

    TTL_SECONDS = 86_400 * 7  # matches the 7-day cookie

    def __init__(self, password: str, sessions_file: str | None = None) -> None:
        self._password = password
        self._sessions: dict[str, float] = {}
        self._file = Path(sessions_file) if sessions_file else None
        self._lock = threading.Lock()
        self._load()

    def _load(self) -> None:
        if not self._file or not self._file.exists():
            return
        try:
            raw = json.loads(self._file.read_text())
            now = time.time()
            self._sessions = {
                t: float(e) for t, e in raw.items()
                if isinstance(e, (int, float)) and float(e) > now
            }
        except Exception:
            log.warning("Could not load sessions file; starting fresh")
            self._sessions = {}

    def _save(self) -> None:
        if not self._file:
            return
        try:
            tmp = self._file.with_name(self._file.name + ".tmp")
            tmp.write_text(json.dumps(self._sessions))
            tmp.replace(self._file)
        except Exception:
            log.exception("Could not persist sessions file")

    def check_password(self, candidate: str) -> bool:
        """Constant-time compare against the stored password.

        Compares as UTF-8 bytes (compare_digest rejects str containing
        non-ASCII) and tolerates stray leading/trailing whitespace from
        mobile keyboards (including non-breaking spaces).
        """
        return hmac.compare_digest(self._password.encode("utf-8"),
                                   candidate.strip().encode("utf-8"))

    def create_session(self) -> str:
        """Generate a new session token (persisted)."""
        token = secrets.token_urlsafe(32)
        with self._lock:
            self._sessions[token] = time.time() + self.TTL_SECONDS
            self._save()
        return token

    def validate(self, token: str) -> bool:
        """Check if a session token is valid and unexpired."""
        if not token:
            return False
        with self._lock:
            exp = self._sessions.get(token)
        return bool(exp and exp > time.time())

    def remove_session(self, token: str) -> None:
        """Invalidate a session token."""
        with self._lock:
            self._sessions.pop(token, None)
            self._save()

    @property
    def session_count(self) -> int:
        return len(self._sessions)


_manager: SessionManager | None = None


def init(password: str, sessions_file: str | None = None) -> SessionManager:
    """Initialise the global session manager. Call once at startup."""
    global _manager
    _manager = SessionManager(password, sessions_file)
    log.info("Session manager initialised (%d chars, %d live sessions)",
             len(password), _manager.session_count)
    return _manager


def get() -> SessionManager:
    """Return the global session manager."""
    assert _manager is not None, "SessionManager not initialised"
    return _manager