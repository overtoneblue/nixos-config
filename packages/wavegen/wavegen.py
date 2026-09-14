#!/usr/bin/env python3
"""wavegen — Zero-LLM Matrix bot for WaveSpeedAI image editing.

Transports images from a Matrix room to WaveSpeedAI (ByteDance Seedream V5.0
Pro Edit) and posts the edited result back. No Hermes integration, no LLM, no
E2EE (Matrix client-server REST only).
"""

import asyncio
import json
import logging
import mimetypes
import os
import sys
import time
import uuid
from pathlib import Path
from typing import Any

import httpx

# ── Constants ──────────────────────────────────────────────────────────────

ENV_PREFIX = "WAVEGEN_"

DEFAULTS = {
    "HOMESERVER": "http://127.0.0.1:8008",
    "MATRIX_USER": "@wavegen:cenunix.dev",
    "ALLOWED_SENDER": "@caden:cenunix.dev",
    "API_BASE": "https://api.wavespeed.ai/api/v3",
    "MODEL": "bytedance/seedream-v5.0-pro/edit",
    "STATE_DIR": "/var/lib/wavegen",
    "POLL_TIMEOUT": "300",
    "QUEUE_CAP": "5",
    "PENDING_TTL": "600",
}

STATUS_TERMINAL = frozenset({"completed", "failed", "cancelled", "timeout"})

# ── Logging ────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S%z",
)
log = logging.getLogger("wavegen")


# ── Helpers ────────────────────────────────────────────────────────────────

def env_str(key: str) -> str:
    val = os.environ.get(f"{ENV_PREFIX}{key}") or DEFAULTS.get(key, "")
    assert val, f"{ENV_PREFIX}{key} is required"
    return str(val)


def env_int(key: str) -> int:
    raw = os.environ.get(f"{ENV_PREFIX}{key}", "")
    return int(raw) if raw else int(DEFAULTS[key])


def mask_auth(headers: dict[str, str]) -> dict[str, str]:
    return {k: ("Bearer [REDACTED]" if k.lower() == "authorization" else v)
            for k, v in headers.items()}


def ensure_extension(filename: str, content_type: str) -> str:
    """WaveSpeed requires a file extension (e.g. .png/.jpg). Matrix media IDs
    carry none, so derive one from the Content-Type when it's missing."""
    if Path(filename).suffix:
        return filename
    ext = mimetypes.guess_extension(content_type or "") or ".jpg"
    return f"{filename}{ext}"


def http_error_detail(e: Exception) -> str:
    """Human-usable error text; includes the API response body when present."""
    if isinstance(e, httpx.HTTPStatusError):
        try:
            body = e.response.text.strip()
        except Exception:
            body = ""
        return f"HTTP {e.response.status_code}" + (f": {body[:300]}" if body else "")
    return str(e)


# ── State persistence ──────────────────────────────────────────────────────

class State:
    """Persistent state: sync token + pending image queue."""

    def __init__(self, state_dir: str) -> None:
        self.path = Path(state_dir) / "state.json"
        self.data: dict[str, Any] = {}
        self._load()

    def _load(self) -> None:
        try:
            raw = self.path.read_text()
            self.data = json.loads(raw)
            log.info("State loaded from %s (%d keys)", self.path, len(self.data))
        except (FileNotFoundError, json.JSONDecodeError):
            self.data = {"since": "", "pending": {}}
            log.info("No prior state; starting fresh")

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.data, indent=2))
        tmp.rename(self.path)

    @property
    def since(self) -> str:
        return self.data.get("since", "")

    @since.setter
    def since(self, value: str) -> None:
        self.data["since"] = value

    def pend_image(self, mxc_url: str) -> str:
        """Register a pending image. Returns a ticket ID."""
        tid = str(uuid.uuid4())
        pending = self.data.setdefault("pending", {})
        pending[tid] = {"mxc_url": mxc_url, "ts": time.time()}
        self.save()
        return tid

    def pend_list(self) -> list[tuple[str, str, float]]:
        """Return [(tid, mxc_url, timestamp), ...]."""
        pending = self.data.get("pending", {})
        return [(tid, e["mxc_url"], e["ts"]) for tid, e in pending.items()]

    def pend_remove(self, tid: str) -> None:
        self.data.get("pending", {}).pop(tid, None)
        self.save()

    def pend_clear(self) -> None:
        self.data["pending"] = {}
        self.save()

    def pend_count(self) -> int:
        return len(self.data.get("pending", {}))

    def pend_expired(self, ttl: float) -> list[str]:
        """Return ticket IDs older than ttl seconds, removing them."""
        now = time.time()
        expired: list[str] = []
        pending = self.data.get("pending", {})
        for tid, info in list(pending.items()):
            if now - info.get("ts", 0) > ttl:
                expired.append(tid)
                del pending[tid]
        if expired:
            self.save()
        return expired


