"""Shared core for the discord-mirror Hermes plugin.

Two halves import this one module (by file path, registered under a fixed
name so both share one instance inside a process):

* the agent half (``__init__.py``):
  - ``pre_llm_call`` / ``post_llm_call`` hooks that copy turns run OUTSIDE the
    Discord gateway (Hermes desktop, TUI, CLI) into the Discord channel/thread
    the session is bound to, and give those turns the forum's post guidelines;
  - inside ``hermes gateway run`` only: the *gateway bridge*, a small worker
    that takes "start this post" requests from the backend half and hands them
    to the live Discord adapter exactly like a real inbound message, so a post
    created from the desktop becomes a natively bound gateway session;
* the backend half (``dashboard/plugin_api.py``, inside ``hermes serve``) —
  the server tree the desktop page renders, plus channel/category/forum
  management and new-post creation.

Discord -> Hermes needs no code: the gateway already turns Discord messages
into turns in the bound session, and the desktop reads the same state.db.

Stdlib only (plus hermes internals when available).
"""

from __future__ import annotations

import json
import logging
import mimetypes
import os
import queue
import re
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from contextlib import closing
from pathlib import Path
from typing import Any, Optional

log = logging.getLogger("discord_mirror")

PLUGIN_ID = "discord-mirror"
API = "https://discord.com/api/v10"
USER_AGENT = "DiscordBot (https://github.com/overtoneblue/nixos-config, 1.0) hermes-discord-mirror"
WEBHOOK_NAME = "Hermes desktop"
STRUCT_TTL = 300  # seconds the Discord structure is cached
CHUNK = 1900  # Discord hard limit is 2000
MAX_UPLOAD = 8 * 1024 * 1024

# Discord channel types
T_TEXT, T_DM, T_VOICE, T_GROUP_DM, T_CATEGORY, T_NEWS = 0, 1, 2, 3, 4, 5
T_NEWS_THREAD, T_PUBLIC_THREAD, T_PRIVATE_THREAD, T_STAGE, T_FORUM, T_MEDIA = 10, 11, 12, 13, 15, 16
THREAD_TYPES = {T_NEWS_THREAD, T_PUBLIC_THREAD, T_PRIVATE_THREAD}
LISTED_TYPES = {T_TEXT, T_NEWS, T_FORUM, T_MEDIA, T_VOICE, T_STAGE}
POSTABLE_TYPES = {T_TEXT, T_NEWS, T_FORUM, T_MEDIA}
CHANNEL_KINDS = {  # UI name -> Discord type
    "text": T_TEXT, "voice": T_VOICE, "category": T_CATEGORY, "announcement": T_NEWS,
    "stage": T_STAGE, "forum": T_FORUM, "media": T_MEDIA,
}
TOPIC_LIMIT = {T_FORUM: 4096, T_MEDIA: 4096}  # everything else: 1024


# ── environment ─────────────────────────────────────────────────────────

def hermes_home() -> Path:
    try:
        from hermes_constants import get_hermes_home

        return Path(get_hermes_home())
    except Exception:
        return Path(os.environ.get("HERMES_HOME") or Path.home() / ".hermes")


def bot_token() -> Optional[str]:
    tok = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    if tok:
        return tok
    try:
        for line in (hermes_home() / ".env").read_text().splitlines():
            if line.startswith("DISCORD_BOT_TOKEN="):
                return line.split("=", 1)[1].strip().strip("'\"") or None
    except OSError:
        pass
    return None


def in_gateway_process() -> bool:
    """True inside ``hermes gateway run``: its turns came FROM Discord (or another
    platform) and were delivered there by the gateway itself — never mirror them."""
    return "gateway" in sys.argv[1:3]


# ── persistent plugin state (webhooks, avatars, last error) ─────────────

_state_lock = threading.Lock()


def _state_path() -> Path:
    return hermes_home() / "cache" / PLUGIN_ID / "state.json"


def _load_state() -> dict:
    try:
        return json.loads(_state_path().read_text())
    except (OSError, ValueError):
        return {}


def _update_state(fn) -> Any:
    with _state_lock:
        st = _load_state()
        out = fn(st)
        p = _state_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps(st, indent=1))
        os.chmod(tmp, 0o600)  # holds webhook tokens
        tmp.replace(p)
        return out


# ── Discord REST ────────────────────────────────────────────────────────

class DiscordError(RuntimeError):
    def __init__(self, status: int, body: str):
        super().__init__(f"Discord HTTP {status}: {body[:300]}")
        self.status = status


