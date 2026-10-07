"""discord-mirror — backend half, mounted by hermes serve at /api/plugins/discord-mirror/."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import JSONResponse

_CORE = "hermes_discord_mirror_core"


def _core():
    mod = sys.modules.get(_CORE)
    if mod is None:
        path = Path(__file__).resolve().parent.parent / "discord_mirror_core.py"
        spec = importlib.util.spec_from_file_location(_CORE, path)
        mod = importlib.util.module_from_spec(spec)
        sys.modules[_CORE] = mod
        spec.loader.exec_module(mod)
    return mod


def _guard(fn, *args):
    """Run a mutation; Discord/validation failures come back as {ok:false,error} (HTTP 400)."""
    core = _core()
    try:
        return fn(*args)
    except (ValueError, RuntimeError, core.DiscordError) as e:
        return JSONResponse({"ok": False, "error": str(e)}, status_code=400)


router = APIRouter()


@router.get("/tree")
def tree(refresh: bool = False):
    """Guilds -> categories -> channels/forums -> threads, joined to Hermes sessions."""
    return _core().build_tree(force=refresh)


@router.get("/status")
def status():
    return _core().status()


@router.get("/session")
def session(target: str):
    """Hermes session bound to a Discord channel/thread (null until the gateway creates it)."""
    return {"session_id": _core().session_for_target(target)}


@router.post("/channels")
def create_channel(body: dict):
    """{guild_id, kind: text|voice|category|announcement|stage|forum|media, name,
    parent_id?, topic? (forum: post guidelines), tags?, layout?: list|gallery, nsfw?}"""
    return _guard(_core().create_channel, body)


@router.patch("/channels/{channel_id}")
def update_channel(channel_id: str, body: dict):
    """{name?, topic?, tags?, parent_id?} — topic on a forum is its post guidelines."""
    return _guard(_core().update_channel, channel_id, body)


@router.post("/posts")
def create_post(body: dict):
    """{channel_id, content, title?, tags? (forum tag ids), mode?: thread|channel}"""
    return _guard(_core().create_post, body)
