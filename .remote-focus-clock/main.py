import asyncio
import json
import random
import time
import uuid
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.base import BaseHTTPMiddleware


BASE_DIR = Path(__file__).resolve().parent
STATE_FILE = BASE_DIR / "state.json"
HOUR_MS = 60 * 60 * 1000
BONUS_SESSION_MAX_MS = 2 * HOUR_MS
FOUR_X_MIN_MS = 30 * 60 * 1000
TEN_X_MIN_MS = 45 * 60 * 1000

app = FastAPI(title="Focus Clock")


class NoCacheMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
        return response


app.add_middleware(NoCacheMiddleware)
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))


def now_ms() -> int:
    return int(time.time() * 1000)


def fresh_state() -> dict[str, Any]:
    return {
        "sessions": [],
        "current": {
            "id": uuid.uuid4().hex,
            "type": "productive",
            "startedAt": now_ms(),
            "reason": None,
        },
        "lastVerdict": None,
    }


def load_state() -> dict[str, Any]:
    if STATE_FILE.exists():
        try:
            with STATE_FILE.open("r") as f:
                data = json.load(f)
            if isinstance(data, dict) and "current" in data and "sessions" in data:
                return data
        except Exception:
            pass
    return fresh_state()


def save_state(data: dict[str, Any]) -> None:
    tmp = STATE_FILE.with_suffix(".tmp")
    with tmp.open("w") as f:
        json.dump(data, f)
    tmp.replace(STATE_FILE)


state: dict[str, Any] = load_state()
clients: set[WebSocket] = set()
state_lock = asyncio.Lock()


def state_message() -> str:
    return json.dumps({"type": "state", "state": state, "serverNow": now_ms()})


async def broadcast_state() -> None:
    msg = state_message()
    dead: list[WebSocket] = []
    for ws in clients:
        try:
            await ws.send_text(msg)
        except Exception:
            dead.append(ws)
    for ws in dead:
        clients.discard(ws)


def credited_duration_ms(session: dict[str, Any]) -> int:
    return int(session.get("creditDurationMs", session.get("durationMs", 0)))


def historical_totals() -> tuple[int, int]:
    prod = 0
    bad = 0
    for sess in state["sessions"]:
        credit = credited_duration_ms(sess)
        if sess.get("type") == "productive":
            prod += credit
        else:
            bad += credit
    return prod, bad


def margin_tier(net_before_ms: int) -> str:
    if net_before_ms <= -8 * HOUR_MS:
        return "huge_loss"
    if net_before_ms <= -2 * HOUR_MS:
        return "loss"
    if net_before_ms >= 8 * HOUR_MS:
        return "huge_win"
    if net_before_ms >= 2 * HOUR_MS:
        return "win"
    return "balanced"


def weighted_choice(options: list[dict[str, Any]]) -> dict[str, Any]:
    total = sum(float(opt["weight"]) for opt in options if float(opt["weight"]) > 0)
    if total <= 0:
        return options[0]

    pick = random.uniform(0, total)
    cursor = 0.0
    for opt in options:
        weight = float(opt["weight"])
        if weight <= 0:
            continue
        cursor += weight
        if pick <= cursor:
            return opt
    return options[-1]


