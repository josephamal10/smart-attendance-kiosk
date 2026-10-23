"""
Daily attendance summary for HR.

Sending uses SMTP (Gmail by default). The account and its App Password live only in
.env, which you fill in yourself:
    SMTP_USER=you@gmail.com
    SMTP_PASSWORD=<16-character Gmail App Password>
Without those, the summary is saved to reports/emails/<date>.html instead of being sent,
so the feature can be tried safely.
"""
import html
import os
import smtplib
from datetime import date, datetime
from email.message import EmailMessage

from sqlalchemy.orm import Session

from models import AttendanceLog, Employee
from services import rules as R
from services.settings_service import get_all

OUTBOX = os.path.join("reports", "emails")


def build_summary(db: Session, day: date) -> dict:
    rules = R.Rules.load(db)
    employees = (db.query(Employee).filter(Employee.role == "user", Employee.is_active == True)  # noqa: E712
                   .order_by(Employee.name).all())
    logs = {l.employee_id: l for l in db.query(AttendanceLog).filter(AttendanceLog.date == day.isoformat()).all()}
    on_leave = R.leave_days(db, None, day, day)
    at_home = R.leave_days(db, None, day, day, wfh=True)
    holiday = R.holidays_between(db, day, day).get(day)

    rows = []
    for e in employees:
        log = logs.get(e.id)
        if log and log.in_time:
            ev = R.evaluate(log, rules)
            status = "Late" if "late" in ev.flags else "On time"
            if "missed_checkout" in ev.flags:
                status += " · missed check-out"
            elif "early_leave" in ev.flags:
                status += " · left early"
        elif day in on_leave.get(e.id, set()):
            status, log = "On leave", None
        elif day in at_home.get(e.id, set()):
            status, log = "Working from home", None
        else:
            status, log = "Absent", None
        rows.append({
            "name": e.name, "team": e.category or "No team", "status": status,
            "in": log.in_time.strftime("%H:%M") if log and log.in_time else "—",
            "out": log.out_time.strftime("%H:%M") if log and log.out_time else "—",
        })

    counts = {k: sum(1 for r in rows if r["status"].startswith(k)) for k in ("On time", "Late", "Working from home", "On leave", "Absent")}
    return {"day": day, "holiday": holiday, "rows": rows, "counts": counts,
            "company": get_all(db)["company_name"]}


def render_html(s: dict) -> str:
    colors = {"On time": "#16A34A", "Late": "#D97706", "Working from home": "#0D9488",
              "On leave": "#2563EB", "Absent": "#DC2626"}
    tiles = "".join(
        f'<td style="padding:12px 16px;border:1px solid #E5E7EB;border-radius:8px">'
        f'<div style="font-size:12px;color:#6B7280">{k}</div>'
        f'<div style="font-size:24px;font-weight:700;color:{colors[k]}">{v}</div></td>'
        for k, v in s["counts"].items())
    body = "".join(
        f'<tr><td style="padding:8px;border-bottom:1px solid #F3F4F6">{html.escape(r["name"])}</td>'
        f'<td style="padding:8px;border-bottom:1px solid #F3F4F6;color:#6B7280">{html.escape(r["team"])}</td>'
        f'<td style="padding:8px;border-bottom:1px solid #F3F4F6">{r["in"]}</td>'
        f'<td style="padding:8px;border-bottom:1px solid #F3F4F6">{r["out"]}</td>'
        f'<td style="padding:8px;border-bottom:1px solid #F3F4F6;color:'
        f'{colors.get(r["status"].split(" ·")[0], "#111827")};font-weight:600">{r["status"]}</td></tr>'
        for r in s["rows"])
    holiday = f'<p style="color:#2563EB">Holiday: {html.escape(s["holiday"])}</p>' if s["holiday"] else ""
    return f"""<html><body style="font-family:Segoe UI,Arial,sans-serif;color:#111827">
<h2 style="margin:0">{html.escape(s["company"])} — attendance for {s["day"]:%A, %d %B %Y}</h2>
{holiday}<table style="border-spacing:8px;margin:12px -8px"><tr>{tiles}</tr></table>
<table style="border-collapse:collapse;width:100%;font-size:14px">
<tr style="text-align:left;color:#6B7280;font-size:12px"><th style="padding:8px">Name</th><th style="padding:8px">Team</th>
<th style="padding:8px">In</th><th style="padding:8px">Out</th><th style="padding:8px">Status</th></tr>{body}</table>
<p style="color:#9CA3AF;font-size:12px">Sent automatically by the {html.escape(s["company"])} attendance kiosk.</p>
</body></html>"""


