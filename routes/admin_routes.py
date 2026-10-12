from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from database import get_db
from models import AttendanceLog, Employee
from schemas import AttendanceOut, EmployeeOut
from datetime import date
import calendar
import csv, io

router = APIRouter(prefix="/admin", tags=["Admin"])

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
    start: str = Query(None),
    end:   str = Query(None),
    db: Session = Depends(get_db)
):
    q = db.query(AttendanceLog)
    if start: q = q.filter(AttendanceLog.date >= start)
    if end:   q = q.filter(AttendanceLog.date <= end)
    return q.order_by(AttendanceLog.date.desc()).all()

@router.get("/employees", response_model=list[EmployeeOut])
def all_employees(db: Session = Depends(get_db)):
    return db.query(Employee).filter(Employee.role == "user").all()

@router.get("/attendance/percentage")
def attendance_percentage(
    month: int = Query(None, description="Month number 1-12"),
    year:  int = Query(None, description="4-digit year"),
    db: Session = Depends(get_db)
):
    """
    Returns attendance % for every employee for the given month/year.
    Defaults to current month if not provided.
    Working days = Mon–Fri only (excludes weekends).
    """
    today     = date.today()
    month     = month or today.month
    year      = year  or today.year

    # Calculate working days in the month up to today
    _, days_in_month = calendar.monthrange(year, month)
    end_day = min(days_in_month, today.day if (year == today.year and month == today.month) else days_in_month)

    working_days = sum(
        1 for d in range(1, end_day + 1)
        if date(year, month, d).weekday() < 5  # Mon=0 ... Fri=4
    )

    employees = db.query(Employee).filter(
        Employee.is_active == True,
        Employee.role == "user"
    ).all()
    result    = []

    for emp in employees:
        start_str = f"{year}-{month:02d}-01"
        end_str   = f"{year}-{month:02d}-{end_day:02d}"

        attended = db.query(AttendanceLog).filter(
            AttendanceLog.employee_id == emp.id,
            AttendanceLog.date >= start_str,
            AttendanceLog.date <= end_str,
            AttendanceLog.status == "present",
        ).count()

        percentage = round((attended / working_days) * 100, 1) if working_days > 0 else 0.0

        result.append({
            "employee_id":   emp.id,
            "name":          emp.name,
            "attended_days": attended,
            "working_days":  working_days,
            "percentage":    percentage,
        })

    return result

@router.get("/reports/export")
def export_csv(db: Session = Depends(get_db)):
    logs   = db.query(AttendanceLog).order_by(AttendanceLog.date.desc()).all()
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["ID", "Employee ID", "Name", "Date",
                     "In Time", "Out Time", "Status"])
    for log in logs:
        emp = db.query(Employee).filter(Employee.id == log.employee_id).first()
        writer.writerow([
            log.id, log.employee_id,
            emp.name if emp else "Unknown",
            log.date, log.in_time, log.out_time, log.status
        ])
    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=attendance_report.csv"}
    )