def _request(method: str, url: str, *, token: Optional[str] = None, payload: Any = None,
             files: Optional[list] = None, timeout: float = 20) -> Any:
    headers = {"User-Agent": USER_AGENT}
    if token:
        headers["Authorization"] = f"Bot {token}"
    data = None
    if files:
        boundary = uuid.uuid4().hex
        parts = []
        if payload is not None:
            parts.append(
                f'--{boundary}\r\nContent-Disposition: form-data; name="payload_json"\r\n'
                f"Content-Type: application/json\r\n\r\n{json.dumps(payload)}\r\n".encode())
        for i, (name, blob) in enumerate(files):
            ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
            parts.append(
                f'--{boundary}\r\nContent-Disposition: form-data; name="files[{i}]"; '
                f'filename="{name}"\r\nContent-Type: {ctype}\r\n\r\n'.encode() + blob + b"\r\n")
        parts.append(f"--{boundary}--\r\n".encode())
        data = b"".join(parts)
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    for attempt in range(4):
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            if e.code == 429 and attempt < 3:
                try:
                    wait = float(json.loads(body).get("retry_after", 1))
                except ValueError:
                    wait = 1.0
                time.sleep(min(wait, 10) + 0.2)
                continue
            raise DiscordError(e.code, body) from None
    raise DiscordError(429, "rate limited")


def api(method: str, path: str, *, payload: Any = None, files: Optional[list] = None,
        token: Optional[str] = None) -> Any:
    tok = token or bot_token()
    if not tok:
        raise RuntimeError("DISCORD_BOT_TOKEN is not configured")
    return _request(method, API + path, token=tok, payload=payload, files=files)


# ── state.db ────────────────────────────────────────────────────────────

def _db() -> sqlite3.Connection:
    path = hermes_home() / "state.db"
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5)
    conn.row_factory = sqlite3.Row
    return conn


def _compression_tip(session_id: str) -> str:
    """Follow compression successors (the same seam the gateway's transcript reads use)."""
    try:
        from hermes_state import SessionDB

        db = SessionDB(db_path=str(hermes_home() / "state.db"), read_only=True)
        try:
            return db.get_compression_tip(session_id) or session_id
        finally:
            close = getattr(db, "close", None)
            if close:
                close()
    except Exception:
        return session_id


def binding_for_session(session_id: str) -> Optional[dict]:
    """Discord target of a session (walks parent links, e.g. compression lineage)."""
    seen: set = set()
    sid: Optional[str] = session_id
    with closing(_db()) as c:
        while sid and sid not in seen:
            seen.add(sid)
            row = c.execute(
                "select source, chat_id, thread_id, chat_type, origin_json, parent_session_id "
                "from sessions where id = ?", (sid,)).fetchone()
            if row is None:
                return None
            if row["source"] == "discord" and row["chat_id"]:
                try:
                    origin = json.loads(row["origin_json"] or "{}")
                except ValueError:
                    origin = {}
                return {
                    "target": row["thread_id"] or row["chat_id"],
                    "thread_id": row["thread_id"],
                    "chat_id": row["chat_id"],
                    "chat_type": row["chat_type"] or origin.get("chat_type") or "",
                    "user_id": origin.get("user_id"),
                    "user_name": origin.get("user_name"),
                }
            sid = row["parent_session_id"]
    return None


def discord_sessions() -> dict:
    """target channel/thread id -> newest Discord-bound session for it."""
    out: dict = {}
    with closing(_db()) as c:
        rows = c.execute(
            "select id, title, chat_id, thread_id, started_at, last_activity_at, message_count, "
            "coalesce(archived, 0) as archived, coalesce(hidden, 0) as hidden "
            "from sessions where source = 'discord' and chat_id is not null").fetchall()
    for r in rows:
        if r["hidden"]:
            continue
        target = r["thread_id"] or r["chat_id"]
        last = r["last_activity_at"] or r["started_at"] or 0
        cur = out.get(target)
        if cur is None or last > cur["last_active"]:
            out[target] = {
                "id": r["id"],
                "title": r["title"] or "",
                "last_active": last,
                "messages": r["message_count"] or 0,
                "archived": bool(r["archived"]),
            }
    for s in out.values():
        s["id"] = _compression_tip(s["id"])
    return out


# ── server structure (cached) ───────────────────────────────────────────

_struct_cache: dict = {"at": 0.0, "data": None}
_struct_lock = threading.Lock()


def _archived_threads(channel_id: str) -> list:
    try:
        res = api("GET", f"/channels/{channel_id}/threads/archived/public?limit=50")
        return res.get("threads", []) if isinstance(res, dict) else []
    except DiscordError as e:
        if e.status in (403, 404):
            return []
        raise


def discord_structure(force: bool = False) -> list:
    with _struct_lock:
        if not force and _struct_cache["data"] is not None and time.time() - _struct_cache["at"] < STRUCT_TTL:
            return _struct_cache["data"]
        guilds = []
        for g in api("GET", "/users/@me/guilds") or []:
            gid = g["id"]
            channels = api("GET", f"/guilds/{gid}/channels") or []
            active = (api("GET", f"/guilds/{gid}/threads/active") or {}).get("threads", [])
            threads = {t["id"]: t for t in active}
            for ch in channels:
                if ch.get("type") in (T_FORUM, T_MEDIA, T_TEXT, T_NEWS):
                    for t in _archived_threads(ch["id"]):
                        threads.setdefault(t["id"], t)
            guilds.append({"id": gid, "name": g.get("name", gid), "icon": g.get("icon"),
                           "channels": channels, "threads": list(threads.values())})
        _struct_cache.update(at=time.time(), data=guilds)
        return guilds