def productive_verdict(duration_ms: int) -> dict[str, Any]:
    prod_total, bad_total = historical_totals()
    net_before_ms = prod_total - bad_total
    tier = margin_tier(net_before_ms)
    short_bonus_ok = duration_ms <= BONUS_SESSION_MAX_MS
    four_x_ok = short_bonus_ok and duration_ms >= FOUR_X_MIN_MS
    ten_x_ok = short_bonus_ok and duration_ms >= TEN_X_MIN_MS

    options: list[dict[str, Any]]
    if tier == "huge_win":
        options = [
            {"assigned": "bad", "multiplier": 1.0, "label": "BURNED", "weight": 42},
            {"assigned": "productive", "multiplier": 0.5, "label": "TRIMMED", "weight": 30},
            {"assigned": "productive", "multiplier": 1.0, "label": "BANKED", "weight": 22},
            {"assigned": "productive", "multiplier": 2.0, "label": "DOUBLE", "weight": 6},
        ]
        if four_x_ok:
            options.append({"assigned": "productive", "multiplier": 4.0, "label": "QUAD", "weight": 1})
    elif tier == "win":
        options = [
            {"assigned": "bad", "multiplier": 1.0, "label": "BURNED", "weight": 35},
            {"assigned": "productive", "multiplier": 0.75, "label": "TRIMMED", "weight": 24},
            {"assigned": "productive", "multiplier": 1.0, "label": "BANKED", "weight": 26},
            {"assigned": "productive", "multiplier": 2.0, "label": "DOUBLE", "weight": 13},
        ]
        if four_x_ok:
            options.append({"assigned": "productive", "multiplier": 4.0, "label": "QUAD", "weight": 2})
    elif tier == "loss":
        options = [
            {"assigned": "bad", "multiplier": 1.0, "label": "BURNED", "weight": 15},
            {"assigned": "productive", "multiplier": 1.0, "label": "BANKED", "weight": 30},
            {"assigned": "productive", "multiplier": 2.0, "label": "DOUBLE", "weight": 33},
        ]
        if four_x_ok:
            options.append({"assigned": "productive", "multiplier": 4.0, "label": "QUAD", "weight": 17})
        if ten_x_ok:
            options.append({"assigned": "productive", "multiplier": 10.0, "label": "MEGA", "weight": 5})
    elif tier == "huge_loss":
        options = [
            {"assigned": "bad", "multiplier": 1.0, "label": "BURNED", "weight": 8},
            {"assigned": "productive", "multiplier": 1.0, "label": "BANKED", "weight": 22},
            {"assigned": "productive", "multiplier": 2.0, "label": "DOUBLE", "weight": 30},
        ]
        if four_x_ok:
            options.append({"assigned": "productive", "multiplier": 4.0, "label": "QUAD", "weight": 25})
        if ten_x_ok:
            options.append({"assigned": "productive", "multiplier": 10.0, "label": "MEGA", "weight": 15})
    else:
        options = [
            {"assigned": "bad", "multiplier": 1.0, "label": "BURNED", "weight": 28},
            {"assigned": "productive", "multiplier": 1.0, "label": "BANKED", "weight": 42},
            {"assigned": "productive", "multiplier": 2.0, "label": "DOUBLE", "weight": 22},
        ]
        if four_x_ok:
            options.append({"assigned": "productive", "multiplier": 4.0, "label": "QUAD", "weight": 8})

    choice = weighted_choice(options)
    assigned = str(choice["assigned"])
    multiplier = float(choice["multiplier"])
    credited = duration_ms if assigned == "bad" else max(1000, int(duration_ms * multiplier))
    return {
        "assigned": assigned,
        "multiplier": multiplier,
        "label": choice["label"],
        "creditDurationMs": credited,
        "actualDurationMs": duration_ms,
        "marginBeforeMs": net_before_ms,
        "tier": tier,
    }


def end_current(
    forced_type: str | None = None,
    rolled: bool = False,
    credited_ms: int | None = None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    cur = state["current"]
    now = now_ms()
    actual_duration = max(0, now - cur["startedAt"])
    assigned = forced_type or cur["type"]
    entry = {
        "id": cur["id"],
        "type": assigned,
        "originalType": cur["type"],
        "startedAt": cur["startedAt"],
        "endedAt": now,
        "durationMs": actual_duration if credited_ms is None else max(0, credited_ms),
        "actualDurationMs": actual_duration,
        "creditDurationMs": actual_duration if credited_ms is None else max(0, credited_ms),
        "reason": cur.get("reason"),
        "rolled": rolled,
    }
    if extra:
        entry.update(extra)
    state["sessions"].append(entry)
    return entry


@app.get("/", response_class=HTMLResponse)
async def home(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(request, "index.html")


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket) -> None:
    await ws.accept()
    clients.add(ws)
    try:
        await ws.send_text(state_message())
        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except Exception:
                continue
            mtype = msg.get("type")
            async with state_lock:
                if mtype == "pause" and state["current"]["type"] == "productive":
                    verdict = productive_verdict(max(0, now_ms() - state["current"]["startedAt"]))
                    entry = end_current(
                        forced_type=verdict["assigned"],
                        rolled=True,
                        credited_ms=verdict["creditDurationMs"],
                        extra={
                            "multiplier": verdict["multiplier"],
                            "tier": verdict["tier"],
                            "marginBeforeMs": verdict["marginBeforeMs"],
                        },
                    )
                    state["lastVerdict"] = {
                        "at": now_ms(),
                        "assigned": verdict["assigned"],
                        "originalType": "productive",
                        "actualDurationMs": entry["actualDurationMs"],
                        "creditDurationMs": entry["creditDurationMs"],
                        "multiplier": verdict["multiplier"],
                        "label": verdict["label"],
                        "tier": verdict["tier"],
                        "marginBeforeMs": verdict["marginBeforeMs"],
                        "sessionId": entry["id"],
                    }
                    reason = (msg.get("reason") or "").strip()[:300] or None
                    state["current"] = {
                        "id": uuid.uuid4().hex,
                        "type": "bad",
                        "startedAt": now_ms(),
                        "reason": reason,
                    }
                    save_state(state)
                    await broadcast_state()
                elif mtype == "resume" and state["current"]["type"] == "bad":
                    end_current()
                    state["lastVerdict"] = None
                    state["current"] = {
                        "id": uuid.uuid4().hex,
                        "type": "productive",
                        "startedAt": now_ms(),
                        "reason": None,
                    }
                    save_state(state)
                    await broadcast_state()
                elif mtype == "reset":
                    state.clear()
                    state.update(fresh_state())
                    save_state(state)
                    await broadcast_state()
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        clients.discard(ws)
