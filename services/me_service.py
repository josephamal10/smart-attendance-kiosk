"""
Everything on an employee's own dashboard beyond the basic monthly numbers:
leave balance, on-time streaks and badges, weekly hours, request updates, team and notices.

Like the rest of the app, nothing here is stored — it's worked out from attendance,
leave and the current work rules each time the dashboard opens.
"""
from datetime import date, datetime, timedelta

from sqlalchemy.orm import Session

from models import AttendanceLog, CorrectionRequest, Employee, Holiday, LeaveRequest, Notice, ShiftChange
from services import rules as R
from services.settings_service import get as get_setting

LEAVE_LABELS = {"casual": "Casual", "sick": "Sick", "other": "Other"}
CORRECTION_LABELS = {"missed_checkout": "Forgot to check out", "wrong_time": "Wrong time", "other": "Problem"}
LOOKBACK_DAYS = 365


def _fmt(d: date) -> str:
    return d.strftime("%d %b")


class History:
    """One year of someone's days, judged once and shared by the streak and badge rules."""

    def __init__(self, db: Session, emp: Employee, today: date | None = None):
        self.today = today or date.today()
        self.rules = R.Rules.load(db)
        joined = emp.created_at.date() if emp.created_at else self.today
        self.start = max(joined, self.today - timedelta(days=LOOKBACK_DAYS))
        holidays = R.holidays_between(db, self.start, self.today)
        self.workdays = R.working_days(self.rules, holidays, self.start, self.today)
        # Leave and work-from-home days are both skipped by streaks and expected hours
        self.leave = (R.leave_days(db, emp.id, self.start, self.today).get(emp.id, set())
                      | R.leave_days(db, emp.id, self.start, self.today, wfh=True).get(emp.id, set()))
        self.shift_start, self.shift_end = self.rules.shift_for(emp.category)
        self.logs: dict[date, AttendanceLog] = {}
        self.evals: dict[date, R.Evaluation] = {}
        for log in (db.query(AttendanceLog)
                      .filter(AttendanceLog.employee_id == emp.id,
                              AttendanceLog.date >= self.start.isoformat(),
                              AttendanceLog.date <= self.today.isoformat())
                      .all()):
            d = date.fromisoformat(log.date)
            self.logs[d] = log
            self.evals[d] = R.evaluate(log, self.rules, team=emp.category)

    def status(self, d: date) -> str:
        """on_time / late / absent / leave / pending (today, not in yet)."""
        log = self.logs.get(d)
        if log and log.in_time:
            return "late" if "late" in self.evals[d].flags else "on_time"
        if d in self.leave:
            return "leave"
        return "pending" if d >= self.today else "absent"

    def days_between(self, first: date, last: date) -> list[date]:
        return [d for d in self.workdays if first <= d <= last]


# ── Streaks & badges ─────────────────────────────────────────────────────────

def streaks(h: History) -> dict:
    """Consecutive working days arriving on time. Leave and holidays don't break a streak;
    a late arrival or an absence does. Today only counts once you've checked in."""
    best = run = 0
    for d in h.workdays:
        s = h.status(d)
        if s == "on_time":
            run += 1
            best = max(best, run)
        elif s in ("late", "absent"):
            run = 0
    return {"current": run, "best": best}


def _perfect(h: History, first: date, last: date) -> bool:
    days = [d for d in h.days_between(first, last) if d not in h.leave]
    return bool(days) and all(h.status(d) == "on_time" for d in days)


def badges(h: History, streak: dict) -> list[dict]:
    today = h.today
    this_monday = today - timedelta(days=today.weekday())
    last_week = (this_monday - timedelta(days=7), this_monday - timedelta(days=1))
    month_start = today.replace(day=1)
    last_month_end = month_start - timedelta(days=1)
    last_month = (last_month_end.replace(day=1), last_month_end)

    month_days = [d for d in h.logs if d >= month_start and h.logs[d].in_time]
    early = sum(1 for d in month_days
                if h.logs[d].in_time <= datetime.combine(d, h.shift_start) - timedelta(minutes=10))
    closed = [d for d in month_days if h.logs[d].out_time]
    forgot = sum(1 for d in closed if "missed_checkout" in h.evals[d].flags)
    overtime_h = sum(h.evals[d].overtime_minutes for d in month_days) / 60

    def badge(key, title, description, earned, progress=None):
        return {"key": key, "title": title, "description": description, "earned": earned, "progress": progress}

    return [
        badge("on_a_roll", "On a roll", "5 working days in a row on time",
              streak["current"] >= 5, f"{min(streak['current'], 5)}/5"),
        badge("perfect_week", "Perfect week", "Every day on time last week",
              _perfect(h, *last_week)),
        badge("perfect_month", "Perfect month", f"Every day on time in {last_month[0]:%B}",
              _perfect(h, *last_month)),
        badge("early_bird", "Early bird", "In 10+ minutes early on 5 days this month",
              early >= 5, f"{min(early, 5)}/5"),
        badge("clean_exits", "Clean exits", "Checked out yourself every day this month (5+ days)",
              len(closed) >= 5 and forgot == 0, f"{min(len(closed), 5)}/5" if forgot == 0 else "missed one"),
        badge("extra_mile", "Extra mile", "5+ hours of overtime this month",
              overtime_h >= 5, f"{min(overtime_h, 5):.1f}/5 h"),
    ]


# ── Hours ────────────────────────────────────────────────────────────────────