def _snowflake_ts(sid: str) -> float:
    try:
        return ((int(sid) >> 22) + 1420070400000) / 1000.0
    except (TypeError, ValueError):
        return 0.0


def _thread_ts(t: dict) -> float:
    meta = t.get("thread_metadata") or {}
    best = _snowflake_ts(t.get("last_message_id") or t["id"])
    for key in ("archive_timestamp", "create_timestamp"):
        v = meta.get(key)
        if v:
            try:
                from datetime import datetime

                best = max(best, datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp())
            except ValueError:
                pass
    return best


def _kind_of(ctype: Any) -> str:
    return {T_TEXT: "text", T_NEWS: "announcement", T_FORUM: "forum", T_MEDIA: "media",
            T_VOICE: "voice", T_STAGE: "stage", T_CATEGORY: "category"}.get(ctype, "other")


def build_tree(force: bool = False) -> dict:
    if not bot_token():
        return {"ok": False, "error": "DISCORD_BOT_TOKEN is not configured on this Hermes backend", "guilds": []}
    try:
        structure = discord_structure(force)
    except Exception as e:  # noqa: BLE001 — surface to the UI, never 500
        log.warning("discord-mirror: structure fetch failed: %s", e)
        return {"ok": False, "error": str(e), "guilds": []}
    sessions = discord_sessions()
    out = []
    for g in structure:
        gid = g["id"]
        url = lambda cid: f"https://discord.com/channels/{gid}/{cid}"  # noqa: E731
        by_parent: dict = {}
        for t in g["threads"]:
            by_parent.setdefault(t.get("parent_id"), []).append(t)
        cats = {c["id"]: {"id": c["id"], "guild_id": gid, "name": c.get("name", ""), "position": c.get("position", 0),
                          "channels": []}
                for c in g["channels"] if c.get("type") == T_CATEGORY}
        loose = {"id": None, "guild_id": gid, "name": "", "position": -1, "channels": []}
        for ch in g["channels"]:
            if ch.get("type") not in LISTED_TYPES:
                continue
            threads = []
            now = time.time()
            for t in by_parent.get(ch["id"], []):
                sess = sessions.get(t["id"])
                meta = t.get("thread_metadata") or {}
                last = max(_thread_ts(t), (sess or {}).get("last_active") or 0)
                # Discord's own "Hide After Inactivity": the API often leaves long-idle threads
                # un-archived, but the client hides them once idle past the thread's window.
                window = int(meta.get("auto_archive_duration") or ch.get("default_auto_archive_duration")
                             or (4320 if ch.get("type") in (T_FORUM, T_MEDIA) else 1440))
                threads.append({
                    "id": t["id"], "name": t.get("name", ""), "url": url(t["id"]),
                    "archived": bool(meta.get("archived")), "locked": bool(meta.get("locked")),
                    "inactive": bool(meta.get("archived")) or now - last > window * 60,
                    "archive_after": window,
                    "message_count": t.get("message_count") or 0,
                    "last_active": last,
                    "session": sess,
                })
            threads.sort(key=lambda t: t["last_active"], reverse=True)
            node = {
                "id": ch["id"], "name": ch.get("name", ""), "type": ch.get("type"),
                "kind": _kind_of(ch.get("type")), "guild_id": gid, "parent_id": ch.get("parent_id"),
                "position": ch.get("position", 0), "topic": ch.get("topic") or "",
                "archive_after": ch.get("default_auto_archive_duration"),
                "tags": [{"id": t["id"], "name": t.get("name", ""), "emoji": t.get("emoji_name")}
                         for t in (ch.get("available_tags") or [])],
                "url": url(ch["id"]), "session": sessions.get(ch["id"]), "threads": threads,
            }
            (cats.get(ch.get("parent_id")) or loose)["channels"].append(node)
        categories = ([loose] if loose["channels"] else []) + sorted(cats.values(), key=lambda c: c["position"])
        order = {"text": 0, "announcement": 0, "forum": 1, "media": 1, "voice": 2, "stage": 2}
        for c in categories:
            c["channels"].sort(key=lambda ch: (order.get(ch["kind"], 3), ch["position"]))
        out.append({"id": gid, "name": g["name"], "categories": categories})
    return {"ok": True, "generated_at": time.time(), "guilds": out}


# ── Hermes -> Discord mirroring ─────────────────────────────────────────

_MEDIA_RE = re.compile(r"^\s*MEDIA:(\S+)\s*$", re.M)


def _text_of(message: Any) -> str:
    """User message text from a plain string or OpenAI-style content parts."""
    if isinstance(message, str):
        return message
    if isinstance(message, list):
        bits = []
        for part in message:
            if isinstance(part, dict):
                if part.get("type") in ("text", "input_text"):
                    bits.append(str(part.get("text", "")))
                elif "image" in str(part.get("type", "")):
                    bits.append("[image]")
            elif isinstance(part, str):
                bits.append(part)
        return "\n".join(b for b in bits if b)
    return ""


