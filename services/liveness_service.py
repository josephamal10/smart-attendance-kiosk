"""
Server-side blink check.

Before, the Flutter app decided by itself whether the user blinked, and the
attendance endpoint trusted it — so anyone could skip the check by POSTing a photo.
Now the app streams frames here; the server watches for an open → closed eye
transition and only then hands out a short-lived, single-use liveness token that
/attendance/verify requires.

This stops photo-of-a-photo attacks but not a replayed video; a trained
anti-spoofing model is the next step.
"""
import threading
import time
from datetime import timedelta

from auth import create_access_token, decode_token

LIVENESS_TOKEN_SECONDS = 60
SESSION_IDLE_SECONDS   = 30
OPEN_EAR_MIN           = 0.20   # pixel-space EAR above this = eyes clearly open
CLOSED_RATIO           = 0.60   # closed = EAR below 60% of this person's open baseline

_lock = threading.Lock()
_sessions: dict[int, dict] = {}       # employee_id -> {"baseline": float, "seen": float}
_used_tokens: dict[str, float] = {}   # jti -> expiry (unix time), so tokens are single-use


def observe(employee_id: int, ear: float) -> bool:
    """Feed one EAR reading. Returns True once a blink has been seen."""
    now = time.time()
    with _lock:
        s = _sessions.get(employee_id)
        if not s or now - s["seen"] > SESSION_IDLE_SECONDS:
            s = {"baseline": 0.0, "seen": now}
            _sessions[employee_id] = s
        s["seen"] = now

        if ear >= OPEN_EAR_MIN:
            s["baseline"] = max(s["baseline"], ear)
            return False
        if s["baseline"] and ear < s["baseline"] * CLOSED_RATIO:
            _sessions.pop(employee_id, None)
            return True
        return False


def issue_token(employee_id: int) -> str:
    return create_access_token(
        {"sub": str(employee_id), "type": "liveness"},
        expires=timedelta(seconds=LIVENESS_TOKEN_SECONDS),
    )


def consume_token(token: str, employee_id: int) -> bool:
    """Valid, unexpired, for this employee, and never used before."""
    payload = decode_token(token)
    if not payload or payload.get("type") != "liveness" or payload.get("sub") != str(employee_id):
        return False
    now = time.time()
    with _lock:
        for jti, exp in list(_used_tokens.items()):
            if exp < now:
                del _used_tokens[jti]
        if payload["jti"] in _used_tokens:
            return False
        _used_tokens[payload["jti"]] = payload["exp"]
    return True


def reset() -> None:
    """Clear all in-memory state (used by tests)."""
    with _lock:
        _sessions.clear()
        _used_tokens.clear()
