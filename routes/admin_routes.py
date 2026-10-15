import calendar
import csv
import io
import uuid
from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response, StreamingResponse
from sqlalchemy.orm import Session

from auth import require_admin, require_super
from database import get_db
from models import AttendanceLog, Employee, FaceImage, LeaveRequest, NO_PASSWORD
from schemas import (AttendanceCreate, AttendanceEdit, AttendanceOut, CATEGORIES,
                     EmployeeCreate, EmployeeOut, EmployeeUpdate)
from services import audit, register, rules as R
from services.settings_service import get as get_setting
from services.settings_service import parse_hhmm

# Every route in this file needs an admin token
router = APIRouter(prefix="/admin", tags=["Admin"], dependencies=[Depends(require_admin)])


def to_out(log: AttendanceLog, rules: R.Rules) -> AttendanceOut:
    ev = R.evaluate(log, rules)
    return AttendanceOut(
        id=log.id, employee_id=log.employee_id, date=log.date,
        in_time=log.in_time, out_time=log.out_time, status=log.status,
        auto_checkout=bool(log.auto_checkout), flags=ev.flags,
        late_minutes=ev.late_minutes, early_minutes=ev.early_minutes,
        worked_minutes=ev.worked_minutes, overtime_minutes=ev.overtime_minutes,
    )


def _fmt(t: datetime | None) -> str:
    return t.strftime("%H:%M") if t else "—"


# ── Attendance ───────────────────────────────────────────────────────────────

@router.get("/attendance/today", response_model=list[AttendanceOut])
def today_all(db: Session = Depends(get_db)):
    rules = R.Rules.load(db)
    logs = db.query(AttendanceLog).filter(AttendanceLog.date == date.today().isoformat()).all()
    return [to_out(l, rules) for l in logs]

@router.get("/attendance/employee/{employee_id}", response_model=list[AttendanceOut])
def employee_history(employee_id: int, db: Session = Depends(get_db)):
    rules = R.Rules.load(db)
    logs = (db.query(AttendanceLog).filter(AttendanceLog.employee_id == employee_id)
              .order_by(AttendanceLog.date.desc()).all())
    return [to_out(l, rules) for l in logs]

@router.get("/attendance/all", response_model=list[AttendanceOut])
def all_attendance(
    start: date | None = Query(None),
    end:   date | None = Query(None),
    db: Session = Depends(get_db)
):
    rules = R.Rules.load(db)
    q = db.query(AttendanceLog)
    if start: q = q.filter(AttendanceLog.date >= start.isoformat())
    if end:   q = q.filter(AttendanceLog.date <= end.isoformat())
    return [to_out(l, rules) for l in q.order_by(AttendanceLog.date.desc()).all()]

@router.patch("/attendance/{log_id}", response_model=AttendanceOut)
def correct_attendance(log_id: int, data: AttendanceEdit, db: Session = Depends(get_db),
                       admin: Employee = Depends(require_super)):
    """Fix a record's times. A reason is required and the change is audit-logged."""
    log = db.get(AttendanceLog, log_id)
    if not log:
        raise HTTPException(status_code=404, detail="Record not found")
    day = date.fromisoformat(log.date)
    before = f"{_fmt(log.in_time)}–{_fmt(log.out_time)}"
    if data.in_time:
        log.in_time = datetime.combine(day, parse_hhmm(data.in_time))
    if data.out_time is not None:
        log.out_time = datetime.combine(day, parse_hhmm(data.out_time)) if data.out_time else None
        log.auto_checkout = False  # a human has now set it
    if log.in_time and log.out_time and log.out_time <= log.in_time:
        raise HTTPException(status_code=422, detail="Check-out must be after check-in.")
    audit.record(db, admin, "attendance.corrected", employee_id=log.employee_id,
                 details=f"{log.date}: {before} → {_fmt(log.in_time)}–{_fmt(log.out_time)}",
                 reason=data.reason)
    db.commit()
    db.refresh(log)
    return to_out(log, R.Rules.load(db))