def chunk(text: str, limit: int = CHUNK) -> list:
    """Split on line boundaries under ``limit``, re-opening ``` fences across chunks."""
    chunks, cur, fence = [], "", None
    for line in text.split("\n"):
        while len(line) > limit:  # pathological single line
            line_head, line = line[:limit], line[limit:]
            if cur:
                chunks.append(cur)
                cur = ""
            chunks.append(line_head)
        candidate = f"{cur}\n{line}" if cur else line
        if len(candidate) + (4 if fence is not None else 0) > limit:
            chunks.append(cur + ("\n```" if fence is not None else ""))
            cur = (f"```{fence}\n" if fence is not None else "") + line
        else:
            cur = candidate
        stripped = line.strip()
        if stripped.startswith("```"):
            fence = None if fence is not None else stripped[3:].strip()
    if cur.strip():
        chunks.append(cur)
    return [c for c in chunks if c.strip()]


def _parent_channel(channel_id: str) -> tuple:
    """(webhook channel, thread id or None) for a target channel/thread."""
    ch = api("GET", f"/channels/{channel_id}")
    if ch.get("type") in THREAD_TYPES:
        return ch["parent_id"], channel_id
    return channel_id, None


def _webhook_for(channel_id: str) -> dict:
    cached = _load_state().get("webhooks", {}).get(channel_id)
    if cached:
        return cached
    hooks = api("GET", f"/channels/{channel_id}/webhooks") or []
    me = api("GET", "/users/@me")
    hook = next((h for h in hooks if h.get("name") == WEBHOOK_NAME and h.get("token")
                 and (h.get("user") or {}).get("id") == me.get("id")), None)
    if hook is None:
        hook = api("POST", f"/channels/{channel_id}/webhooks", payload={"name": WEBHOOK_NAME})
    rec = {"id": hook["id"], "token": hook["token"]}
    _update_state(lambda st: st.setdefault("webhooks", {}).__setitem__(channel_id, rec))
    return rec


def _identity(user_id: Optional[str], fallback: Optional[str]) -> dict:
    name = fallback or "Hermes desktop"
    if not user_id:
        return {"username": name}
    cached = _load_state().get("users", {}).get(str(user_id))
    if cached and time.time() - cached.get("at", 0) < 86400:
        return {"username": cached["username"], "avatar_url": cached.get("avatar_url")}
    try:
        u = api("GET", f"/users/{user_id}")
        avatar = (f"https://cdn.discordapp.com/avatars/{user_id}/{u['avatar']}.png?size=128"
                  if u.get("avatar") else None)
        rec = {"username": u.get("global_name") or u.get("username") or name, "avatar_url": avatar, "at": time.time()}
        _update_state(lambda st: st.setdefault("users", {}).__setitem__(str(user_id), rec))
        return {"username": rec["username"], "avatar_url": avatar}
    except Exception:  # noqa: BLE001
        return {"username": name}


def execute_webhook(channel_id: str, payload: dict, *, thread_id: Optional[str] = None) -> dict:
    """Post through this plugin's webhook on ``channel_id`` (a text/forum channel, never a
    thread — threads ride ``thread_id``). Recreates the webhook once if it was deleted."""
    qs = "?wait=true" + (f"&thread_id={thread_id}" if thread_id else "")
    for attempt in (0, 1):
        hook = _webhook_for(channel_id)
        try:
            return _request("POST", f"{API}/webhooks/{hook['id']}/{hook['token']}{qs}", payload=payload)
        except DiscordError as e:
            if e.status in (401, 404) and attempt == 0:
                _update_state(lambda st: st.get("webhooks", {}).pop(channel_id, None))
                continue
            raise
    raise RuntimeError("unreachable")


def post_user_message(binding: dict, text: str) -> None:
    """The desktop user's message, posted as them (webhook: their name + avatar)."""
    ident = _identity(binding.get("user_id"), binding.get("user_name"))
    if binding.get("chat_type") == "dm":
        for part in chunk(f"**{ident['username']}** (Hermes desktop):\n{text}"):
            api("POST", f"/channels/{binding['target']}/messages",
                payload={"content": part, "allowed_mentions": {"parse": []}})
        return
    parent, thread = _parent_channel(binding["target"])
    for part in chunk(text):
        execute_webhook(parent, {"content": part, "allowed_mentions": {"parse": []}, **ident}, thread_id=thread)


def post_assistant_message(binding: dict, text: str) -> None:
    """The agent's reply, posted by the bot itself (exactly like a gateway delivery)."""
    files = []
    for path in _MEDIA_RE.findall(text):
        p = Path(path)
        try:
            if p.is_file() and p.stat().st_size <= MAX_UPLOAD:
                files.append((p.name, p.read_bytes()))
        except OSError:
            pass
    body = _MEDIA_RE.sub("", text).strip()
    target = binding["target"]
    for part in chunk(body):
        api("POST", f"/channels/{target}/messages", payload={"content": part, "allowed_mentions": {"parse": []}})
    for name, blob in files:
        api("POST", f"/channels/{target}/messages", payload={"allowed_mentions": {"parse": []}},
            files=[(name, blob)])


