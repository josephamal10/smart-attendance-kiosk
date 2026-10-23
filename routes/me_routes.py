"""
Employee self-service, opened from the kiosk after a successful face check-in.

There's no employee password: the kiosk's check-in response includes a `self_token`
(type "self", valid a few minutes, for that one person) which these endpoints accept.
"""
import os
import socket
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import Response
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from auth import create_access_token, decode_token
from database import get_db
from models import AttendanceLog, CorrectionRequest, Employee, LeaveRequest, ShiftChange
from schemas import (CorrectionIn, CorrectionOut, LeaveIn, LeaveOut, NoticeOut, ShiftChangeIn,
                     ShiftChangeOut)
from services import me_service, register, report_pdf
from services import rules as R
from services.settings_service import get as get_setting

router = APIRouter(prefix="/me", tags=["Self-service"])
# The QR code on the dashboard points here; the link itself is the (short-lived) permission
public_router = APIRouter(tags=["Self-service"])
REPORT_LINK_MINUTES = 10
_bearer = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=True)


def get_self(token: str = Depends(_bearer), db: Session = Depends(get_db)) -> Employee:
    payload = decode_token(token)
    if not payload or payload.get("type") != "self":
        raise HTTPException(status_code=401, detail="Please scan your face at the kiosk again.")
    emp = db.get(Employee, int(payload["sub"]))
    if not emp or not emp.is_active:
        raise HTTPException(status_code=401, detail="Account not found or disabled")
    return emp


@router.get("")
def my_summary(year: int | None = Query(None, ge=2000, le=2100), month: int | None = Query(None, ge=1, le=12),
               emp: Employee = Depends(get_self), db: Session = Depends(get_db)):
    """The whole dashboard in one call. `year`/`month` pick the calendar month (default: this month)."""
    today = date.today()
    month_start = today.replace(day=1)
    rules = R.Rules.load(db)
    holidays = R.holidays_between(db, month_start, today)
    workdays = set(R.working_days(rules, holidays, month_start, today))
    leave = R.leave_days(db, emp.id, month_start, today).get(emp.id, set())
    at_home = R.leave_days(db, emp.id, month_start, today, wfh=True).get(emp.id, set()) & workdays

    logs = (db.query(AttendanceLog).filter(AttendanceLog.employee_id == emp.id,
                                           AttendanceLog.date >= (today - timedelta(days=45)).isoformat())
              .order_by(AttendanceLog.date.desc()).all())
    month_logs = [l for l in logs if date.fromisoformat(l.date) >= month_start]
    evals = {l.id: R.evaluate(l, rules) for l in logs}
    worked = [evals[l.id].worked_minutes for l in month_logs if evals[l.id].worked_minutes]

    cal_year, cal_month = year or today.year, month or today.month
    reg = register.build(db, cal_year, cal_month, [emp.id])
    history = me_service.History(db, emp, today)
    streak = me_service.streaks(history)

    return {
        "name": emp.name,
        "category": emp.category,
        "month": {
            "present": len({date.fromisoformat(l.date) for l in month_logs} & workdays | at_home),
            "late": sum(1 for l in month_logs if "late" in evals[l.id].flags),
            "leave": len(leave & workdays),
            "wfh": len(at_home),
            "absent": len([d for d in workdays if d < today and d not in leave and d not in at_home
                           and d.isoformat() not in {l.date for l in month_logs}]),
            "working_days": len(workdays),
            "avg_hours": round(sum(worked) / len(worked) / 60, 1) if worked else None,
            "overtime_hours": round(sum(evals[l.id].overtime_minutes for l in month_logs) / 60, 1),
        },
        "calendar": {
            "year": cal_year, "month": cal_month, "month_name": reg["month_name"],
            "days": reg["days"],
            "row": reg["rows"][0] if reg["rows"] else None,
        },
        "weekly_hours": me_service.weekly_hours(history),
        "streak": streak,
        "badges": me_service.badges(history, streak),
        "leave_balance": me_service.leave_balance(db, emp, today.year),
        "updates": me_service.updates(db, emp),
        "notices": [NoticeOut.model_validate(n).model_dump(mode="json") for n in me_service.active_notices(db)],
        "team": me_service.team(db, emp),
        "recent": [{
            "date": l.date,
            "in_time": l.in_time,
            "out_time": l.out_time,
            "flags": evals[l.id].flags,
            "late_minutes": evals[l.id].late_minutes,
            "early_minutes": evals[l.id].early_minutes,
            "worked_minutes": evals[l.id].worked_minutes,
        } for l in logs[:14]],
        "leave_requests": [LeaveOut.model_validate(lr).model_dump(mode="json") for lr in
                           db.query(LeaveRequest).filter(LeaveRequest.employee_id == emp.id)
                             .order_by(LeaveRequest.created_at.desc()).limit(5).all()],
    }


