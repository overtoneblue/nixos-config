"""wavegen-web — Starlette web app for WaveSpeedAI image editing.

Mobile-first UI with queue, history, retry, single-password auth.
"""

import logging
import mimetypes
import uuid
from pathlib import Path
from typing import Any

from starlette.applications import Starlette
from starlette.exceptions import HTTPException
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import HTMLResponse, JSONResponse, RedirectResponse, Response
from starlette.routing import Mount, Route
from starlette.staticfiles import StaticFiles

from wavegen_web import env_int, env_str

log = logging.getLogger("wavegen-web")

# ── Paths ──────────────────────────────────────────────────────────────────

HERE = Path(__file__).resolve().parent
STATIC_DIR = HERE / "static"

# ── Auth middleware ────────────────────────────────────────────────────────

AUTH_EXEMPT = frozenset({"/healthz", "/login"})


class AuthMiddleware(BaseHTTPMiddleware):
    """Protect all routes except AUTH_EXEMPT by checking wavegen_session."""

    async def dispatch(self, request: Request, call_next: Any) -> Response:
        path = request.url.path
        if path in AUTH_EXEMPT or path.startswith("/static/"):
            return await call_next(request)

        from wavegen_web.auth import get as get_auth

        token = request.cookies.get("wavegen_session", "")
        if not get_auth().validate(token):
            if path.startswith("/api/"):
                return JSONResponse({"error": "Unauthorized"}, status_code=401)
            return RedirectResponse(url="/login")

        return await call_next(request)


# ── Route handlers ─────────────────────────────────────────────────────────

async def handle_healthz(request: Request) -> Response:
    return Response("ok", media_type="text/plain")


async def handle_login_get(request: Request) -> Response:
    """Show the login page (or redirect to / if already authed)."""
    token = request.cookies.get("wavegen_session", "")
    from wavegen_web.auth import get as get_auth

    if get_auth().validate(token):
        return RedirectResponse(url="/", status_code=303)

    html = _read_static("index.html")
    return HTMLResponse(html)


async def handle_login_post(request: Request) -> Response:
    """Verify password and set session cookie."""
    form = await request.form()
    password = form.get("password", "")
    from wavegen_web.auth import get as get_auth

    if get_auth().check_password(password):
        session_token = get_auth().create_session()
        resp = RedirectResponse(url="/", status_code=303)
        resp.set_cookie(
            key="wavegen_session",
            value=session_token,
            httponly=True,
            samesite="lax",
            max_age=86_400 * 7,  # 7 days
        )
        return resp
    return Response("Invalid password", status_code=403)


async def handle_index(request: Request) -> Response:
    """Serve the single-page app (auth gate is in middleware)."""
    html = _read_static("index.html")
    return HTMLResponse(html)


async def handle_list_runs(request: Request) -> JSONResponse:
    """GET /api/runs?limit=50"""
    from wavegen_web.storage import get as get_storage

    limit = int(request.query_params.get("limit", 50))
    runs = get_storage().list_runs(limit)
    return JSONResponse(runs)


async def handle_create_run(request: Request) -> JSONResponse:
    """POST /api/runs (multipart: files + prompt)."""
    from wavegen_web.storage import get as get_storage
    from wavegen_web.job_engine import get as get_engine

    form = await request.form()
    prompt = form.get("prompt", "").strip()
    if not prompt:
        return JSONResponse({"error": "prompt is required"}, status_code=400)

    # Collect uploaded files
    raw_files = form.getlist("files")
    if not raw_files:
        return JSONResponse({"error": "at least 1 image required"},
                            status_code=400)

    valid_files: list[tuple[str, bytes]] = []
    for f in raw_files:
        if not hasattr(f, "filename") or not f.filename:
            continue
        fname = f.filename
        data = await f.read()
        # Validate
        ext = Path(fname).suffix.lower()
        if ext not in (".jpg", ".jpeg", ".png", ".webp"):
            return JSONResponse(
                {"error": f"Unsupported format: {fname} (jpg/png/webp only)"},
                status_code=400)
        if len(data) > 20 * 1024 * 1024:
            return JSONResponse(
                {"error": f"{fname} exceeds 20 MB limit"}, status_code=400)
        valid_files.append((fname, data))

    if not valid_files:
        return JSONResponse({"error": "no valid images provided"},
                            status_code=400)
    if len(valid_files) > 10:
        return JSONResponse({"error": "maximum 10 images"}, status_code=400)

    # Create run record
    run_id = uuid.uuid4().hex
    get_storage().create_run(run_id, prompt, len(valid_files))

    # Enqueue
    get_engine().enqueue(run_id, valid_files, prompt)

    return JSONResponse({"id": run_id, "status": "queued"}, status_code=201)