# Ordered, off-thread delivery: hooks must never block or fail a turn.
_queue: "queue.Queue[tuple]" = queue.Queue()
_worker: Optional[threading.Thread] = None
_worker_lock = threading.Lock()


def _notify(event: str, payload: dict) -> None:
    try:
        from hermes_cli.plugin_events import broadcast_plugin_event

        broadcast_plugin_event(PLUGIN_ID, event, payload)
    except Exception:  # noqa: BLE001 — not every process has desktop clients
        pass


def _work() -> None:
    while True:
        role, session_id, binding, text = _queue.get()
        try:
            if role == "user":
                post_user_message(binding, text)
            else:
                post_assistant_message(binding, text)
            _update_state(lambda st: st.update(last_ok={"at": time.time(), "session": session_id, "role": role}))
            _notify("mirrored", {"session_id": session_id, "role": role, "target": binding["target"]})
        except Exception as e:  # noqa: BLE001
            log.warning("discord-mirror: %s mirror to %s failed: %s", role, binding.get("target"), e)
            msg = str(e)[:500]
            _update_state(lambda st: st.update(last_error={"at": time.time(), "session": session_id,
                                                            "role": role, "error": msg}))
            _notify("error", {"session_id": session_id, "role": role, "error": msg})
        finally:
            _queue.task_done()


def enqueue(role: str, session_id: str, binding: dict, text: str) -> None:
    global _worker
    with _worker_lock:
        if _worker is None or not _worker.is_alive():
            _worker = threading.Thread(target=_work, name="discord-mirror", daemon=True)
            _worker.start()
    _queue.put((role, session_id, binding, text))


def _binding_or_none(session_id: Any) -> Optional[dict]:
    if not session_id or in_gateway_process() or not bot_token():
        return None
    try:
        return binding_for_session(str(session_id))
    except Exception:  # noqa: BLE001
        log.debug("discord-mirror: binding lookup failed", exc_info=True)
        return None


_topic_cache: dict = {}


def _guidelines_for(binding: dict) -> tuple:
    """(channel name, topic) of the forum/channel a binding lives in; cached 5 minutes."""
    target = binding["target"]
    hit = _topic_cache.get(target)
    if hit and time.time() - hit[0] < STRUCT_TTL:
        return hit[1], hit[2]
    parent, thread = _parent_channel(target)
    ch = api("GET", f"/channels/{parent}") if thread else api("GET", f"/channels/{target}")
    name, topic = ch.get("name", ""), (ch.get("topic") or "").strip()
    _topic_cache[target] = (time.time(), name, topic)
    return name, topic


def _guidelines_context(session_id: str, binding: dict) -> Optional[dict]:
    """Forum post guidelines for a desktop turn, injected once per session and again only when
    the guidelines change (Discord-originated turns already get them via the gateway)."""
    try:
        name, topic = _guidelines_for(binding)
    except Exception:  # noqa: BLE001
        return None
    if not topic:
        return None
    import hashlib

    digest = hashlib.sha1(topic.encode()).hexdigest()[:16]
    if _load_state().get("guidelines", {}).get(session_id) == digest:
        return None
    _update_state(lambda st: st.setdefault("guidelines", {}).__setitem__(session_id, digest))
    where = f"#{name}" if name else "this channel"
    return {"context": (
        f"[Discord context: this conversation is bound to a post in {where}. "
        f"Its post guidelines (set on the channel) apply to this chat:]\n{topic}")}


def on_pre_llm_call(**kw: Any) -> Optional[dict]:
    """Turn start: post the user's message so Discord sees it before the reply, and hand the
    model the channel's post guidelines."""
    binding = _binding_or_none(kw.get("session_id"))
    if not binding:
        return None
    sid = str(kw["session_id"])
    text = _text_of(kw.get("user_message")).strip()
    if text:
        enqueue("user", sid, binding, text)
    return _guidelines_context(sid, binding)


def on_post_llm_call(**kw: Any) -> None:
    """Turn end: post the final reply as the bot."""
    binding = _binding_or_none(kw.get("session_id"))
    if binding:
        text = _text_of(kw.get("assistant_response")).strip()
        if text:
            enqueue("assistant", str(kw["session_id"]), binding, text)


# ── server management (categories, channels, forums) ────────────────────

def _invalidate() -> None:
    with _struct_lock:
        _struct_cache.update(at=0.0, data=None)
    _topic_cache.clear()


def _clean_tags(tags: Any) -> list:
    if isinstance(tags, str):
        tags = tags.split(",")
    out = []
    for t in tags or []:
        name = str(t).strip()[:20]
        if name and name not in out:
            out.append(name)
    return out[:20]


def _archive_window(v: Any) -> Optional[int]:
    """Discord's "Hide After Inactivity" choices, in minutes."""
    try:
        n = int(v)
    except (TypeError, ValueError):
        return None
    return n if n in (60, 1440, 4320, 10080) else None


