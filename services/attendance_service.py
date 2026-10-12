import os
from datetime import datetime, date, timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from models import AttendanceLog, Employee

# A second scan sooner than this after check-in is treated as an accidental repeat, not a check-out.
MIN_CHECKOUT_GAP = timedelta(minutes=int(os.getenv("MIN_CHECKOUT_MINUTES", 5)))


def mark_attendance(db: Session, employee: Employee) -> dict:
    """Auto mark IN or OUT based on today's existing log."""
    today = date.today().isoformat()
    now = datetime.now()

    log = get_today_log(db, employee.id)

    if not log:
        log = AttendanceLog(employee_id=employee.id, date=today, in_time=now, status="present")
        db.add(log)
        try:
            db.commit()
        except IntegrityError:
            # Another scan for the same person landed at the same moment and won the race
            db.rollback()
            return {"action": "done", "time": now, "log": get_today_log(db, employee.id)}
        db.refresh(log)
        return {"action": "in", "time": now, "log": log}

    if log.in_time and not log.out_time:
        if now - log.in_time < MIN_CHECKOUT_GAP:
            return {"action": "too_soon", "time": log.in_time, "log": log}
        log.out_time = now
        db.commit()
        db.refresh(log)
        return {"action": "out", "time": now, "log": log}

    return {"action": "done", "time": log.out_time or now, "log": log}


def get_today_log(db: Session, employee_id: int) -> AttendanceLog | None:
    return db.query(AttendanceLog).filter(
        AttendanceLog.employee_id == employee_id,
        AttendanceLog.date == date.today().isoformat(),
    ).first()
