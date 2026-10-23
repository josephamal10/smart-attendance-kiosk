"""
Walk-up kiosk check-in. No login: the person's face *is* their identity.

    1. POST /kiosk/liveness  (frame, session_id)   repeat until live=true → liveness_token
    2. POST /kiosk/check-in  (frame, session_id, liveness_token)
         → anti-spoofing → 1:N face identification → IN / OUT
    or POST /kiosk/identify  (same inputs) → who is this? → a pass for their own dashboard,
         without touching attendance (the "My dashboard" icon on the kiosk)

The session id is a random string the app makes per scan; the liveness token is bound
to it and single-use, so a check-in always needs a fresh blink in front of the camera.
These endpoints are plain `def` (run in a thread pool) because face models are CPU-bound.
"""
import re
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from auth import create_access_token
from database import get_db
from models import Employee
from schemas import CheckInResponse, LivenessResponse
from services import liveness_service, rules as R
from services.attendance_service import mark_attendance
from services.face_service import identify_face, measure_ear
from services.settings_service import get as get_setting

router = APIRouter(prefix="/kiosk", tags=["Kiosk"])

_SESSION_RE = re.compile(r"^[A-Za-z0-9_-]{16,64}$")


def _session(session_id: str) -> str:
    if not _SESSION_RE.match(session_id):
        raise HTTPException(status_code=422, detail="Invalid session id")
    return session_id


@router.get("/info")
def kiosk_info(db: Session = Depends(get_db)):
    """What the lock screen shows before anyone signs in: the company name, today's birthdays
    and work anniversaries (first names only, if enabled) and whether to speak greetings."""
    return {
        "company_name": get_setting(db, "company_name"),
        "voice_greeting": bool(get_setting(db, "voice_greeting")),
        "celebrations": celebrations(db, date.today()) if get_setting(db, "show_celebrations") else [],
    }


def _same_day(d: date, today: date) -> bool:
    if (d.month, d.day) == (today.month, today.day):
        return True
    # 29 Feb birthdays are celebrated on 28 Feb in other years
    leap = today.year % 4 == 0 and (today.year % 100 != 0 or today.year % 400 == 0)
    return (d.month, d.day) == (2, 29) and (today.month, today.day) == (2, 28) and not leap


def celebrations(db: Session, today: date) -> list[dict]:
    out = []
    for e in (db.query(Employee).filter(Employee.role == "user", Employee.is_active == True)  # noqa: E712
                .order_by(Employee.name).all()):
        first = e.name.split()[0]
        if e.birthday and _same_day(e.birthday, today):
            out.append({"kind": "birthday", "name": first, "team": e.category})
        if e.joined_on and e.joined_on.year < today.year and _same_day(e.joined_on, today):
            out.append({"kind": "anniversary", "name": first, "team": e.category,
                        "years": today.year - e.joined_on.year})
    return out


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
    action, log = result["action"], result["log"]
    ev = R.evaluate(log, R.Rules.load(db)) if log else R.Evaluation()
    first = employee.name.split()[0]
    messages = {
        "in":       "Have a great day!",
        "out":      "See you tomorrow!",
        "done":     "You've already checked in and out today.",
        "too_soon": "You just checked in. Scan again later to check out.",
    }
    return CheckInResponse(
        recognized=True,
        employee_id=employee.id,
        name=employee.name,
        category=employee.category,
        action=action,
        time=result["time"],
        message=messages[action],
        greeting=f"{R.greeting(datetime.now())}, {first}!",
        flags=ev.flags,
        late_minutes=ev.late_minutes,
        early_minutes=ev.early_minutes,
        worked_minutes=ev.worked_minutes,
        overtime_minutes=ev.overtime_minutes,
        # Lets this person open "My attendance" for a few minutes, no password needed
        self_token=create_access_token({"sub": str(employee.id), "type": "self"},
                                       expires=timedelta(minutes=3)),
    )


@router.post("/identify", response_model=CheckInResponse)
def identify(
    session_id: str = Form(...),
    liveness_token: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    """Open someone's own dashboard by face. Same blink + anti-spoofing checks as check-in,
    but no attendance is recorded."""
    if not liveness_service.consume_token(liveness_token, _session(session_id)):
        raise HTTPException(status_code=403, detail="Liveness check missing or expired. Please blink again.")

    employee, msg = identify_face(db, file.file.read())
    if not employee:
        return CheckInResponse(recognized=False, message=msg)
    return CheckInResponse(
        recognized=True,
        employee_id=employee.id,
        name=employee.name,
        category=employee.category,
        message="Opening your dashboard",
        greeting=f"{R.greeting(datetime.now())}, {employee.name.split()[0]}!",
        self_token=create_access_token({"sub": str(employee.id), "type": "self"},
                                       expires=timedelta(minutes=5)),
    )