def create_channel(body: dict) -> dict:
    kind = str(body.get("kind") or "forum").lower()
    if kind not in CHANNEL_KINDS:
        raise ValueError(f"unknown channel kind {kind!r}")
    ctype = CHANNEL_KINDS[kind]
    name = str(body.get("name") or "").strip()[:100]
    guild_id = str(body.get("guild_id") or "")
    if not name or not guild_id:
        raise ValueError("guild_id and name are required")
    payload: dict = {"name": name, "type": ctype}
    if ctype != T_CATEGORY and body.get("parent_id"):
        payload["parent_id"] = str(body["parent_id"])
    topic = str(body.get("topic") or "").strip()
    if topic and ctype in (T_TEXT, T_NEWS, T_FORUM, T_MEDIA):
        payload["topic"] = topic[:TOPIC_LIMIT.get(ctype, 1024)]
    if ctype in (T_FORUM, T_MEDIA):
        tags = _clean_tags(body.get("tags"))
        if tags:
            payload["available_tags"] = [{"name": t} for t in tags]
    if ctype == T_FORUM and body.get("layout") in ("list", "gallery"):
        payload["default_forum_layout"] = {"list": 1, "gallery": 2}[body["layout"]]
    if body.get("nsfw") and ctype != T_CATEGORY:
        payload["nsfw"] = True
    window = _archive_window(body.get("archive_after"))
    if window and ctype in (T_TEXT, T_NEWS, T_FORUM, T_MEDIA):
        payload["default_auto_archive_duration"] = window
    ch = api("POST", f"/guilds/{guild_id}/channels", payload=payload)
    _invalidate()
    return {"ok": True, "channel": {"id": ch["id"], "name": ch.get("name"), "kind": _kind_of(ch.get("type"))}}


def update_channel(channel_id: str, body: dict) -> dict:
    cur = api("GET", f"/channels/{channel_id}")
    ctype = cur.get("type")
    payload: dict = {}
    if body.get("name"):
        payload["name"] = str(body["name"]).strip()[:100]
    if "topic" in body and ctype in (T_TEXT, T_NEWS, T_FORUM, T_MEDIA):
        payload["topic"] = str(body.get("topic") or "").strip()[:TOPIC_LIMIT.get(ctype, 1024)]
    if "tags" in body and ctype in (T_FORUM, T_MEDIA):
        existing = {t.get("name"): t for t in (cur.get("available_tags") or [])}
        payload["available_tags"] = [
            {k: v for k, v in existing[n].items() if k in ("id", "name", "moderated", "emoji_id", "emoji_name")}
            if n in existing else {"name": n}
            for n in _clean_tags(body.get("tags"))
        ]
    if "parent_id" in body and ctype != T_CATEGORY:
        payload["parent_id"] = str(body["parent_id"]) if body.get("parent_id") else None
    window = _archive_window(body.get("archive_after"))
    if window and ctype in (T_TEXT, T_NEWS, T_FORUM, T_MEDIA) and window != cur.get("default_auto_archive_duration"):
        payload["default_auto_archive_duration"] = window
    if not payload:
        return {"ok": True, "unchanged": True}
    ch = api("PATCH", f"/channels/{channel_id}", payload=payload)
    _invalidate()
    return {"ok": True, "channel": {"id": ch["id"], "name": ch.get("name"), "kind": _kind_of(ch.get("type"))}}


# ── new posts / threads / channel chats from the desktop ────────────────

def _env_value(name: str) -> str:
    val = os.environ.get(name, "")
    if val:
        return val
    try:
        for line in (hermes_home() / ".env").read_text().splitlines():
            if line.startswith(f"{name}="):
                return line.split("=", 1)[1].strip().strip("'\"")
    except OSError:
        pass
    return ""


def owner() -> dict:
    """The human the desktop speaks for on Discord: the first allowed user, else whoever last
    talked to the bot in a server channel."""
    uid = next((x.strip() for x in _env_value("DISCORD_ALLOWED_USERS").split(",") if x.strip().isdigit()), None)
    if not uid:
        with closing(_db()) as c:
            for (origin,) in c.execute(
                    "select origin_json from sessions where source = 'discord' and origin_json is not null "
                    "order by started_at desc limit 50"):
                try:
                    o = json.loads(origin)
                except ValueError:
                    continue
                if str(o.get("user_id", "")).isdigit():
                    uid = str(o["user_id"])
                    break
    if not uid:
        raise RuntimeError("cannot tell which Discord user the desktop speaks for (set DISCORD_ALLOWED_USERS)")
    ident = _identity(uid, None)
    return {"user_id": uid, "user_name": ident["username"], "avatar_url": ident.get("avatar_url")}


def session_for_target(target: str) -> Optional[str]:
    with closing(_db()) as c:
        row = c.execute(
            "select id from sessions where source = 'discord' and "
            "(thread_id = ? or (chat_id = ? and thread_id is null)) order by started_at desc limit 1",
            (target, target)).fetchone()
    return _compression_tip(row["id"]) if row else None


