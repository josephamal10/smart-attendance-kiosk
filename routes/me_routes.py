"""
Employee self-service, opened from the kiosk after a successful face check-in.

There's no employee password: the kiosk's check-in response includes a `self_token`
(type "self", valid a few minutes, for that one person) which these endpoints accept.
"""
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from auth import decode_token
from database import get_db
from models import AttendanceLog, CorrectionRequest, Employee, LeaveRequest
from schemas import CorrectionIn, CorrectionOut, LeaveIn, LeaveOut
from services import rules as R

router = APIRouter(prefix="/me", tags=["Self-service"])
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
def my_summary(emp: Employee = Depends(get_self), db: Session = Depends(get_db)):
    today = date.today()
    month_start = today.replace(day=1)
    rules = R.Rules.load(db)
    holidays = R.holidays_between(db, month_start, today)
    workdays = set(R.working_days(rules, holidays, month_start, today))
    leave = R.leave_days(db, emp.id, month_start, today).get(emp.id, set())

    logs = (db.query(AttendanceLog).filter(AttendanceLog.employee_id == emp.id,
                                           AttendanceLog.date >= (today - timedelta(days=45)).isoformat())
              .order_by(AttendanceLog.date.desc()).all())
    month_logs = [l for l in logs if date.fromisoformat(l.date) >= month_start]
    evals = {l.id: R.evaluate(l, rules) for l in logs}
    worked = [evals[l.id].worked_minutes for l in month_logs if evals[l.id].worked_minutes]

    return {
        "name": emp.name,
        "category": emp.category,
        "month": {
            "present": len([l for l in month_logs if date.fromisoformat(l.date) in workdays]),
            "late": sum(1 for l in month_logs if "late" in evals[l.id].flags),
            "leave": len(leave & workdays),
            "absent": len([d for d in workdays if d < today and d not in leave
                           and d.isoformat() not in {l.date for l in month_logs}]),
            "working_days": len(workdays),
            "avg_hours": round(sum(worked) / len(worked) / 60, 1) if worked else None,
        },
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


@router.post("/corrections", response_model=CorrectionOut)
def report_problem(data: CorrectionIn, emp: Employee = Depends(get_self), db: Session = Depends(get_db)):
    if data.date > date.today():
        raise HTTPException(status_code=422, detail="That date is in the future.")
    cr = CorrectionRequest(employee_id=emp.id, date=data.date, kind=data.kind, note=data.note)
    db.add(cr)
    db.commit()
    db.refresh(cr)
    return cr
