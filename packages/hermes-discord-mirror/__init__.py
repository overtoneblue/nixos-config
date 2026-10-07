"""discord-mirror — agent half: mirror non-Discord turns into the bound Discord thread."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_CORE = "hermes_discord_mirror_core"


def load_core():
    """One shared core module per process (the dashboard API loads the same name)."""
    mod = sys.modules.get(_CORE)
    if mod is None:
        path = Path(__file__).resolve().parent / "discord_mirror_core.py"
        spec = importlib.util.spec_from_file_location(_CORE, path)
        mod = importlib.util.module_from_spec(spec)
        sys.modules[_CORE] = mod
        spec.loader.exec_module(mod)
    return mod


def register(ctx) -> None:
    core = load_core()
    ctx.register_hook("pre_llm_call", core.on_pre_llm_call)
    ctx.register_hook("post_llm_call", core.on_post_llm_call)
    # Only inside `hermes gateway run`: lets the desktop start posts the gateway owns.
    core.start_gateway_bridge()