def _wait_for_session(target: str, timeout: float) -> Optional[str]:
    end = time.time() + timeout
    while True:
        sid = session_for_target(target)
        if sid or time.time() >= end:
            return sid
        time.sleep(0.5)


def create_post(body: dict) -> dict:
    """New forum/media post, new thread in a text/announcement channel, or (mode=channel) a
    message straight into a text channel — written as the owner via webhook, then handed to the
    gateway as that owner's inbound message, so the gateway binds the session natively, applies
    the channel's guidelines/skills/prompt, and replies in Discord. The desktop then opens it."""
    channel_id = str(body.get("channel_id") or "")
    content = str(body.get("content") or "").strip()
    title = str(body.get("title") or "").strip()[:100]
    mode = body.get("mode") or "thread"
    if not channel_id or not content:
        raise ValueError("channel_id and content are required")
    ch = api("GET", f"/channels/{channel_id}")
    ctype = ch.get("type")
    if ctype not in POSTABLE_TYPES:
        raise ValueError("this channel type does not take posts")
    if not title:
        first = content.splitlines()[0]
        title = (first[:80] + "…") if len(first) > 80 else first
    me = owner()
    ident = {"username": me["user_name"], "allowed_mentions": {"parse": []}}
    if me.get("avatar_url"):
        ident["avatar_url"] = me["avatar_url"]
    parts = chunk(content)
    if ctype in (T_FORUM, T_MEDIA):
        payload = {"content": parts[0], "thread_name": title, **ident}
        tags = [str(t) for t in (body.get("tags") or [])][:5]
        if tags:
            payload["applied_tags"] = tags
        first_msg = execute_webhook(channel_id, payload)
        target = str(first_msg["channel_id"])
        for part in parts[1:]:
            execute_webhook(channel_id, {"content": part, **ident}, thread_id=target)
    elif mode == "channel":
        target, first_msg = channel_id, None
        for part in parts:
            m = execute_webhook(channel_id, {"content": part, **ident})
            first_msg = first_msg or m
    else:
        thread_payload = {"name": title, "type": T_NEWS_THREAD if ctype == T_NEWS else T_PUBLIC_THREAD}
        if ch.get("default_auto_archive_duration"):  # else Discord applies its own default
            thread_payload["auto_archive_duration"] = ch["default_auto_archive_duration"]
        thread = api("POST", f"/channels/{channel_id}/threads", payload=thread_payload)
        target, first_msg = str(thread["id"]), None
        for part in parts:
            m = execute_webhook(channel_id, {"content": part, **ident}, thread_id=target)
            first_msg = first_msg or m
    _invalidate()
    guild = ch.get("guild_id")
    result = {"ok": True, "target": target, "url": f"https://discord.com/channels/{guild}/{target}",
              "dispatched": False, "session_id": None}
    try:
        reply = gateway_dispatch(target, content, me, (first_msg or {}).get("id"))
        result["dispatched"] = bool(reply.get("ok"))
        if not reply.get("ok"):
            result["dispatch_error"] = reply.get("error")
    except Exception as e:  # noqa: BLE001 — the post exists; report why the agent didn't pick it up
        result["dispatch_error"] = str(e)
    if result["dispatched"]:
        result["session_id"] = _wait_for_session(target, 8)
    return result


# ── gateway bridge (serve <-> hermes gateway run) ───────────────────────

def _bridge_dir(kind: str) -> Path:
    d = hermes_home() / "cache" / PLUGIN_ID / "bridge" / kind
    d.mkdir(parents=True, exist_ok=True)
    return d


def _write_json(path: Path, obj: dict) -> None:
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(json.dumps(obj))
    os.chmod(tmp, 0o600)
    tmp.replace(path)


def gateway_dispatch(target: str, text: str, user: dict, message_id: Optional[str], timeout: float = 20) -> dict:
    """Ask the gateway-side bridge to treat ``text`` as ``user``'s inbound message in ``target``."""
    rid = uuid.uuid4().hex
    req = {"id": rid, "at": time.time(), "op": "dispatch", "channel_id": target, "text": text,
           "user_id": user["user_id"], "user_name": user.get("user_name") or "", "message_id": message_id}
    _write_json(_bridge_dir("req") / f"{rid}.json", req)
    resp_path = _bridge_dir("resp") / f"{rid}.json"
    end = time.time() + timeout
    while time.time() < end:
        if resp_path.exists():
            try:
                resp = json.loads(resp_path.read_text())
            except ValueError:
                time.sleep(0.2)
                continue
            resp_path.unlink(missing_ok=True)
            return resp
        time.sleep(0.25)
    (_bridge_dir("req") / f"{rid}.json").unlink(missing_ok=True)
    raise RuntimeError("the gateway bridge did not answer — hermes-agent has not loaded discord-mirror "
                       "yet (restart the gateway once after enabling the plugin)")


_bridge_thread: Optional[threading.Thread] = None
_bridge_tasks: set = set()