@router.post("/attendance", response_model=AttendanceOut)
def add_attendance(data: AttendanceCreate, db: Session = Depends(get_db),
                   admin: Employee = Depends(require_super)):
    """Add a day that was never recorded (e.g. the kiosk was down)."""
    if not db.get(Employee, data.employee_id):
        raise HTTPException(status_code=404, detail="Employee not found")
    if data.date > date.today():
        raise HTTPException(status_code=422, detail="Can't add attendance for a future date.")
    exists = db.query(AttendanceLog).filter(AttendanceLog.employee_id == data.employee_id,
                                            AttendanceLog.date == data.date.isoformat()).first()
    if exists:
        raise HTTPException(status_code=409, detail="There's already a record for that day — edit it instead.")
    log = AttendanceLog(
        employee_id=data.employee_id, date=data.date.isoformat(), status="present",
        in_time=datetime.combine(data.date, parse_hhmm(data.in_time)),
        out_time=datetime.combine(data.date, parse_hhmm(data.out_time)) if data.out_time else None,
    )
    if log.out_time and log.out_time <= log.in_time:
        raise HTTPException(status_code=422, detail="Check-out must be after check-in.")
    db.add(log)
    audit.record(db, admin, "attendance.added", employee_id=data.employee_id,
                 details=f"{log.date}: {_fmt(log.in_time)}–{_fmt(log.out_time)}", reason=data.reason)
    db.commit()
    db.refresh(log)
    return to_out(log, R.Rules.load(db))


# ── Employees ────────────────────────────────────────────────────────────────

@router.get("/categories", response_model=list[str])
def categories():
    return CATEGORIES

@router.get("/employees", response_model=list[EmployeeOut])
def all_employees(db: Session = Depends(get_db)):
    return db.query(Employee).filter(Employee.role == "user").order_by(Employee.name).all()

@router.post("/employees", response_model=EmployeeOut)
def create_employee(data: EmployeeCreate, db: Session = Depends(get_db),
                    admin: Employee = Depends(require_super)):
    """Employees get no password. The username column must be unique, so it's an internal id."""
    emp = Employee(name=data.name.strip(), category=data.category, role="user",
                   username=f"emp-{uuid.uuid4().hex[:10]}", password=NO_PASSWORD)
    db.add(emp)
    db.flush()
    audit.record(db, admin, "employee.added", employee_id=emp.id, details=f"{emp.name} ({emp.category})")
    db.commit()
    db.refresh(emp)
    return emp

@router.patch("/employees/{employee_id}", response_model=EmployeeOut)
def update_employee(employee_id: int, data: EmployeeUpdate, db: Session = Depends(get_db),
                    admin: Employee = Depends(require_super)):
    emp = db.get(Employee, employee_id)
    if not emp or emp.role != "user":
        raise HTTPException(status_code=404, detail="Employee not found")
    changes = []
    for field, value in data.model_dump(exclude_unset=True).items():
        if value is None:
            continue
        value = value.strip() if field == "name" else value
        if getattr(emp, field) != value:
            changes.append(f"{field}: {getattr(emp, field)} → {value}")
            setattr(emp, field, value)
    if changes:
        audit.record(db, admin, "employee.updated", employee_id=emp.id, details="; ".join(changes))
    db.commit()
    db.refresh(emp)
    return emp


# ── Reports ──────────────────────────────────────────────────────────────────

def _month_bounds(month: int | None, year: int | None) -> tuple[date, date] | None:
    today = date.today()
    month, year = month or today.month, year or today.year
    if (year, month) > (today.year, today.month):
        return None  # future month: nothing to count yet
    last = today.day if (year, month) == (today.year, today.month) else calendar.monthrange(year, month)[1]
    return date(year, month, 1), date(year, month, last)