# ── WaveSpeed upload ───────────────────────────────────────────────────────

async def wavespeed_upload(
    client: httpx.AsyncClient,
    api_base: str,
    api_key: str,
    data_bytes: bytes,
    filename: str,
    content_type: str = "",
) -> str:
    """Upload bytes to WaveSpeed via two-step ticket flow. Returns download_url."""

    # WaveSpeed requires a file extension on the filename in the ticket
    # request (400 otherwise). Matrix media IDs carry none, so derive one
    # from the content type. Must happen BEFORE the ticket POST.
    filename = ensure_extension(filename, content_type)

    # Step 1: request upload ticket
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {"filename": filename, "size": len(data_bytes)}
    resp = await client.post(
        f"{api_base}/media/uploads",
        headers=headers,
        json=payload,
        timeout=30,
    )
    resp.raise_for_status()
    ticket = resp.json()["data"]
    upload_url = ticket["upload"]["url"]
    upload_method = ticket["upload"].get("method", "PUT")
    upload_headers = dict(ticket["upload"].get("headers", {}))

    # Step 2: upload bytes to the temporary URL
    if "Content-Type" not in upload_headers:
        guessed, _ = mimetypes.guess_type(filename)
        if guessed:
            upload_headers["Content-Type"] = guessed
    put_resp = await client.request(
        method=upload_method,
        url=upload_url,
        headers=upload_headers,
        content=data_bytes,
        timeout=120,
    )
    put_resp.raise_for_status()

    download_url = ticket["download_url"]
    log.info("Uploaded %s -> %s", filename, download_url)
    return download_url


# ── WaveSpeed submit + poll ────────────────────────────────────────────────

