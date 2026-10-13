import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from auth import require_admin
from database import get_db
from models import AttendanceLog, Employee, NO_PASSWORD
from schemas import AttendanceOut, CATEGORIES, EmployeeCreate, EmployeeOut, EmployeeUpdate
from datetime import date
import calendar
import csv, io

# Every route in this file needs an admin token
router = APIRouter(prefix="/admin", tags=["Admin"], dependencies=[Depends(require_admin)])

@router.get("/attendance/today", response_model=list[AttendanceOut])
def today_all(db: Session = Depends(get_db)):
    today = date.today().isoformat()
    return db.query(AttendanceLog).filter(AttendanceLog.date == today).all()

@router.get("/attendance/employee/{employee_id}", response_model=list[AttendanceOut])
def employee_history(employee_id: int, db: Session = Depends(get_db)):
    return db.query(AttendanceLog).filter(
        AttendanceLog.employee_id == employee_id
    ).order_by(AttendanceLog.date.desc()).all()

@router.get("/attendance/all", response_model=list[AttendanceOut])
def all_attendance(
    start: date | None = Query(None),
    end:   date | None = Query(None),
    db: Session = Depends(get_db)
):
    q = db.query(AttendanceLog)
    if start: q = q.filter(AttendanceLog.date >= start.isoformat())
    if end:   q = q.filter(AttendanceLog.date <= end.isoformat())
    return q.order_by(AttendanceLog.date.desc()).all()

@router.get("/categories", response_model=list[str])
def categories():
    return CATEGORIES

@router.get("/employees", response_model=list[EmployeeOut])
def all_employees(db: Session = Depends(get_db)):
    return db.query(Employee).filter(Employee.role == "user").order_by(Employee.name).all()

@router.post("/employees", response_model=EmployeeOut)
def create_employee(data: EmployeeCreate, db: Session = Depends(get_db)):
    """Employees get no password. The username column must be unique, so it's an internal id."""
    emp = Employee(name=data.name.strip(), category=data.category, role="user",
                   username=f"emp-{uuid.uuid4().hex[:10]}", password=NO_PASSWORD)
    db.add(emp)
    db.commit()
    db.refresh(emp)
    return emp

@router.patch("/employees/{employee_id}", response_model=EmployeeOut)
def update_employee(employee_id: int, data: EmployeeUpdate, db: Session = Depends(get_db)):
    emp = db.get(Employee, employee_id)
    if not emp or emp.role != "user":
        raise HTTPException(status_code=404, detail="Employee not found")
    for field, value in data.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(emp, field, value.strip() if isinstance(value, str) and field == "name" else value)
    db.commit()
    db.refresh(emp)
    return emp

@router.get("/attendance/percentage")
def attendance_percentage(
    month: int = Query(None, ge=1, le=12, description="Month number 1-12"),
    year:  int = Query(None, ge=2000, le=2100, description="4-digit year"),
    db: Session = Depends(get_db)
):
    """
    Returns attendance % for every employee for the given month/year.
    Defaults to current month if not provided.
    Working days = Mon–Fri only (excludes weekends), counted up to today.
    """
    today     = date.today()
    month     = month or today.month
    year      = year  or today.year

    _, days_in_month = calendar.monthrange(year, month)
    if (year, month) > (today.year, today.month):
        end_day = 0                      # future month: nothing to count yet
    elif (year, month) == (today.year, today.month):
        end_day = today.day
    else:
        end_day = days_in_month

    working_days = sum(
        1 for d in range(1, end_day + 1)
        if date(year, month, d).weekday() < 5  # Mon=0 ... Fri=4
    )

    employees = db.query(Employee).filter(
        Employee.is_active == True,
        Employee.role == "user"
    ).all()
    result    = []
    start_str = f"{year}-{month:02d}-01"
    end_str   = f"{year}-{month:02d}-{max(end_day, 1):02d}"

    for emp in employees:
        attended = db.query(AttendanceLog).filter(
            AttendanceLog.employee_id == emp.id,
            AttendanceLog.date >= start_str,
            AttendanceLog.date <= end_str,
            AttendanceLog.status == "present",
        ).count() if end_day else 0

        percentage = round((attended / working_days) * 100, 1) if working_days > 0 else 0.0

        result.append({
            "employee_id":   emp.id,
            "name":          emp.name,
            "category":      emp.category,
            "attended_days": attended,
            "working_days":  working_days,
            "percentage":    percentage,
        })

    return result

@router.get("/reports/export")
def export_csv(db: Session = Depends(get_db)):
    rows = (
        db.query(AttendanceLog, Employee.name, Employee.category)
        .outerjoin(Employee, Employee.id == AttendanceLog.employee_id)
        .order_by(AttendanceLog.date.desc())
        .all()
    )
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["ID", "Employee ID", "Name", "Category", "Date",
                     "In Time", "Out Time", "Status"])
    for log, name, category in rows:
        writer.writerow([
            log.id, log.employee_id, name or "Unknown", category or "",
            log.date, log.in_time, log.out_time, log.status
        ])
    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=attendance_report.csv"}
    )