def weekly_hours(h: History, weeks: int = 8) -> list[dict]:
    """Hours worked per week (Mon–Sun) against the hours the shift expected."""
    shift_len = (datetime.combine(h.today, h.shift_end) - datetime.combine(h.today, h.shift_start))
    shift_hours = shift_len.total_seconds() / 3600
    this_monday = h.today - timedelta(days=h.today.weekday())
    out = []
    for i in range(weeks - 1, -1, -1):
        mon = this_monday - timedelta(weeks=i)
        sun = mon + timedelta(days=6)
        worked = sum(ev.worked_minutes or 0 for d, ev in h.evals.items() if mon <= d <= sun)
        # Today only counts once it's over (checked out), so a half-done day doesn't look like a shortfall
        today_done = h.today in h.logs and h.logs[h.today].out_time is not None
        expected_days = [d for d in h.days_between(mon, min(sun, h.today)) if d not in h.leave
                         and (d < h.today or today_done)]
        out.append({"week_start": mon.isoformat(), "label": _fmt(mon),
                    "hours": round(worked / 60, 1),
                    "expected": round(len(expected_days) * shift_hours, 1)})
    return out


# ── Leave balance ────────────────────────────────────────────────────────────

def leave_balance(db: Session, emp: Employee, year: int | None = None) -> list[dict]:
    """Working days of leave used this year against the yearly allowance (from settings)."""
    year = year or date.today().year
    first, last = date(year, 1, 1), date(year, 12, 31)
    rules = R.Rules.load(db)
    holidays = R.holidays_between(db, first, last)
    allowance = get_setting(db, "leave_allowance") or {}
    used = {k: 0 for k in LEAVE_LABELS}
    pending = {k: 0 for k in LEAVE_LABELS}
    for lr in (db.query(LeaveRequest)
                 .filter(LeaveRequest.employee_id == emp.id,
                         LeaveRequest.status.in_(("approved", "pending")), LeaveRequest.kind != "wfh",
                         LeaveRequest.start_date <= last, LeaveRequest.end_date >= first)
                 .all()):
        days = len(R.working_days(rules, holidays, max(lr.start_date, first), min(lr.end_date, last)))
        bucket = used if lr.status == "approved" else pending
        bucket[lr.kind if lr.kind in bucket else "other"] += days
    out = []
    for kind, label in LEAVE_LABELS.items():
        total = int(allowance.get(kind, 0))
        if total == 0 and used[kind] == 0 and pending[kind] == 0:
            continue  # e.g. "other" with no allowance and never used: nothing to show
        out.append({"kind": kind, "label": label, "allowance": total, "used": used[kind],
                    "pending": pending[kind], "remaining": max(total - used[kind], 0)})
    return out


# ── Updates, notices, team ───────────────────────────────────────────────────

def updates(db: Session, emp: Employee, days: int = 30) -> list[dict]:
    """What happened to this person's requests recently, newest first."""
    since = datetime.now() - timedelta(days=days)
    items = []
    for lr in (db.query(LeaveRequest)
                 .filter(LeaveRequest.employee_id == emp.id,
                         (LeaveRequest.created_at >= since) | (LeaveRequest.decided_at >= since))
                 .all()):
        span = _fmt(lr.start_date) if lr.start_date == lr.end_date else f"{_fmt(lr.start_date)} – {_fmt(lr.end_date)}"
        what = "Work from home" if lr.kind == "wfh" else f"{LEAVE_LABELS.get(lr.kind, 'Other')} leave"
        items.append({"type": "wfh" if lr.kind == "wfh" else "leave", "title": f"{what}, {span}",
                      "status": lr.status, "at": _naive(lr.decided_at or lr.created_at)})
    for cr in (db.query(CorrectionRequest)
                 .filter(CorrectionRequest.employee_id == emp.id,
                         (CorrectionRequest.created_at >= since) | (CorrectionRequest.resolved_at >= since))
                 .all()):
        items.append({"type": "correction",
                      "title": f"{CORRECTION_LABELS.get(cr.kind, 'Problem')} on {_fmt(cr.date)}",
                      "status": cr.status, "at": _naive(cr.resolved_at or cr.created_at)})
    for sc in (db.query(ShiftChange)
                 .filter(ShiftChange.employee_id == emp.id,
                         (ShiftChange.created_at >= since) | (ShiftChange.decided_at >= since))
                 .all()):
        items.append({"type": "shift", "title": f"Shift {sc.start}–{sc.end} on {_fmt(sc.date)}",
                      "status": sc.status, "at": _naive(sc.decided_at or sc.created_at)})
    items.sort(key=lambda i: i["at"], reverse=True)
    return items[:10]


def _naive(dt: datetime) -> datetime:
    # created_at is stored in UTC by some tables; compare everything as naive local-ish times
    return dt.replace(tzinfo=None) if dt else datetime.min


def active_notices(db: Session, limit: int = 10) -> list[Notice]:
    today = date.today()
    return (db.query(Notice)
              .filter((Notice.expires_on == None) | (Notice.expires_on >= today))  # noqa: E711
              .order_by(Notice.pinned.desc(), Notice.created_at.desc())
              .limit(limit).all())


def team(db: Session, emp: Employee) -> dict:
    today = date.today()
    rules = R.Rules.load(db)
    mates = []
    if emp.category:
        mates = (db.query(Employee)
                   .filter(Employee.role == "user", Employee.is_active == True,  # noqa: E712
                           Employee.category == emp.category)
                   .order_by(Employee.name).all())
    on_leave = R.leave_days(db, None, today, today)
    holidays = (db.query(Holiday).filter(Holiday.date >= today)
                  .order_by(Holiday.date).limit(4).all())
    return {
        "name": emp.category,
        "shift": "–".join(t.strftime("%H:%M") for t in rules.shift_for(emp.category)),
        "members": len(mates),
        "on_leave_today": [m.name for m in mates if m.id != emp.id and m.id in on_leave],
        "upcoming_holidays": [{"date": h.date.isoformat(), "name": h.name,
                               "in_days": (h.date - today).days} for h in holidays],
    }
