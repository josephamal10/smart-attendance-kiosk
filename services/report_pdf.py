"""One person's monthly attendance as a printable PDF (the "Download my report" button)."""
import io
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

STATUS_TEXT = {"present": "Present", "late": "Late", "half_day": "Half day", "wfh": "Work from home", "absent": "Absent",
               "leave": "Leave", "holiday": "Holiday", "off": "Day off", "future": ""}
STATUS_COLOUR = {"present": "#DCFCE7", "late": "#FEF3C7", "half_day": "#FFE4E6", "wfh": "#CCFBF1", "absent": "#FEE2E2",
                 "leave": "#DBEAFE", "holiday": "#EDE9FE"}
FLAG_TEXT = {"late": "late", "early_leave": "left early", "half_day": "half day",
             "missed_checkout": "auto check-out"}


def _hm(minutes: int | None) -> str:
    """45 mins · 1 hr · 1 hr 20 mins · 8 hrs 5 mins"""
    if not minutes:
        return ""
    h, m = divmod(minutes, 60)
    hrs, mins = f"{h} hr{'s' if h != 1 else ''}", f"{m} min{'s' if m != 1 else ''}"
    return mins if h == 0 else hrs if m == 0 else f"{hrs} {mins}"


def build(company: str, register: dict, row: dict) -> bytes:
    """`register` and `row` come from services.register.build for one employee."""
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm,
                            topMargin=14 * mm, bottomMargin=14 * mm,
                            title=f"{row['name']} — {register['month_name']}", author=company)
    ss = getSampleStyleSheet()
    h1 = ParagraphStyle("h1", parent=ss["Title"], fontSize=17, alignment=0, spaceAfter=2)
    muted = ParagraphStyle("muted", parent=ss["Normal"], fontSize=9, textColor=colors.HexColor("#6B7280"))
    grey = colors.HexColor("#E5E7EB")

    t = row["totals"]
    summary = Table(
        [["Present", "Late", "Half day", "WFH", "Absent", "Leave", "Hours", "Overtime", "Attendance"],
         [t["present"], t["late"], t["half_day"], t["wfh"], t["absent"], t["leave"], row["worked_hours"],
          f"{row['overtime_hours']} h",
          f"{row['attendance_pct']}%" if row["attendance_pct"] is not None else "–"]],
        colWidths=[19.5 * mm] * 9)
    summary.setStyle(TableStyle([
        ("FONT", (0, 0), (-1, 0), "Helvetica", 8), ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#6B7280")),
        ("FONT", (0, 1), (-1, 1), "Helvetica-Bold", 13),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("BOX", (0, 0), (-1, -1), 0.5, grey), ("INNERGRID", (0, 0), (-1, -1), 0.5, grey),
        ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))

    rows = [["Date", "Day", "Status", "In", "Out", "Worked", "Notes"]]
    styles = [
        ("FONT", (0, 0), (-1, 0), "Helvetica-Bold", 8),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F9FAFB")),
        ("FONT", (0, 1), (-1, -1), "Helvetica", 8.5),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, grey),
        ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]
    for i, (day, cell) in enumerate(zip(register["days"], row["cells"]), start=1):
        status = cell["status"]
        notes = ", ".join(FLAG_TEXT.get(f, f) for f in cell.get("flags", []) if f != "late")
        if status == "holiday":
            notes = cell.get("name", "")
        if cell.get("overtime_minutes"):
            notes = ", ".join(filter(None, [notes, f"overtime {_hm(cell['overtime_minutes'])}"]))
        rows.append([day["date"][8:] + " " + datetime.fromisoformat(day["date"]).strftime("%b"),
                     day["weekday"], STATUS_TEXT[status], cell.get("in") or "", cell.get("out") or "",
                     _hm(cell.get("worked_minutes")), notes])
        if status in STATUS_COLOUR:
            styles.append(("BACKGROUND", (2, i), (2, i), colors.HexColor(STATUS_COLOUR[status])))
        if status in ("off", "future"):
            styles.append(("TEXTCOLOR", (0, i), (-1, i), colors.HexColor("#9CA3AF")))
    days = Table(rows, colWidths=[18 * mm, 13 * mm, 22 * mm, 16 * mm, 16 * mm, 20 * mm, 73 * mm], repeatRows=1)
    days.setStyle(TableStyle(styles))

    team = row["category"] or "No team"
    story = [
        Paragraph(f"{company} · attendance report", muted),
        Paragraph(f"{row['name']} — {register['month_name']}", h1),
        Paragraph(f"{team} · shift {row['shift']}", muted),
        Spacer(1, 6 * mm), summary, Spacer(1, 6 * mm), days, Spacer(1, 5 * mm),
        Paragraph(f"Generated {datetime.now():%d %b %Y, %H:%M}. Late, early leave and overtime use the "
                  "current work rules.", muted),
    ]
    doc.build(story)
    return buf.getvalue()
