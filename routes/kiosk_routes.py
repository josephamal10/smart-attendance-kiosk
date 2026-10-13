"""
Walk-up kiosk check-in. No login: the person's face *is* their identity.

    1. POST /kiosk/liveness  (frame, session_id)   repeat until live=true → liveness_token
    2. POST /kiosk/check-in  (frame, session_id, liveness_token)
         → anti-spoofing → 1:N face identification → IN / OUT

The session id is a random string the app makes per scan; the liveness token is bound
to it and single-use, so a check-in always needs a fresh blink in front of the camera.
These endpoints are plain `def` (run in a thread pool) because face models are CPU-bound.
"""
import re

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from database import get_db
from schemas import CheckInResponse, LivenessResponse
from services import liveness_service
from services.attendance_service import mark_attendance
from services.face_service import identify_face, measure_ear

router = APIRouter(prefix="/kiosk", tags=["Kiosk"])

_SESSION_RE = re.compile(r"^[A-Za-z0-9_-]{16,64}$")


def _session(session_id: str) -> str:
    if not _SESSION_RE.match(session_id):
        raise HTTPException(status_code=422, detail="Invalid session id")
    return session_id


@router.post("/liveness", response_model=LivenessResponse)
def liveness_frame(session_id: str = Form(...), file: UploadFile = File(...)):
    sid = _session(session_id)
    m = measure_ear(file.file.read())
    if not m["ok"]:
        return LivenessResponse(live=False, face_found=False, ear=0.0, message=m["message"])

    if liveness_service.observe(sid, m["ear"]):
        return LivenessResponse(live=True, face_found=True, ear=m["ear"], message="Blink detected",
                                liveness_token=liveness_service.issue_token(sid))
    return LivenessResponse(live=False, face_found=True, ear=m["ear"], message="Please blink")


@router.post("/check-in", response_model=CheckInResponse)
def check_in(
    session_id: str = Form(...),
    liveness_token: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    if not liveness_service.consume_token(liveness_token, _session(session_id)):
        raise HTTPException(status_code=403, detail="Liveness check missing or expired. Please blink again.")

    employee, msg = identify_face(db, file.file.read())
    if not employee:
        return CheckInResponse(recognized=False, message=msg)

    result = mark_attendance(db, employee)
    first = employee.name.split()[0]
    messages = {
        "in":       f"Welcome, {first}! Have a great day.",
        "out":      f"See you tomorrow, {first}.",
        "done":     f"{first}, you've already checked in and out today.",
        "too_soon": f"{first}, you just checked in. Scan again later to check out.",
    }
    return CheckInResponse(
        recognized=True,
        employee_id=employee.id,
        name=employee.name,
        category=employee.category,
        action=result["action"],
        time=result["time"],
        message=messages[result["action"]],
    )