@router.get("/attendance/percentage")
def attendance_percentage(
    month: int = Query(None, ge=1, le=12, description="Month number 1-12"),
    year:  int = Query(None, ge=2000, le=2100, description="4-digit year"),
    db: Session = Depends(get_db)
):
    """
    Attendance % per employee for a month (default: this month, up to today).
    Working days skip weekends and holidays; approved leave days don't count as absences.
    """
    employees = db.query(Employee).filter(Employee.is_active == True, Employee.role == "user").all()  # noqa: E712
    bounds = _month_bounds(month, year)
    if bounds is None:
        return [{"employee_id": e.id, "name": e.name, "category": e.category, "attended_days": 0,
                 "working_days": 0, "leave_days": 0, "late_days": 0, "percentage": 0.0} for e in employees]
    start, end = bounds
    rules = R.Rules.load(db)
    holidays = R.holidays_between(db, start, end)
    workdays = set(R.working_days(rules, holidays, start, end))
    leave = R.leave_days(db, None, start, end)
    logs = (db.query(AttendanceLog)
              .filter(AttendanceLog.date >= start.isoformat(), AttendanceLog.date <= end.isoformat()).all())

    result = []
    for emp in employees:
        mine = [l for l in logs if l.employee_id == emp.id and date.fromisoformat(l.date) in workdays]
        on_leave = len((leave.get(emp.id) or set()) & workdays)
        expected = len(workdays) - on_leave
        late = sum(1 for l in mine if "late" in R.evaluate(l, rules).flags)
        result.append({
            "employee_id":   emp.id,
            "name":          emp.name,
            "category":      emp.category,
            "attended_days": len(mine),
            "working_days":  expected,
            "leave_days":    on_leave,
            "late_days":     late,
            "percentage":    round(min(len(mine), expected) / expected * 100, 1) if expected > 0 else 0.0,
        })
    return result

@router.get("/reports/export")
def export_csv(db: Session = Depends(get_db)):
    rules = R.Rules.load(db)
    rows = (
        db.query(AttendanceLog, Employee.name, Employee.category)
        .outerjoin(Employee, Employee.id == AttendanceLog.employee_id)
        .order_by(AttendanceLog.date.desc())
        .all()
    )
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["ID", "Employee ID", "Name", "Team", "Date", "In Time", "Out Time",
                     "Hours Worked", "Late (min)", "Flags"])
    for log, name, category in rows:
        ev = R.evaluate(log, rules)
        writer.writerow([
            log.id, log.employee_id, name or "Unknown", category or "",
            log.date, _fmt(log.in_time), _fmt(log.out_time),
            "" if ev.worked_minutes is None else f"{ev.worked_minutes / 60:.2f}",
            ev.late_minutes or "", " ".join(ev.flags),
        ])
    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=attendance_report.csv"}
    )


# ── Monthly register & employee profile ──────────────────────────────────────

def _ym(year: int | None, month: int | None) -> tuple[int, int]:
    today = date.today()
    return year or today.year, month or today.month

@router.get("/register")
def monthly_register(year: int = Query(None, ge=2000, le=2100), month: int = Query(None, ge=1, le=12),
                     db: Session = Depends(get_db)):
    return register.build(db, *_ym(year, month))

@router.get("/register.xlsx")
def monthly_register_xlsx(year: int = Query(None, ge=2000, le=2100), month: int = Query(None, ge=1, le=12),
                          db: Session = Depends(get_db)):
    y, m = _ym(year, month)
    data = register.build(db, y, m)
    content = register.to_xlsx(data, get_setting(db, "company_name"))
    return Response(content, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    headers={"Content-Disposition": f"attachment; filename=attendance-{y}-{m:02d}.xlsx"})

@router.get("/employees/{employee_id}/profile")
def employee_profile(employee_id: int, year: int = Query(None, ge=2000, le=2100),
                     month: int = Query(None, ge=1, le=12), db: Session = Depends(get_db)):
    emp = db.get(Employee, employee_id)
    if not emp or emp.role != "user":
        raise HTTPException(status_code=404, detail="Employee not found")
    data = register.build(db, *_ym(year, month), employee_ids=[employee_id])
    leave = (db.query(LeaveRequest).filter(LeaveRequest.employee_id == employee_id)
               .order_by(LeaveRequest.start_date.desc()).limit(10).all())
    return {
        "employee": EmployeeOut.model_validate(emp).model_dump(mode="json"),
        "face_photos": db.query(FaceImage).filter(FaceImage.employee_id == employee_id).count(),
        "month": {k: data[k] for k in ("year", "month", "month_name", "work_start", "work_end", "days")},
        "row": data["rows"][0] if data["rows"] else None,
        "leave": [{"id": l.id, "start_date": l.start_date.isoformat(), "end_date": l.end_date.isoformat(),
                   "kind": l.kind, "status": l.status, "reason": l.reason} for l in leave],
    }
