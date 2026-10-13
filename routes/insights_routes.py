"""Analytics for the charts page, and the audit log."""
from collections import defaultdict
from datetime import date, timedelta
from statistics import mean

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from auth import require_admin
from database import get_db
from models import AttendanceLog, AuditLog, Employee
from schemas import AuditOut
from services import rules as R

router = APIRouter(prefix="/admin", tags=["Insights"], dependencies=[Depends(require_admin)])


def _minutes(t) -> int:
    return t.hour * 60 + t.minute


@router.get("/analytics")
def analytics(days: int = Query(30, ge=7, le=365), db: Session = Depends(get_db)):
    today = date.today()
    start = today - timedelta(days=days - 1)
    rules = R.Rules.load(db)
    holidays = R.holidays_between(db, start, today)
    workdays = R.working_days(rules, holidays, start, today)
    leave = R.leave_days(db, None, start, today)

    employees = db.query(Employee).filter(Employee.role == "user", Employee.is_active == True).all()  # noqa: E712
    team_of = {e.id: e.category or "No team" for e in employees}
    logs = [l for l in db.query(AttendanceLog)
                         .filter(AttendanceLog.date >= start.isoformat(), AttendanceLog.date <= today.isoformat())
                         .all() if l.employee_id in team_of and l.in_time]
    evals = {l.id: R.evaluate(l, rules) for l in logs}
    by_day = defaultdict(list)
    for l in logs:
        by_day[l.date].append(l)

    daily = []
    for d in (start + timedelta(days=i) for i in range(days)):
        day_logs = by_day.get(d.isoformat(), [])
        arrivals = [_minutes(l.in_time) for l in day_logs]
        daily.append({
            "date": d.isoformat(),
            "working": d in workdays,
            "holiday": holidays.get(d),
            "present": len(day_logs),
            "late": sum(1 for l in day_logs if "late" in evals[l.id].flags),
            "on_leave": sum(1 for e in employees if d in leave.get(e.id, ())),
            "avg_arrival": round(mean(arrivals)) if arrivals else None,
        })

    workday_set = {d.isoformat() for d in workdays}
    work_logs = [l for l in logs if l.date in workday_set]

    teams = []
    for team in sorted(set(team_of.values())):
        members = [e for e in employees if team_of[e.id] == team]
        expected = sum(len(workdays) - len(leave.get(e.id, set()) & set(workdays)) for e in members)
        t_logs = [l for l in work_logs if team_of[l.employee_id] == team]
        teams.append({
            "team": team,
            "members": len(members),
            "presence_pct": round(len(t_logs) / expected * 100, 1) if expected else 0.0,
            "late": sum(1 for l in t_logs if "late" in evals[l.id].flags),
            "avg_arrival": round(mean(_minutes(l.in_time) for l in t_logs)) if t_logs else None,
        })

    people = []
    for e in employees:
        mine = [l for l in work_logs if l.employee_id == e.id]
        if not mine:
            continue
        on_time = sum(1 for l in mine if "late" not in evals[l.id].flags)
        people.append({"employee_id": e.id, "name": e.name, "team": team_of[e.id],
                       "present_days": len(mine), "late_days": len(mine) - on_time,
                       "on_time_pct": round(on_time / len(mine) * 100, 1)})
    people.sort(key=lambda p: (-p["on_time_pct"], -p["present_days"], p["name"]))

    worked = [evals[l.id].worked_minutes for l in work_logs if evals[l.id].worked_minutes]
    expected_total = sum(len(workdays) - len(leave.get(e.id, set()) & set(workdays)) for e in employees)
    return {
        "days": days,
        "work_start": rules.start.strftime("%H:%M"),
        "summary": {
            "presence_rate": round(len(work_logs) / expected_total * 100, 1) if expected_total else 0.0,
            "on_time_rate": round(sum(1 for l in work_logs if "late" not in evals[l.id].flags)
                                  / len(work_logs) * 100, 1) if work_logs else 0.0,
            "avg_arrival": round(mean(_minutes(l.in_time) for l in work_logs)) if work_logs else None,
            "avg_worked": round(mean(worked)) if worked else None,
        },
        "daily": daily,
        "teams": teams,
        "punctuality": people,
    }


@router.get("/audit", response_model=list[AuditOut])
def audit_log(limit: int = Query(200, ge=1, le=1000), employee_id: int | None = None,
              db: Session = Depends(get_db)):
    q = db.query(AuditLog)
    if employee_id is not None:
        q = q.filter(AuditLog.employee_id == employee_id)
    return q.order_by(AuditLog.at.desc(), AuditLog.id.desc()).limit(limit).all()
