"""Holidays, leave requests and correction requests (admin side)."""
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from auth import require_admin, require_super
from database import get_db
from models import CorrectionRequest, Employee, Holiday, LeaveRequest, ShiftChange
from schemas import (AdminLeaveIn, CorrectionDecision, CorrectionOut, Decision,
                     HolidayIn, HolidayOut, LeaveOut, ShiftChangeOut)
from services import audit

router = APIRouter(prefix="/admin", tags=["Requests"], dependencies=[Depends(require_admin)])

_KIND = {"missed_checkout": "forgot check-out", "wrong_time": "wrong time", "other": "other",
         "sick": "sick leave", "casual": "casual leave", "wfh": "work from home"}


def _d(d: date) -> str:
    return d.strftime("%d %b %Y")


# ── Holidays ─────────────────────────────────────────────────────────────────

@router.get("/holidays", response_model=list[HolidayOut])
def list_holidays(year: int | None = Query(None, ge=2000, le=2100), db: Session = Depends(get_db)):
    q = db.query(Holiday)
    if year:
        q = q.filter(Holiday.date >= date(year, 1, 1), Holiday.date <= date(year, 12, 31))
    return q.order_by(Holiday.date).all()

@router.post("/holidays", response_model=HolidayOut)
def add_holiday(data: HolidayIn, db: Session = Depends(get_db), admin: Employee = Depends(require_super)):
    h = Holiday(date=data.date, name=data.name.strip())
    db.add(h)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="There's already a holiday on that date.")
    audit.record(db, admin, "holiday.added", details=f"{_d(h.date)}: {h.name}")
    db.commit()
    db.refresh(h)
    return h

@router.delete("/holidays/{holiday_id}")
def delete_holiday(holiday_id: int, db: Session = Depends(get_db), admin: Employee = Depends(require_super)):
    h = db.get(Holiday, holiday_id)
    if not h:
        raise HTTPException(status_code=404, detail="Holiday not found")
    audit.record(db, admin, "holiday.removed", details=f"{_d(h.date)}: {h.name}")
    db.delete(h)
    db.commit()
    return {"message": "Holiday removed"}


# ── Leave ────────────────────────────────────────────────────────────────────

@router.get("/leave", response_model=list[LeaveOut])
def list_leave(status: str | None = Query(None, pattern="^(pending|approved|rejected)$"),
               db: Session = Depends(get_db)):
    q = db.query(LeaveRequest)
    if status:
        q = q.filter(LeaveRequest.status == status)
    return q.order_by(LeaveRequest.created_at.desc()).all()

@router.post("/leave", response_model=LeaveOut)
def add_leave(data: AdminLeaveIn, db: Session = Depends(get_db), admin: Employee = Depends(require_super)):
    """Admin records leave directly (already approved)."""
    if not db.get(Employee, data.employee_id):
        raise HTTPException(status_code=404, detail="Employee not found")
    lr = LeaveRequest(employee_id=data.employee_id, start_date=data.start_date, end_date=data.end_date,
                      kind=data.kind, reason=data.reason, status="approved",
                      decided_at=datetime.now(), decided_by=admin.id)
    db.add(lr)
    audit.record(db, admin, "leave.added", employee_id=data.employee_id,
                 details=f"{_KIND[data.kind]}: {_d(data.start_date)} → {_d(data.end_date)}", reason=data.reason)
    db.commit()
    db.refresh(lr)
    return lr

@router.post("/leave/{leave_id}/decision", response_model=LeaveOut)
def decide_leave(leave_id: int, data: Decision, db: Session = Depends(get_db),
                 admin: Employee = Depends(require_super)):
    lr = db.get(LeaveRequest, leave_id)
    if not lr:
        raise HTTPException(status_code=404, detail="Leave request not found")
    lr.status, lr.decided_at, lr.decided_by = data.status, datetime.now(), admin.id
    audit.record(db, admin, f"leave.{data.status}", employee_id=lr.employee_id,
                 details=f"{_KIND.get(lr.kind, lr.kind)}: {_d(lr.start_date)} → {_d(lr.end_date)}")
    db.commit()
    db.refresh(lr)
    return lr


# ── Correction requests (from employees) ─────────────────────────────────────

@router.get("/corrections", response_model=list[CorrectionOut])
def list_corrections(status: str | None = Query(None, pattern="^(pending|resolved|rejected)$"),
                     db: Session = Depends(get_db)):
    q = db.query(CorrectionRequest)
    if status:
        q = q.filter(CorrectionRequest.status == status)
    return q.order_by(CorrectionRequest.created_at.desc()).all()

@router.post("/corrections/{request_id}/decision", response_model=CorrectionOut)
def decide_correction(request_id: int, data: CorrectionDecision, db: Session = Depends(get_db),
                      admin: Employee = Depends(require_super)):
    """Mark a request handled. The actual time fix is done with PATCH /admin/attendance/{id}."""
    cr = db.get(CorrectionRequest, request_id)
    if not cr:
        raise HTTPException(status_code=404, detail="Request not found")
    cr.status, cr.resolved_at = data.status, datetime.now()
    audit.record(db, admin, f"correction.{data.status}", employee_id=cr.employee_id,
                 details=f"{_d(cr.date)}: {_KIND.get(cr.kind, cr.kind)}")
    db.commit()
    db.refresh(cr)
    return cr


# ── One-day shift changes (from employees) ───────────────────────────────────

@router.get("/shift-changes", response_model=list[ShiftChangeOut])
def list_shift_changes(status: str | None = Query(None, pattern="^(pending|approved|rejected)$"),
                       db: Session = Depends(get_db)):
    q = db.query(ShiftChange)
    if status:
        q = q.filter(ShiftChange.status == status)
    return q.order_by(ShiftChange.created_at.desc()).all()

@router.post("/shift-changes/{change_id}/decision", response_model=ShiftChangeOut)
def decide_shift_change(change_id: int, data: Decision, db: Session = Depends(get_db),
                        admin: Employee = Depends(require_super)):
    sc = db.get(ShiftChange, change_id)
    if not sc:
        raise HTTPException(status_code=404, detail="Shift change not found")
    sc.status, sc.decided_at, sc.decided_by = data.status, datetime.now(), admin.id
    audit.record(db, admin, f"shift_change.{data.status}", employee_id=sc.employee_id,
                 details=f"{_d(sc.date)}: {sc.start}–{sc.end}", reason=sc.reason)
    db.commit()
    db.refresh(sc)
    return sc
