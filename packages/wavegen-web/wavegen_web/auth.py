"""Session-based single-password auth for wavegen-web."""

import hmac
import secrets
import logging

log = logging.getLogger("wavegen-web")


class SessionManager:
    """Simple in-memory session store backed by a shared password."""

    def __init__(self, password: str) -> None:
        self._password = password
        self._sessions: dict[str, bool] = {}

    def check_password(self, candidate: str) -> bool:
        """Constant-time compare against the stored password.

        Compares as UTF-8 bytes (compare_digest rejects str containing
        non-ASCII) and tolerates stray leading/trailing whitespace from
        mobile keyboards (including non-breaking spaces).
        """
        return hmac.compare_digest(self._password.encode("utf-8"),
                                   candidate.strip().encode("utf-8"))

    def create_session(self) -> str:
        """Generate a new session token."""
        token = secrets.token_urlsafe(32)
        self._sessions[token] = True
        return token

    def validate(self, token: str) -> bool:
        """Check if a session token is valid."""
        return token in self._sessions

    def remove_session(self, token: str) -> None:
        """Invalidate a session token."""
        self._sessions.pop(token, None)

    @property
    def session_count(self) -> int:
        return len(self._sessions)


_manager: SessionManager | None = None


def init(password: str) -> SessionManager:
    """Initialise the global session manager. Call once at startup."""
    global _manager
    _manager = SessionManager(password)
    log.info("Session manager initialised (%d chars)", len(password))
    return _manager


def get() -> SessionManager:
    """Return the global session manager."""
    assert _manager is not None, "SessionManager not initialised"
    return _manager