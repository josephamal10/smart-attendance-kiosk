"""
Monthly attendance register: one row per employee, one cell per day.

Cell statuses (in priority order for a day):
  holiday  company holiday (unless the person worked, then it's their attendance)
  off      weekly day off (same exception)
  leave    approved leave
  present / late / half_day   from the check-in record and the work rules
  absent   a past working day with no record and no leave
  future   not happened yet
"""
import calendar
from dataclasses import dataclass
from datetime import date, timedelta

from sqlalchemy.orm import Session

from models import AttendanceLog, Employee
from services import rules as R

STATUSES = ("present", "late", "half_day", "absent", "leave", "holiday", "off", "future")


@dataclass
class Day:
    date: date
    weekday: str
    working: bool
    holiday: str | None


def month_days(db: Session, year: int, month: int) -> tuple[list[Day], R.Rules]:
    rules = R.Rules.load(db)
    first = date(year, month, 1)
    last = date(year, month, calendar.monthrange(year, month)[1])
    holidays = R.holidays_between(db, first, last)
    days = []
    d = first
    while d <= last:
        days.append(Day(d, d.strftime("%a"), d.weekday() not in rules.weekend and d not in holidays,
                        holidays.get(d)))
        d += timedelta(days=1)
    return days, rules


def build(db: Session, year: int, month: int, employee_ids: list[int] | None = None) -> dict:
    days, rules = month_days(db, year, month)
    first, last = days[0].date, days[-1].date
    today = date.today()

    q = db.query(Employee).filter(Employee.role == "user")
    if employee_ids is not None:
        q = q.filter(Employee.id.in_(employee_ids))
    else:
        q = q.filter(Employee.is_active == True)  # noqa: E712
    employees = q.order_by(Employee.category, Employee.name).all()

    logs = {}
    for l in (db.query(AttendanceLog)
                .filter(AttendanceLog.date >= first.isoformat(), AttendanceLog.date <= last.isoformat())
                .all()):
        logs[(l.employee_id, l.date)] = l
    leave = R.leave_days(db, None, first, last)

    rows = []
    for e in employees:
        cells, totals = [], {s: 0 for s in STATUSES}
        worked_minutes, late_minutes, overtime_minutes = 0, 0, 0
        for day in days:
            log = logs.get((e.id, day.date.isoformat()))
            cell = {"status": "future"}
            if log and log.in_time:
                ev = R.evaluate(log, rules, team=e.category)
                status = "half_day" if "half_day" in ev.flags else "late" if "late" in ev.flags else "present"
                cell = {"status": status, "in": log.in_time.strftime("%H:%M"),
                        "out": log.out_time.strftime("%H:%M") if log.out_time else None,
                        "flags": ev.flags, "log_id": log.id,
                        "worked_minutes": ev.worked_minutes, "overtime_minutes": ev.overtime_minutes}
                worked_minutes += ev.worked_minutes or 0
                late_minutes += ev.late_minutes
                overtime_minutes += ev.overtime_minutes
            elif day.holiday:
                cell = {"status": "holiday", "name": day.holiday}
            elif not day.working:
                cell = {"status": "off"}
            elif day.date in leave.get(e.id, set()):
                cell = {"status": "leave"}
            elif day.date < today:
                cell = {"status": "absent"}
            elif day.date == today:
                cell = {"status": "future"}  # may still check in today
            cells.append(cell)
            totals[cell["status"]] += 1

        expected = totals["present"] + totals["late"] + totals["half_day"] + totals["absent"]
        attended = totals["present"] + totals["late"] + totals["half_day"]
        rows.append({
            "employee_id": e.id, "name": e.name, "category": e.category, "is_active": e.is_active,
            "cells": cells, "totals": totals,
            "attendance_pct": round(attended / expected * 100, 1) if expected else None,
            "worked_hours": round(worked_minutes / 60, 1),
            "overtime_hours": round(overtime_minutes / 60, 1),
            "late_minutes": late_minutes,
            "shift": "–".join(t.strftime("%H:%M") for t in rules.shift_for(e.category)),
        })

    return {
        "year": year, "month": month, "month_name": first.strftime("%B %Y"),
        "work_start": rules.start.strftime("%H:%M"), "work_end": rules.end.strftime("%H:%M"),
        "days": [{"date": d.date.isoformat(), "day": d.date.day, "weekday": d.weekday,
                  "working": d.working, "holiday": d.holiday} for d in days],
        "rows": rows,
    }


