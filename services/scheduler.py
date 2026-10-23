"""
Background jobs, run every few minutes while the server is up:
  * auto check-out: close any day someone forgot to check out of
  * daily email: send HR the summary once, after the configured time
  * monthly email: on the 1st, last month's Excel register
Each job is a plain function (easy to test); `run_forever` just calls them on a timer.
"""
import asyncio
import logging
from datetime import date, datetime, timedelta

from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from database import SessionLocal
from models import AttendanceLog
from services import audit, backup, email_service, settings_service
from services.rules import Rules

log = logging.getLogger("technerdz.scheduler")
INTERVAL_SECONDS = 300


def auto_checkout(db: Session, now: datetime | None = None) -> int:
    """Close open records from previous days at the office end time. Returns how many."""
    now = now or datetime.now()
    rules = Rules.load(db)
    open_logs = (db.query(AttendanceLog)
                   .filter(AttendanceLog.out_time.is_(None), AttendanceLog.in_time.isnot(None),
                           AttendanceLog.date < now.date().isoformat())
                   .all())
    for l in open_logs:
        team = l.employee.category if l.employee else None
        day = date.fromisoformat(l.date)
        end = datetime.combine(day, rules.shift_for(team, l.employee_id, day)[1])
        l.out_time = max(end, l.in_time)  # someone who came in after hours: zero-length day
        l.auto_checkout = True
        audit.record(db, None, "attendance.auto_checkout", employee_id=l.employee_id,
                     details=f"{l.date}: no check-out, closed at {l.out_time:%H:%M}")
    if open_logs:
        db.commit()
    return len(open_logs)


def maybe_send_daily_email(db: Session, now: datetime | None = None) -> str | None:
    now = now or datetime.now()
    s = settings_service.get_all(db)
    if not s["email_enabled"] or s["last_email_date"] == now.date().isoformat():
        return None
    if now.time() < settings_service.parse_hhmm(s["email_time"]):
        return None
    result = email_service.send_daily_summary(db, now.date(), s["hr_emails"])
    settings_service.put(db, "last_email_date", now.date().isoformat())
    audit.record(db, None, "email.daily_summary", details=result)
    db.commit()
    return result


def maybe_send_monthly_register(db: Session, now: datetime | None = None) -> str | None:
    """Once a month (from the 1st, after the email time), send HR last month's register."""
    now = now or datetime.now()
    s = settings_service.get_all(db)
    first = now.date().replace(day=1)
    last_month = (first - timedelta(days=1)).replace(day=1)
    key = f"{last_month:%Y-%m}"
    if not (s["email_enabled"] and s["monthly_register_email"]) or s["last_register_month"] == key:
        return None
    if now.time() < settings_service.parse_hhmm(s["email_time"]):
        return None
    result = email_service.send_monthly_register(db, last_month.year, last_month.month, s["hr_emails"])
    settings_service.put(db, "last_register_month", key)
    audit.record(db, None, "email.monthly_register", details=f"{last_month:%B %Y}: {result}")
    db.commit()
    return result


def maybe_backup(db: Session, now: datetime | None = None) -> str | None:
    """One automatic database backup per day (SQLite only)."""
    now = now or datetime.now()
    if not backup.db_path() or settings_service.get(db, "last_backup_date") == now.date().isoformat():
        return None
    name = backup.backup_now()
    settings_service.put(db, "last_backup_date", now.date().isoformat())
    db.commit()
    return name


def run_jobs() -> None:
    db = SessionLocal()
    try:
        n = auto_checkout(db)
        if n:
            log.info("auto check-out closed %d record(s)", n)
        sent = maybe_send_daily_email(db)
        if sent:
            log.info("daily summary: %s", sent)
        monthly = maybe_send_monthly_register(db)
        if monthly:
            log.info("monthly register: %s", monthly)
        saved = maybe_backup(db)
        if saved:
            log.info("database backed up to %s", saved)
    except Exception:  # keep the loop alive; the next run retries
        log.exception("background job failed")
        db.rollback()
    finally:
        db.close()


async def run_forever() -> None:
    while True:
        await run_in_threadpool(run_jobs)
        await asyncio.sleep(INTERVAL_SECONDS)