@router.post("/leave", response_model=LeaveOut)
def request_leave(data: LeaveIn, emp: Employee = Depends(get_self), db: Session = Depends(get_db)):
    if data.start_date < date.today() - timedelta(days=30):
        raise HTTPException(status_code=422, detail="Leave can't start more than 30 days ago.")
    lr = LeaveRequest(employee_id=emp.id, start_date=data.start_date, end_date=data.end_date,
                      kind=data.kind, reason=data.reason, status="pending")
    db.add(lr)
    db.commit()
    db.refresh(lr)
    return lr


@router.post("/shift-change", response_model=ShiftChangeOut)
def request_shift_change(data: ShiftChangeIn, emp: Employee = Depends(get_self), db: Session = Depends(get_db)):
    """Ask to work different hours on one day. Once approved, that day is judged by them."""
    if data.date < date.today() - timedelta(days=7):
        raise HTTPException(status_code=422, detail="Shift changes can only be asked for up to a week back.")
    if data.date > date.today() + timedelta(days=90):
        raise HTTPException(status_code=422, detail="That's more than 3 months away.")
    sc = ShiftChange(employee_id=emp.id, date=data.date, start=data.start, end=data.end, reason=data.reason)
    db.add(sc)
    db.commit()
    db.refresh(sc)
    return sc


@router.post("/corrections", response_model=CorrectionOut)
def report_problem(data: CorrectionIn, emp: Employee = Depends(get_self), db: Session = Depends(get_db)):
    if data.date > date.today():
        raise HTTPException(status_code=422, detail="That date is in the future.")
    cr = CorrectionRequest(employee_id=emp.id, date=data.date, kind=data.kind, note=data.note)
    db.add(cr)
    db.commit()
    db.refresh(cr)
    return cr


# ── My report (PDF) ──────────────────────────────────────────────────────────

def _report_pdf(db: Session, emp: Employee, year: int, month: int) -> Response:
    reg = register.build(db, year, month, [emp.id])
    if not reg["rows"]:
        raise HTTPException(status_code=404, detail="No report for this account")
    pdf = report_pdf.build(get_setting(db, "company_name"), reg, reg["rows"][0])
    name = f"{emp.name.replace(' ', '_')}_{year}-{month:02d}.pdf"
    return Response(pdf, media_type="application/pdf",
                    headers={"Content-Disposition": f'inline; filename="{name}"'})


def _month(year: int | None, month: int | None) -> tuple[int, int]:
    today = date.today()
    return year or today.year, month or today.month


@router.get("/report.pdf")
def my_report(year: int | None = Query(None, ge=2000, le=2100), month: int | None = Query(None, ge=1, le=12),
              emp: Employee = Depends(get_self), db: Session = Depends(get_db)):
    return _report_pdf(db, emp, *_month(year, month))


def _lan_ip() -> str | None:
    """This PC's address on the local network (no packets are sent)."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.254.254.254", 1))
            return s.getsockname()[0]
    except OSError:
        return None


def public_base_url(request: Request) -> str:
    """Where a phone can reach this server: PUBLIC_URL if set, else this PC's LAN address.

    run.bat keeps the kiosk's own server on 127.0.0.1 and serves the network over HTTPS on
    HTTPS_PORT, so a link asked for by the kiosk points phones at that HTTPS address."""
    if os.getenv("PUBLIC_URL"):
        return os.getenv("PUBLIC_URL").rstrip("/")
    base = str(request.base_url).rstrip("/")
    if request.url.hostname in ("127.0.0.1", "localhost", "::1"):
        ip = _lan_ip()
        if ip and os.getenv("HTTPS_PORT"):
            return f"https://{ip}:{os.getenv('HTTPS_PORT')}"
        if ip:
            base = base.replace(request.url.hostname, ip, 1)
    return base


@router.post("/report-link")
def my_report_link(request: Request,
                   year: int | None = Query(None, ge=2000, le=2100), month: int | None = Query(None, ge=1, le=12),
                   emp: Employee = Depends(get_self)):
    """A link (shown as a QR code) to download the report on your phone. Works for 10 minutes."""
    y, m = _month(year, month)
    token = create_access_token({"sub": str(emp.id), "type": "report", "y": y, "m": m},
                                expires=timedelta(minutes=REPORT_LINK_MINUTES))
    return {"url": f"{public_base_url(request)}/r/{token}", "expires_in_minutes": REPORT_LINK_MINUTES}


@public_router.get("/r/{token}")
def report_from_link(token: str, db: Session = Depends(get_db)):
    payload = decode_token(token)
    if not payload or payload.get("type") != "report":
        raise HTTPException(status_code=404, detail="This link has expired. Make a new one at the kiosk.")
    emp = db.get(Employee, int(payload["sub"]))
    if not emp or not emp.is_active:
        raise HTTPException(status_code=404, detail="This link has expired. Make a new one at the kiosk.")
    return _report_pdf(db, emp, int(payload["y"]), int(payload["m"]))