def start_gateway_bridge() -> None:
    """Gateway process only: serve dispatch requests from the backend half."""
    global _bridge_thread
    if not in_gateway_process() or (_bridge_thread and _bridge_thread.is_alive()):
        return
    _bridge_thread = threading.Thread(target=_bridge_loop, name="discord-mirror-bridge", daemon=True)
    _bridge_thread.start()


def _bridge_loop() -> None:
    beat = 0.0
    while True:
        try:
            if time.time() - beat > 10:
                _write_json(_bridge_dir("hb") / "gateway.json", {"at": time.time(), "pid": os.getpid()})
                beat = time.time()
            for path in sorted(_bridge_dir("req").glob("*.json")):
                try:
                    req = json.loads(path.read_text())
                except ValueError:
                    continue
                path.unlink(missing_ok=True)
                if time.time() - float(req.get("at", 0)) > 60:
                    continue  # its caller gave up long ago
                try:
                    resp = _bridge_handle(req)
                except Exception as e:  # noqa: BLE001
                    log.warning("discord-mirror bridge: %s failed: %s", req.get("op"), e, exc_info=True)
                    resp = {"ok": False, "error": str(e)}
                _write_json(_bridge_dir("resp") / f"{req['id']}.json", resp)
        except Exception:  # noqa: BLE001 — the bridge must never die
            log.warning("discord-mirror bridge loop error", exc_info=True)
        time.sleep(0.5)


def _bridge_handle(req: dict) -> dict:
    import asyncio

    from hermes_cli import plugins as hp

    host = getattr(hp, "_published_gateway_message_injector", None)
    runner = host[0] if host else None
    loop = getattr(runner, "_gateway_loop", None)
    if runner is None or loop is None or loop.is_closed() or not getattr(runner, "_running", False):
        return {"ok": False, "error": "gateway is not running yet"}
    from gateway.config import Platform

    adapter = (getattr(runner, "adapters", None) or {}).get(Platform.DISCORD)
    if adapter is None or getattr(adapter, "_client", None) is None:
        return {"ok": False, "error": "Discord is not connected in this gateway"}
    if req.get("op") != "dispatch":
        return {"ok": False, "error": f"unknown op {req.get('op')!r}"}
    fut = asyncio.run_coroutine_threadsafe(_bridge_dispatch(adapter, req), loop)
    return fut.result(timeout=20)


async def _bridge_dispatch(adapter: Any, req: dict) -> dict:
    """Build the MessageEvent the Discord adapter would build for a human message in this
    channel/thread (same source shape -> same session key) and hand it to handle_message."""
    import asyncio

    import discord
    from gateway.platforms.event import MessageEvent, MessageType

    client = adapter._client
    cid = int(req["channel_id"])
    ch = client.get_channel(cid) or await client.fetch_channel(cid)
    guild = getattr(ch, "guild", None)
    is_thread = isinstance(ch, discord.Thread)
    if is_thread:
        chat_type, thread_id = "thread", str(ch.id)
        fmt = getattr(adapter, "_format_thread_chat_name", None)
        chat_name = fmt(ch) if fmt else ch.name
        parent_id = str(ch.parent_id) if getattr(ch, "parent_id", None) else None
    else:
        chat_type, thread_id, parent_id = "group", None, None
        chat_name = f"{guild.name} / #{ch.name}" if guild else ch.name
    topic = adapter._get_effective_topic(ch, is_thread=is_thread)
    source = adapter.build_source(
        chat_id=str(ch.id), chat_name=chat_name, chat_type=chat_type,
        user_id=str(req["user_id"]), user_name=req.get("user_name") or "",
        thread_id=thread_id, chat_topic=topic, is_bot=False,
        guild_id=str(guild.id) if guild else None, parent_chat_id=parent_id,
        message_id=req.get("message_id"),
    )
    extra = {}
    for field, resolver in (("auto_skill", "_resolve_channel_skills"), ("channel_prompt", "_resolve_channel_prompt")):
        fn = getattr(adapter, resolver, None)
        if fn:
            extra[field] = fn(str(ch.id), parent_id)
    event = MessageEvent(text=req["text"], message_type=MessageType.TEXT, source=source,
                         message_id=req.get("message_id"), **extra)
    tracker = getattr(adapter, "_threads", None)
    if thread_id and tracker is not None:
        await tracker.mark_async(thread_id)  # follow-ups in this thread need no @mention
    task = asyncio.ensure_future(adapter.handle_message(event))
    _bridge_tasks.add(task)
    task.add_done_callback(_bridge_tasks.discard)
    return {"ok": True, "chat_type": chat_type}


def status() -> dict:
    st = _load_state()
    try:
        hb = json.loads((_bridge_dir("hb") / "gateway.json").read_text())
    except (OSError, ValueError):
        hb = None
    return {
        "ok": bool(bot_token()),
        "token": bool(bot_token()),
        "bridge": bool(hb and time.time() - hb.get("at", 0) < 30),
        "webhooks": len(st.get("webhooks", {})),
        "last_ok": st.get("last_ok"),
        "last_error": st.get("last_error"),
        "queue": _queue.qsize(),
    }
