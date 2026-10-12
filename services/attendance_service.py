from sqlalchemy.orm import Session
from models import AttendanceLog, Employee
from datetime import datetime, date

def mark_attendance(db: Session, employee: Employee) -> dict:
    """Auto mark IN or OUT based on today's existing log."""
    today = date.today().isoformat()
    now = datetime.now()

    log = db.query(AttendanceLog).filter(
        AttendanceLog.employee_id == employee.id,
        AttendanceLog.date == today
    ).first()

    if not log:
        # First scan of day → mark IN
        log = AttendanceLog(
            employee_id=employee.id,
            date=today,
            in_time=now,
            status="present"
        )
        db.add(log)
        db.commit()
        db.refresh(log)
        return {"action": "in", "time": now, "log": log}
    elif log.in_time and not log.out_time:
        # Second scan → mark OUT
        log.out_time = now
        db.commit()
        db.refresh(log)
        return {"action": "out", "time": now, "log": log}
    else:
        # Already fully checked in and out
        return {"action": "done", "time": now, "log": log}

def get_today_log(db: Session, employee_id: int) -> AttendanceLog | None:
    today = date.today().isoformat()
    return db.query(AttendanceLog).filter(
        AttendanceLog.employee_id == employee_id,
        AttendanceLog.date == today
    ).first()
