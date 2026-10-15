"""
Work rules: turns raw check-in/out times into On time / Late / Early leave / Half day,
and counts working days (excluding weekends, holidays and approved leave).

Nothing here is stored — it's recomputed from the current settings, so if the admin
changes office hours, past records are judged by the new rules too.
"""
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

from sqlalchemy.orm import Session

from models import AttendanceLog, Holiday, LeaveRequest
from services.settings_service import get_all, parse_hhmm


@dataclass
class Rules:
    start: time                 # default office hours...
    end: time
    grace: timedelta
    half_day: timedelta
    weekend: set[int]
    # ...unless a team has its own shift: {"Developer": (10:00, 19:00)}
    shifts: dict[str, tuple[time, time]] = field(default_factory=dict)

    @classmethod
    def load(cls, db: Session) -> "Rules":
        s = get_all(db)
        return cls(
            start=parse_hhmm(s["work_start"]),
            end=parse_hhmm(s["work_end"]),
            grace=timedelta(minutes=int(s["grace_minutes"])),
            half_day=timedelta(hours=float(s["half_day_hours"])),
            weekend=set(s["weekend_days"]),
            shifts={team: (parse_hhmm(v["start"]), parse_hhmm(v["end"]))
                    for team, v in (s.get("team_shifts") or {}).items()},
        )

    def shift_for(self, team: str | None) -> tuple[time, time]:
        return self.shifts.get(team or "", (self.start, self.end))


@dataclass
class Evaluation:
    flags: list[str] = field(default_factory=list)  # late, early_leave, half_day, missed_checkout
    late_minutes: int = 0
    early_minutes: int = 0
    worked_minutes: int | None = None
    overtime_minutes: int = 0


def evaluate(log: AttendanceLog, rules: Rules, team: str | None = None) -> Evaluation:
    """Judge one record against the shift of the person's team (or the default hours)."""
    ev = Evaluation()
    if log.in_time is None:
        return ev
    day = log.in_time.date()
    if team is None and log.employee is not None:
        team = log.employee.category
    shift_start, shift_end = rules.shift_for(team)

    # Late: after start + grace. Minutes late are counted from the start time itself.
    start = datetime.combine(day, shift_start)
    if log.in_time > start + rules.grace:
        ev.flags.append("late")
        ev.late_minutes = int((log.in_time - start).total_seconds() // 60)

    if log.out_time is not None:
        worked = log.out_time - log.in_time
        ev.worked_minutes = max(0, int(worked.total_seconds() // 60))
        end = datetime.combine(day, shift_end)
        if log.auto_checkout:
            ev.flags.append("missed_checkout")
        elif log.out_time < end - rules.grace:  # same grace as arrivals: 5:57 PM isn't "early"
            ev.flags.append("early_leave")
            ev.early_minutes = int((end - log.out_time).total_seconds() // 60)
        if not log.auto_checkout and worked < rules.half_day:
            ev.flags.append("half_day")
        # Overtime: time beyond a full shift's length (ignoring anything within the grace period)
        if not log.auto_checkout:
            extra = worked - (datetime.combine(day, shift_end) - datetime.combine(day, shift_start))
            if extra > rules.grace:
                ev.overtime_minutes = int(extra.total_seconds() // 60)
    return ev


def holidays_between(db: Session, start: date, end: date) -> dict[date, str]:
    rows = db.query(Holiday).filter(Holiday.date >= start, Holiday.date <= end).all()
    return {h.date: h.name for h in rows}


def leave_days(db: Session, employee_id: int | None, start: date, end: date) -> dict[int, set[date]]:
    """Approved leave days per employee within [start, end]."""
    q = db.query(LeaveRequest).filter(
        LeaveRequest.status == "approved",
        LeaveRequest.start_date <= end,
        LeaveRequest.end_date >= start,
    )
    if employee_id is not None:
        q = q.filter(LeaveRequest.employee_id == employee_id)
    out: dict[int, set[date]] = {}
    for lr in q.all():
        d = max(lr.start_date, start)
        while d <= min(lr.end_date, end):
            out.setdefault(lr.employee_id, set()).add(d)
            d += timedelta(days=1)
    return out


def working_days(rules: Rules, holidays: dict[date, str], start: date, end: date) -> list[date]:
    days, d = [], start
    while d <= end:
        if d.weekday() not in rules.weekend and d not in holidays:
            days.append(d)
        d += timedelta(days=1)
    return days


def greeting(now: datetime) -> str:
    return "Good morning" if now.hour < 12 else "Good afternoon" if now.hour < 17 else "Good evening"
