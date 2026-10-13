from datetime import datetime, date, timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from models import AttendanceLog, Employee
from services import settings_service


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
        # A second scan this soon after check-in is an accidental repeat, not a check-out
        gap = timedelta(minutes=int(settings_service.get(db, "min_checkout_minutes")))
        if now - log.in_time < gap:
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