async def wavespeed_submit(
    client: httpx.AsyncClient,
    api_base: str,
    api_key: str,
    model: str,
    prompt: str,
    image_urls: list[str],
) -> dict[str, Any]:
    """Submit an edit job. Returns the response JSON."""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    body: dict[str, Any] = {"prompt": prompt, "images": image_urls}
    resp = await client.post(
        f"{api_base}/{model.lstrip('/')}",
        headers=headers,
        json=body,
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()


async def wavespeed_poll(
    client: httpx.AsyncClient,
    api_key: str,
    task_id: str,
    get_url: str,
    timeout_s: int,
) -> dict[str, Any]:
    """Poll a task until terminal or timeout. Returns final result JSON."""
    headers = {"Authorization": f"Bearer {api_key}"}
    deadline = time.monotonic() + timeout_s
    last_status = ""
    while time.monotonic() < deadline:
        resp = await client.get(get_url, headers=headers, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        status = data.get("data", {}).get("status", "unknown")
        if status != last_status:
            log.info("Task %s status: %s", task_id, status)
            last_status = status
        if status in STATUS_TERMINAL:
            return data
        await asyncio.sleep(3)
    return {"code": 408, "message": "timeout",
            "data": {"id": task_id, "status": "timeout"}}


# ── Matrix media helpers ───────────────────────────────────────────────────

async def matrix_get(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    path: str,
    **kw: Any,
) -> httpx.Response:
    headers = kw.pop("headers", {})
    headers.setdefault("Authorization", f"Bearer {token}")
    return await client.get(f"{hs_url}{path}", headers=headers, **kw)


async def matrix_post(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    path: str,
    **kw: Any,
) -> httpx.Response:
    headers = kw.pop("headers", {})
    headers.setdefault("Authorization", f"Bearer {token}")
    if "json" in kw:
        headers.setdefault("Content-Type", "application/json")
    return await client.post(f"{hs_url}{path}", headers=headers, **kw)


async def matrix_download(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    mxc_url: str,
) -> tuple[bytes, str, str]:
    """Download Matrix media. Returns (bytes, filename, content_type)."""
    if not mxc_url.startswith("mxc://"):
        raise ValueError(f"Not an mxc URL: {mxc_url}")
    server, media_id = mxc_url[6:].split("/", 1)
    resp = await matrix_get(
        client, hs_url, token,
        f"/_matrix/client/v1/media/download/{server}/{media_id}",
        timeout=60,
    )
    resp.raise_for_status()
    ct = resp.headers.get("Content-Type", "application/octet-stream")
    filename = media_id
    cd = resp.headers.get("Content-Disposition", "")
    if "filename=" in cd:
        fn_part = cd.split("filename=")[-1].split(";")[0].strip('" ')
        if fn_part:
            filename = fn_part
    return resp.content, filename, ct


async def matrix_upload_media(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    data: bytes,
    filename: str,
    content_type: str,
) -> str:
    """Upload bytes to homeserver. Returns mxc:// URL."""
    resp = await client.post(
        f"{hs_url}/_matrix/media/v3/upload",
        headers={"Authorization": f"Bearer {token}", "Content-Type": content_type},
        content=data,
        params={"filename": filename},
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()["content_uri"]


async def matrix_put(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    path: str,
    **kw: Any,
) -> httpx.Response:
    """PUT with auth headers. Matrix /send/{type}/{txnId} is PUT-only."""
    headers = kw.pop("headers", {})
    headers.setdefault("Authorization", f"Bearer {token}")
    if "json" in kw:
        headers.setdefault("Content-Type", "application/json")
    return await client.put(f"{hs_url}{path}", headers=headers, **kw)


async def send_text(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    room_id: str,
    text: str,
) -> None:
    txn = str(uuid.uuid4())
    await matrix_put(
        client, hs_url, token,
        f"/_matrix/client/v3/rooms/{room_id}/send/m.room.message/{txn}",
        json={"msgtype": "m.text", "body": text},
    )


async def send_image(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    room_id: str,
    mxc_url: str,
    body_text: str,
) -> None:
    txn = str(uuid.uuid4())
    await matrix_put(
        client, hs_url, token,
        f"/_matrix/client/v3/rooms/{room_id}/send/m.room.message/{txn}",
        json={"msgtype": "m.image", "body": body_text, "url": mxc_url},
    )


# ── Event processing ───────────────────────────────────────────────────────

async def handle_invite(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    room_id: str,
    invite_data: dict[str, Any],
    allowed: str,
) -> None:
    inv_state = invite_data.get("invite_state", {})
    sender = ""
    for ev in inv_state.get("events", []):
        if ev.get("type") == "m.room.member" and ev.get("content", {}).get("membership") == "invite":
            sender = ev.get("sender", "")
            break
    if sender != allowed:
        log.info("Ignoring invite from %s", sender)
        return
    log.info("Auto-joining room %s", room_id)
    await matrix_post(client, hs_url, token, f"/_matrix/client/v3/rooms/{room_id}/join", json={})


async def handle_event(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    api_base: str,
    api_key: str,
    model: str,
    state: State,
    poll_timeout: int,
    queue_cap: int,
    pending_ttl: int,
    room_id: str,
    event: dict[str, Any],
    allowed: str,
    my_mxid: str,
) -> None:
    sender = event.get("sender", "")
    content = event.get("content", {})
    if sender == my_mxid or sender != allowed:
        return
    if event.get("type") != "m.room.message" or event.get("state_key") is not None:
        return

    msgtype = content.get("msgtype", "")
    body = content.get("body", "")
    stripped = body.strip()

    # ── help ──
    if msgtype == "m.text" and stripped in ("!help", "help"):
        await send_text(client, hs_url, token, room_id,
                        "wavegen — image editing via Seedream V5.0 Pro Edit on WaveSpeedAI\n\n"
                        "Send image(s) + a text prompt. The bot uploads the images, submits "
                        "the edit, and posts the result back.\n\n"
                        "  help / !help    Show this text\n\n"
                        "Usage:\n"
                        "  1. Attach image(s); caption sets the edit prompt immediately\n"
                        "  2. Or send a separate text message after images\n"
                        "  3. Pending images expire after 10 minutes")
        return

    # ── image message ──
    if msgtype == "m.image":
        url = content.get("url", "")
        if not url:
            return

        # Caption detection. Element X / current spec: m.image carries the
        # file name in the TOP-LEVEL content.filename and the caption in
        # body. Legacy clients (no filename field): file name in body.
        info = content.get("info", {})
        filename = (content.get("filename") or info.get("filename") or body or "").strip()
        is_caption = bool(stripped) and stripped != filename and stripped != Path(filename).stem
        caption = stripped if is_caption else ""

        # Enforce the pending-queue cap before enqueueing.
        if state.pend_count() >= queue_cap:
            await send_text(client, hs_url, token, room_id,
                            "Queue full — send your prompt to flush the pending images first.")
            return

        # Enqueue
        tid = state.pend_image(url)
        log.info("Enqueued image %s -> tid=%s%s", url, tid,
                 f" (caption: {caption!r})" if caption else "")

        if caption:
            # Caption acts as the prompt for ALL pending images (this one
            # plus any sent without captions in the last TTL window).
            await flush_all(client, hs_url, token, api_base, api_key, model,
                            state, poll_timeout, room_id, caption)
        return

    # ── text message (prompt) ──
    if msgtype in ("m.text", "m.notice"):
        prompt = stripped
        if not prompt or prompt in ("!help", "help"):
            return
        if state.pend_count() == 0:
            await send_text(client, hs_url, token, room_id,
                            "No pending images. Send image(s) first.")
            return
        await flush_all(client, hs_url, token, api_base, api_key, model,
                       state, poll_timeout, room_id, prompt)


# ── Job execution ──────────────────────────────────────────────────────────

async def flush_all(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    api_base: str,
    api_key: str,
    model: str,
    state: State,
    poll_timeout: int,
    room_id: str,
    prompt: str,
) -> None:
    """Upload all pending images and submit one job."""
    pending = state.pend_list()
    if not pending:
        return

    image_urls: list[str] = []
    for tid, mxc_url, _ in pending:
        try:
            data, fname, ctype = await matrix_download(client, hs_url, token, mxc_url)
            ws_url = await wavespeed_upload(client, api_base, api_key, data, fname, ctype)
            image_urls.append(ws_url)
        except Exception as e:
            log.error("Failed to process tid %s: %s", tid, e)
            await send_text(client, hs_url, token, room_id, f"Image upload failed: {http_error_detail(e)}")
            return

    state.pend_clear()

    if not image_urls:
        await send_text(client, hs_url, token, room_id, "No images to process.")
        return

    await run_job(client, hs_url, token, api_base, api_key, model,
                 poll_timeout, room_id, prompt, image_urls)


async def flush_job(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    api_base: str,
    api_key: str,
    model: str,
    state: State,
    poll_timeout: int,
    room_id: str,
    prompt: str,
) -> None:
    """Upload the single most recent pending image and submit."""
    pending = state.pend_list()
    if not pending:
        return

    tid, mxc_url, _ = pending[-1]  # most recent
    state.pend_remove(tid)

    try:
        data, fname, ctype = await matrix_download(client, hs_url, token, mxc_url)
        ws_url = await wavespeed_upload(client, api_base, api_key, data, fname, ctype)
    except Exception as e:
        log.error("Failed to process tid %s: %s", tid, e)
        await send_text(client, hs_url, token, room_id, f"Image upload failed: {http_error_detail(e)}")
        return

    await run_job(client, hs_url, token, api_base, api_key, model,
                 poll_timeout, room_id, prompt, [ws_url])


async def run_job(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    api_base: str,
    api_key: str,
    model: str,
    poll_timeout: int,
    room_id: str,
    prompt: str,
    image_urls: list[str],
) -> None:
    """Submit a job, poll, download result, post back."""

    await send_text(client, hs_url, token, room_id, "Processing…")

    # Submit with retry
    for attempt in range(3):
        try:
            submit_data = await wavespeed_submit(client, api_base, api_key, model, prompt, image_urls)
            break
        except httpx.HTTPStatusError as e:
            if attempt < 2 and e.response.status_code in (429, 500, 502, 503, 504):
                delay = 3 if attempt == 0 else 9
                log.warning("Submit HTTP %d, retrying in %ds", e.response.status_code, delay)
                await asyncio.sleep(delay)
                continue
            await send_text(client, hs_url, token, room_id,
                           f"Submit failed ({e.response.status_code}). Try again later.")
            return
        except httpx.RequestError as e:
            if attempt < 2:
                await asyncio.sleep(3)
                continue
            await send_text(client, hs_url, token, room_id,
                           f"Connection error: {e}. Try again later.")
            return
    else:
        return

    task_id = submit_data.get("data", {}).get("id", "")
    get_url = submit_data.get("data", {}).get("urls", {}).get("get", "")
    if not task_id:
        await send_text(client, hs_url, token, room_id, "Submit OK but no task ID returned.")
        return

    log.info("Job submitted: task_id=%s", task_id)

    t_start = time.time()
    result = await wavespeed_poll(client, api_key, task_id, get_url, poll_timeout)
    elapsed = int(time.time() - t_start)
    status = result.get("data", {}).get("status", "unknown")

    if status == "completed":
        outputs = result.get("data", {}).get("outputs", [])
        if not outputs:
            await send_text(client, hs_url, token, room_id,
                           f"Edit completed but no outputs ({elapsed}s).")
            return

        out_url = outputs[0]
        log.info("Job completed: output=%s (%ds)", out_url, elapsed)

        try:
            resp = await client.get(out_url, timeout=60)
            resp.raise_for_status()
            out_ct = resp.headers.get("Content-Type", "image/png")
            out_data = resp.content
            out_fn = f"wavegen_{task_id[:8]}.{out_ct.split('/')[-1] or 'png'}"
            mxc = await matrix_upload_media(client, hs_url, token, out_data, out_fn, out_ct)
            await send_image(client, hs_url, token, room_id, mxc,
                             f"Edited: {prompt} ({elapsed}s)")
        except Exception as e:
            await send_text(client, hs_url, token, room_id,
                           f"Result available but failed to relay: {e}\nDirect URL: {out_url}")

    elif status in ("failed", "cancelled", "timeout"):
        err = result.get("data", {}).get("error", result.get("message", status))
        await send_text(client, hs_url, token, room_id,
                       f"Edit {status}. Task {task_id}: {err}")
    else:
        await send_text(client, hs_url, token, room_id,
                       f"Unexpected status '{status}' for task {task_id}")


# ── Sync loop ──────────────────────────────────────────────────────────────

async def sync_loop(
    client: httpx.AsyncClient,
    hs_url: str,
    token: str,
    allowed: str,
    api_base: str,
    api_key: str,
    model: str,
    state: State,
    poll_timeout: int,
    queue_cap: int,
    pending_ttl: int,
) -> None:

    while True:
        params = {"timeout": 30000}
        if state.since:
            params["since"] = state.since

        try:
            resp = await matrix_get(
                client, hs_url, token, "/_matrix/client/v3/sync",
                params=params, timeout=35,
            )
            resp.raise_for_status()
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 401:
                log.critical("Token rejected (401) — exiting")
                raise
            log.error("Sync HTTP %d, retrying in 10s", e.response.status_code)
            await asyncio.sleep(10)
            continue
        except httpx.RequestError as e:
            log.warning("Sync connection error: %s, retrying in 10s", e)
            await asyncio.sleep(10)
            continue

        sync_data = resp.json()
        state.since = sync_data.get("next_batch", state.since)

        # Verify auth periodically
        whoami = None
        if not hasattr(sync_loop, "_whoami_ok"):
            try:
                wr = await matrix_get(client, hs_url, token, "/_matrix/client/v3/account/whoami")
                whoami = wr.json()["user_id"]
                log.info("Authenticated as %s", whoami)
                sync_loop._whoami_ok = True  # type: ignore[attr-defined]
            except Exception as e:
                log.error("Whoami failed: %s", e)
                raise

        # Process invites
        for room_id, invite_data in sync_data.get("rooms", {}).get("invite", {}).items():
            await handle_invite(client, hs_url, token, room_id, invite_data, allowed)

        # Process messages
        for room_id, room_data in sync_data.get("rooms", {}).get("join", {}).items():
            for event in room_data.get("timeline", {}).get("events", []):
                await handle_event(client, hs_url, token, api_base, api_key, model,
                                   state, poll_timeout, queue_cap, pending_ttl,
                                   room_id, event, allowed, whoami or "")

        # Expire old pending
        expired = state.pend_expired(pending_ttl)
        for tid in expired:
            log.info("Pending image %s expired", tid)

        state.save()


# ── Doctor ─────────────────────────────────────────────────────────────────

async def doctor() -> None:
    results: list[str] = []
    fail = False

    hs_url = env_str("HOMESERVER")
    token = env_str("MATRIX_TOKEN")
    api_base = env_str("API_BASE")
    api_key = env_str("WAVESPEED_API_KEY")
    matrix_user = env_str("MATRIX_USER")

    # 1 env
    results.append(f"[CHECK] MATRIX_TOKEN present: {bool(token)}")
    results.append(f"[CHECK] WAVESPEED_API_KEY present: {bool(api_key)}")

    async with httpx.AsyncClient(timeout=15) as client:
        # 2 homeserver reachable
        try:
            r = await client.get(f"{hs_url}/_matrix/client/v3/versions")
            if r.status_code == 200:
                results.append("[ PASS] Homeserver reachable (200 OK)")
            else:
                results.append(f"[FAIL] Homeserver returned {r.status_code}")
                fail = True
        except Exception as e:
            results.append(f"[FAIL] Homeserver unreachable: {e}")
            fail = True

        # 3 whoami
        try:
            r = await matrix_get(client, hs_url, token, "/_matrix/client/v3/account/whoami")
            if r.status_code == 200:
                uid = r.json()["user_id"]
                match = "✓" if uid == matrix_user else "✗"
                results.append(f"[{ 'PASS' if uid == matrix_user else 'FAIL'}] Whoami: {uid} ({match} expected {matrix_user})")
                if uid != matrix_user:
                    fail = True
            else:
                results.append(f"[FAIL] Whoami returned {r.status_code}")
                fail = True
        except Exception as e:
            results.append(f"[FAIL] Whoami error: {e}")
            fail = True

        # 4 wavespeed endpoint (expect 401 without valid key or 200 with)
        try:
            r = await client.get(f"{api_base}/predictions/dummy/result", timeout=10)
            if r.status_code == 401:
                results.append("[ PASS] WaveSpeed endpoint reachable (returned 401 — expected without valid key)")
            else:
                results.append(f"[ INFO] WaveSpeed endpoint responded {r.status_code}")
        except Exception as e:
            results.append(f"[FAIL] WaveSpeed endpoint unreachable: {e}")
            fail = True

    print("\n".join(results))
    sys.exit(1 if fail else 0)


# ── Main ───────────────────────────────────────────────────────────────────

async def main() -> None:
    if "--doctor" in sys.argv:
        await doctor()
        return

    hs_url = env_str("HOMESERVER")
    token = env_str("MATRIX_TOKEN")
    allowed = env_str("ALLOWED_SENDER")
    api_base = env_str("API_BASE")
    model = env_str("MODEL")
    api_key = env_str("WAVESPEED_API_KEY")
    state_dir = env_str("STATE_DIR")
    poll_timeout = env_int("POLL_TIMEOUT")
    queue_cap = env_int("QUEUE_CAP")
    pending_ttl = env_int("PENDING_TTL")

    log.info("wavegen starting — user=%s, hs=%s", env_str("MATRIX_USER"), hs_url)

    state = State(state_dir)

    async with httpx.AsyncClient(timeout=30) as client:
        try:
            await sync_loop(client, hs_url, token, allowed, api_base, api_key, model,
                           state, poll_timeout, queue_cap, pending_ttl)
        except Exception:
            log.exception("Fatal error")
            sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())


def run() -> None:
    """Console-script entry point (project.scripts.wavegen)."""
    asyncio.run(main())