def smtp_configured() -> bool:
    return bool(os.getenv("SMTP_USER") and os.getenv("SMTP_PASSWORD"))


def send_daily_summary(db: Session, day: date, recipients: list[str]) -> str:
    """Send (or save) the summary. Returns a short human-readable result."""
    s = build_summary(db, day)
    body = render_html(s)
    subject = f"{s['company']} attendance — {day:%d %b}: {s['counts']['On time'] + s['counts']['Late']} present, " \
              f"{s['counts']['Late']} late, {s['counts']['Absent']} absent"

    return _deliver(subject, body, recipients, day.isoformat())


def send_monthly_register(db: Session, year: int, month: int, recipients: list[str]) -> str:
    """Email last month's attendance register to HR, with the coloured Excel file attached."""
    from services import register
    data = register.build(db, year, month)
    company = get_all(db)["company_name"]
    rows = "".join(
        f"<tr><td style='padding:6px 10px'>{html.escape(r['name'])}</td>"
        f"<td style='padding:6px 10px;color:#6b7280'>{html.escape(r['category'] or '')}</td>"
        f"<td style='padding:6px 10px;text-align:right'>"
        f"{'' if r['attendance_pct'] is None else str(r['attendance_pct']) + '%'}</td>"
        f"<td style='padding:6px 10px;text-align:right'>{r['worked_hours']} h</td></tr>" for r in data["rows"])
    body = (f"<html><body style='font-family:Segoe UI,Arial,sans-serif;color:#111827'>"
            f"<h2 style='margin:0 0 4px'>{html.escape(company)} — attendance register</h2>"
            f"<p style='color:#6b7280;margin:0 0 16px'>{data['month_name']}. The full day-by-day register "
            f"is attached as an Excel file.</p><table style='border-collapse:collapse;font-size:14px'>"
            f"<tr style='background:#f9fafb'><th align='left' style='padding:6px 10px'>Employee</th>"
            f"<th align='left' style='padding:6px 10px'>Team</th><th style='padding:6px 10px'>Attendance</th>"
            f"<th style='padding:6px 10px'>Hours</th></tr>{rows}</table></body></html>")
    xlsx = register.to_xlsx(data, company)
    name = f"attendance-{year}-{month:02d}.xlsx"
    return _deliver(f"{company} attendance register — {data['month_name']}", body, recipients,
                    f"register-{year}-{month:02d}", attachments=[(name, xlsx)])


def _deliver(subject: str, body: str, recipients: list[str], outbox_name: str,
             attachments: list[tuple[str, bytes]] = ()) -> str:
    """Send by SMTP, or save to the outbox folder when email isn't set up yet."""
    if not smtp_configured() or not recipients:
        os.makedirs(OUTBOX, exist_ok=True)
        path = os.path.join(OUTBOX, f"{outbox_name}.html")
        with open(path, "w", encoding="utf-8") as f:
            f.write(body)
        for filename, data in attachments:
            with open(os.path.join(OUTBOX, filename), "wb") as f:
                f.write(data)
        why = "no HR email addresses set" if not recipients else "SMTP not configured in .env"
        return f"Saved to {path} ({why})"

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = os.getenv("SMTP_FROM", os.environ["SMTP_USER"])
    msg["To"] = ", ".join(recipients)
    msg.set_content("This email is best viewed in an email app that shows HTML.")
    msg.add_alternative(body, subtype="html")
    for filename, data in attachments:
        msg.add_attachment(data, maintype="application",
                           subtype="vnd.openxmlformats-officedocument.spreadsheetml.sheet", filename=filename)
    host = os.getenv("SMTP_HOST", "smtp.gmail.com")
    port = int(os.getenv("SMTP_PORT", 587))
    with smtplib.SMTP(host, port, timeout=20) as smtp:
        smtp.starttls()
        smtp.login(os.environ["SMTP_USER"], os.environ["SMTP_PASSWORD"])
        smtp.send_message(msg)
    return f"Sent to {', '.join(recipients)} at {datetime.now():%H:%M}"