async def handle_retry_run(request: Request) -> JSONResponse:
    """POST /api/runs/{id}/retry — creates a new run from original inputs."""
    from wavegen_web.storage import get as get_storage
    from wavegen_web.job_engine import get as get_engine

    run_id = request.path_params["id"]
    original = get_storage().get_run(run_id)
    if not original:
        return JSONResponse({"error": "run not found"}, status_code=404)

    # Re-load original input files from disk
    input_files: list[tuple[str, bytes]] = []
    for idx, fname in enumerate(original["input_filenames"]):
        inp_path = get_storage().input_path(run_id, idx)
        if inp_path and inp_path.exists():
            data = inp_path.read_bytes()
            input_files.append((fname, data))

    if not input_files:
        return JSONResponse({"error": "original input files not found"},
                            status_code=404)

    # Create retry run
    new_id = uuid.uuid4().hex
    get_storage().create_run(new_id, original["prompt"],
                             len(input_files), retry_of=run_id)
    get_engine().enqueue(new_id, input_files, original["prompt"])

    return JSONResponse({"id": new_id, "status": "queued", "retry_of": run_id},
                        status_code=201)


async def handle_get_input(request: Request) -> Response:
    """GET /api/runs/{id}/input/{index} — serve input image bytes."""
    from wavegen_web.storage import get as get_storage

    run_id = request.path_params["id"]
    index = int(request.path_params.get("index", 0)) - 1  # 1-based from URL
    inp_path = get_storage().input_path(run_id, index)
    if not inp_path or not inp_path.exists():
        return JSONResponse({"error": "input not found"}, status_code=404)
    ct, _ = mimetypes.guess_type(str(inp_path))
    return Response(inp_path.read_bytes(),
                    media_type=ct or "application/octet-stream")


async def handle_get_result(request: Request) -> Response:
    """GET /api/runs/{id}/result — serve result image bytes."""
    from wavegen_web.storage import get as get_storage

    run_id = request.path_params["id"]
    res_path = get_storage().result_path(run_id)
    if not res_path or not res_path.exists():
        return JSONResponse({"error": "result not found"}, status_code=404)
    ct, _ = mimetypes.guess_type(str(res_path))
    return Response(res_path.read_bytes(),
                    media_type=ct or "application/octet-stream")


# ── Static file helper ────────────────────────────────────────────────────

_CACHE: dict[str, str] = {}


def _read_static(name: str) -> str:
    """Read a static file, cached in memory."""
    if name not in _CACHE:
        path = STATIC_DIR / name
        _CACHE[name] = path.read_text(encoding="utf-8")
    return _CACHE[name]


# ── App factory ────────────────────────────────────────────────────────────

def create_app() -> Starlette:
    """Build and return the ASGI app. Idempotent for the entry point."""
    from wavegen_web.auth import init as init_auth
    from wavegen_web.storage import init as init_storage
    from wavegen_web.job_engine import init as init_engine

    # ── Config from env ──
    password = env_str("PASSWORD")
    if not password:
        raise RuntimeError("WAVEGEN_WEB_PASSWORD is required")

    api_key = env_str("WAVESPEED_API_KEY")
    if not api_key:
        raise RuntimeError("WAVEGEN_WEB_WAVESPEED_API_KEY is required")

    state_dir = env_str("STATE", "/var/lib/wavegen-web")
    concurrency = env_int("CONCURRENCY", 2)
    poll_timeout = env_int("POLL_TIMEOUT", 300)

    # ── Initialise subsystems ──
    init_auth(password)
    storage = init_storage(state_dir)
    engine = init_engine(storage, api_key, concurrency, poll_timeout)
    storage.mark_stuck_as_failed()

    # ── Routes ──
    routes = [
        Route("/healthz", handle_healthz),
        Route("/login", handle_login_get, methods=["GET"]),
        Route("/login", handle_login_post, methods=["POST"]),
        Route("/", handle_index),
        Route("/api/runs", handle_list_runs, methods=["GET"]),
        Route("/api/runs", handle_create_run, methods=["POST"]),
        Route("/api/runs/{id:str}/retry", handle_retry_run, methods=["POST"]),
        Route("/api/runs/{id:str}/input/{index:int}", handle_get_input,
              methods=["GET"]),
        Route("/api/runs/{id:str}/result", handle_get_result, methods=["GET"]),
        # Static assets (CSS/JS inlined in index.html; this catch-all for
        # /static/* if needed)
        Mount("/static",
              app=StaticFiles(directory=str(STATIC_DIR)),
              name="static"),
    ]

    app = Starlette(
        routes=routes,
        middleware=[Middleware(AuthMiddleware)],
        on_startup=[engine.start],
    )

    log.info("wavegen-web app created — concurrency=%d, poll_timeout=%d",
             concurrency, poll_timeout)
    return app