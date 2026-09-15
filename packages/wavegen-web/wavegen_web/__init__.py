"""wavegen-web — Web UI for WaveSpeedAI image editing (Seedream V5.0 Pro Edit).

Queue with parallel workers, history, retry, single-password auth.
"""

import os
import sys

ENV_PREFIX = "WAVEGEN_WEB_"


def env_str(key: str, default: str = "") -> str:
    val = os.environ.get(f"{ENV_PREFIX}{key}", "")
    return val if val else default


def env_int(key: str, default: int = 0) -> int:
    raw = os.environ.get(f"{ENV_PREFIX}{key}", "")
    return int(raw) if raw else default


def run() -> None:
    """Console-script entry point (project.scripts.wavegen-web)."""
    # Re-import app here so it initialises with env set
    from wavegen_web.app import create_app

    app = create_app()

    import uvicorn

    port = env_int("PORT", 8443)
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")