# ── Excel ────────────────────────────────────────────────────────────────────

CODES = {"present": "P", "late": "L", "half_day": "½", "absent": "A", "leave": "LV",
         "holiday": "H", "off": "", "future": ""}
FILLS = {"present": "DCFCE7", "late": "FEF3C7", "half_day": "FFE4E6", "absent": "FEE2E2",
         "leave": "DBEAFE", "holiday": "EDE9FE", "off": "F3F4F6", "future": "FFFFFF"}


def to_xlsx(data: dict, company: str) -> bytes:
    import io
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter

    wb = Workbook()
    ws = wb.active
    ws.title = data["month_name"]
    thin = Side(style="thin", color="E5E7EB")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    center = Alignment(horizontal="center", vertical="center")
    n_days = len(data["days"])

    ws["A1"] = f"{company} — attendance register, {data['month_name']}"
    ws["A1"].font = Font(size=14, bold=True)
    ws["A2"] = (f"Office hours {data['work_start']}–{data['work_end']}.  "
                "P present · L late · ½ half day · A absent · LV leave · H holiday")
    ws["A2"].font = Font(size=9, color="6B7280")

    header = ["Employee", "Team"] + [f"{d['day']}\n{d['weekday'][:2]}" for d in data["days"]] + \
             ["Present", "Late", "Half day", "Absent", "Leave", "Hours", "Overtime h", "Attendance %"]
    for c, text in enumerate(header, start=1):
        cell = ws.cell(row=4, column=c, value=text)
        cell.font = Font(bold=True, size=9, color="374151")
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.fill = PatternFill("solid", fgColor="F9FAFB")
        cell.border = border
    for i, d in enumerate(data["days"]):
        if not d["working"]:
            ws.cell(row=4, column=3 + i).fill = PatternFill("solid", fgColor=FILLS["holiday" if d["holiday"] else "off"])

    for r, row in enumerate(data["rows"], start=5):
        ws.cell(row=r, column=1, value=row["name"]).font = Font(bold=True, size=10)
        ws.cell(row=r, column=2, value=row["category"] or "").font = Font(size=9, color="6B7280")
        for i, cell in enumerate(row["cells"]):
            x = ws.cell(row=r, column=3 + i, value=CODES[cell["status"]])
            x.fill = PatternFill("solid", fgColor=FILLS[cell["status"]])
            x.alignment, x.border, x.font = center, border, Font(size=9, bold=cell["status"] in ("absent", "late"))
        t = row["totals"]
        values = [t["present"], t["late"], t["half_day"], t["absent"], t["leave"], row["worked_hours"],
                  row["overtime_hours"], row["attendance_pct"] if row["attendance_pct"] is not None else ""]
        for j, v in enumerate(values):
            x = ws.cell(row=r, column=3 + n_days + j, value=v)
            x.alignment, x.border = center, border
        for c in (1, 2):
            ws.cell(row=r, column=c).border = border

    ws.column_dimensions["A"].width = 24
    ws.column_dimensions["B"].width = 16
    for i in range(n_days):
        ws.column_dimensions[get_column_letter(3 + i)].width = 4.2
    for j in range(8):
        ws.column_dimensions[get_column_letter(3 + n_days + j)].width = 10
    ws.row_dimensions[4].height = 30
    ws.freeze_panes = "C5"

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()
