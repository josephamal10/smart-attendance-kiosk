"""
Server-side blink check.

The kiosk app streams camera frames here under a random per-scan session id. The
server watches for an open → closed eye transition and only then hands out a
short-lived, single-use liveness token, bound to that session, which the kiosk
check-in endpoint requires. The app can't skip the check by just POSTing a photo.

A blink defeats a still photo; replayed videos are the anti-spoofing model's job
(services/antispoof_service.py), which runs on the check-in photo.
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
_sessions: dict[str, dict] = {}       # scan session id -> {"baseline": float, "seen": float}
_used_tokens: dict[str, float] = {}   # jti -> expiry (unix time), so tokens are single-use


def observe(session_id: str, ear: float) -> bool:
    """Feed one EAR reading. Returns True once a blink has been seen."""
    now = time.time()
    with _lock:
        # Forget abandoned scans so the dict can't grow forever
        for sid, old in list(_sessions.items()):
            if now - old["seen"] > SESSION_IDLE_SECONDS:
                del _sessions[sid]
        s = _sessions.setdefault(session_id, {"baseline": 0.0, "seen": now})
        s["seen"] = now

        if ear >= OPEN_EAR_MIN:
            s["baseline"] = max(s["baseline"], ear)
            return False
        if s["baseline"] and ear < s["baseline"] * CLOSED_RATIO:
            _sessions.pop(session_id, None)
            return True
        return False


def issue_token(session_id: str) -> str:
    return create_access_token(
        {"sub": session_id, "type": "liveness"},
        expires=timedelta(seconds=LIVENESS_TOKEN_SECONDS),
    )


def consume_token(token: str, session_id: str) -> bool:
    """Valid, unexpired, for this scan session, and never used before."""
    payload = decode_token(token)
    if not payload or payload.get("type") != "liveness" or payload.get("sub") != session_id:
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
