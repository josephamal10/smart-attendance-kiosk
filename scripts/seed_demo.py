"""
Create a separate demo database full of made-up people and a month of attendance,
for screenshots and UI work. Never touches the real technerdz.db.

    python scripts/seed_demo.py                       # writes demo.db
    set DATABASE_URL=sqlite:///./demo.db && set CORS_ORIGINS=http://localhost:5180
    python -m uvicorn main:app --port 8001

Demo admins: "demo-admin" (super) and "hr-viewer" (read-only), password from --password (default below).
Employees have no passwords (they check in by face), like the real system.
"""
import argparse
import json
import os
import random
import sys
from datetime import date, datetime, time, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

PEOPLE = [
    ("Aarav Menon", "Developer"), ("Priya Raman", "HR"), ("Karthik Subramanian", "Developer"),
    ("Divya Nair", "Tester"), ("Rahul Verma", "Project Manager"), ("Sneha Iyer", "Developer"),
    ("Vikram Joshi", "Tester"), ("Ananya Krishnan", "HR"), ("Arjun Pillai", "Admin"),
    ("Meera Das", "Developer"), ("Rohan Kapoor", "Project Manager"), ("Lakshmi Prasad", "Admin"),
]


def _next_weekday(d: date) -> date:
    while d.weekday() >= 4:  # Fri–Sun: start on a Monday so a 2-day leave stays on weekdays
        d += timedelta(days=1)
    return d


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default=os.path.join(ROOT, "demo.db"))
    ap.add_argument("--password", default="demo-pass-2026")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--at", metavar="HH:MM", help="make today's records as if it were this time of day "
                    "(the screenshot tool uses mid-afternoon); default: the real time")
    args = ap.parse_args()

    if os.path.exists(args.db):
        os.remove(args.db)
    os.environ["DATABASE_URL"] = "sqlite:///" + args.db.replace("\\", "/")
    os.environ.setdefault("SECRET_KEY", "demo-only-secret")

    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    from database import init_db
    from models import (AttendanceLog, CorrectionRequest, Employee, FaceImage, Holiday,
                        LeaveRequest, NO_PASSWORD, Notice, ShiftChange)
    from services import audit, settings_service
    from auth import hash_password

    engine = create_engine(os.environ["DATABASE_URL"])
    init_db(bind=engine)
    db = sessionmaker(bind=engine)()
    rng = random.Random(args.seed)

    db.add(Employee(name="Demo Admin", username="demo-admin",
                    password=hash_password(args.password), role="admin"))
    db.add(Employee(name="Hema Shankar", username="hr-viewer",
                    password=hash_password(args.password), role="viewer"))
    joined = datetime.now() - timedelta(days=90)  # so streaks and badges have history to look at
    emps = []
    for name, category in PEOPLE:
        e = Employee(name=name, username=f"emp-{name.split()[0].lower()}", category=category,
                     password=NO_PASSWORD, role="user", created_at=joined)
        db.add(e)
        emps.append(e)
    db.commit()

    # Most people have registered faces (placeholder embeddings: demo DB can't verify faces)
    for e in emps[:-3]:
        for d in ("straight", "left", "right"):
            for _ in range(10):
                db.add(FaceImage(employee_id=e.id, image_path=f"demo/{e.id}_{d}.jpg",
                                 direction=d, embedding=json.dumps([0.0] * 128)))

    today = date.today()
    # Developers work 10–7; everyone else uses the office hours
    settings_service.put(db, "team_shifts", {"Developer": {"start": "10:00", "end": "19:00"}})
    priya = emps[1]
    priya_leave = today - timedelta(days=today.weekday() + 5)  # last week's Wednesday
    for e in emps:
        reliability = rng.uniform(0.6, 0.98)
        shift_start = time(10, 0) if e.category == "Developer" else time(9, 0)
        for back in range(60, -1, -1):
            day = today - timedelta(days=back)
            if e is priya:
                # The screenshot employee: reliable and usually early, one late day, one day of leave
                if day.weekday() >= 5 or day == priya_leave:
                    continue
                start = datetime.combine(day, time(8, 38)) + timedelta(minutes=rng.randint(0, 14))
                if back == 23:
                    start = datetime.combine(day, time(9, 32))
                end = start + timedelta(hours=9, minutes=rng.randint(15, 75))
            else:
                if day.weekday() >= 5 or rng.random() > reliability:
                    continue
                start = datetime.combine(day, shift_start) + timedelta(minutes=rng.gauss(5, 18) - 15)
                end = start + timedelta(hours=rng.uniform(7.5, 10))
            if day == today:
                # Today only has what could really have happened by now: nobody arrives in the
                # future, and people still at work haven't checked out yet
                now = (datetime.combine(today, datetime.strptime(args.at, "%H:%M").time())
                       if args.at else datetime.now())
                if start > now or rng.random() < 0.2:
                    continue  # not in (yet) today
                end = end if end < now else None
            db.add(AttendanceLog(employee_id=e.id, date=day.isoformat(),
                                 in_time=start, out_time=end, status="present"))
    db.commit()

    # Leave, holidays, a correction request and a forgotten check-out, so every page has content
    admin = db.query(Employee).filter(Employee.role == "admin").first()
    first_monday = today - timedelta(days=today.weekday() + 14)
    db.add(Holiday(date=first_monday, name="Company foundation day"))
    db.add(Holiday(date=today + timedelta(days=12), name="Diwali"))
    db.add(LeaveRequest(employee_id=emps[3].id, start_date=today, end_date=today + timedelta(days=1),
                        kind="sick", reason="Fever", status="approved", decided_by=admin.id,
                        decided_at=datetime.now()))
    db.add(LeaveRequest(employee_id=emps[0].id, start_date=today + timedelta(days=5),
                        end_date=today + timedelta(days=7), kind="casual", reason="Sister's wedding"))
    db.add(LeaveRequest(employee_id=emps[6].id, start_date=today + timedelta(days=2),
                        end_date=today + timedelta(days=2), kind="other", reason="Visa appointment"))
    db.add(CorrectionRequest(employee_id=emps[4].id, date=today - timedelta(days=1),
                             kind="missed_checkout", note="Left at 6:40 PM, forgot to scan"))
    # Priya: an approved day off last week, a request waiting, a fixed correction
    db.add(LeaveRequest(employee_id=priya.id, start_date=priya_leave, end_date=priya_leave, kind="casual",
                        reason="Family function", status="approved", decided_by=admin.id,
                        created_at=datetime.now() - timedelta(days=12), decided_at=datetime.now() - timedelta(days=11)))
    db.add(LeaveRequest(employee_id=priya.id, start_date=_next_weekday(today + timedelta(days=4)), end_date=_next_weekday(today + timedelta(days=4)) + timedelta(days=1),
                        kind="casual", reason="Trip home", created_at=datetime.now() - timedelta(hours=3)))
    db.add(CorrectionRequest(employee_id=priya.id, date=today - timedelta(days=16), kind="wrong_time",
                             note="Scanned twice by mistake", status="resolved",
                             created_at=datetime.now() - timedelta(days=15), resolved_at=datetime.now() - timedelta(days=14)))
    # Celebrations on the lock screen today, work from home, and a shift change waiting for approval
    emps[3].birthday = today.replace(year=1997)            # Divya
    emps[4].joined_on = today.replace(year=today.year - 3)  # Rahul: 3 years today
    for e in emps:
        e.joined_on = e.joined_on or (today - timedelta(days=rng.randint(200, 1500)))
    wfh_day = today - timedelta(days=today.weekday() + 3)   # last week's Friday
    db.add(LeaveRequest(employee_id=priya.id, start_date=wfh_day, end_date=wfh_day, kind="wfh",
                        reason="Waiting for a delivery", status="approved", decided_by=admin.id,
                        created_at=datetime.now() - timedelta(days=9), decided_at=datetime.now() - timedelta(days=8)))
    db.query(AttendanceLog).filter(AttendanceLog.employee_id == priya.id,
                                   AttendanceLog.date == wfh_day.isoformat()).delete()
    db.add(ShiftChange(employee_id=emps[2].id, date=_next_weekday(today + timedelta(days=1)), start="11:30",
                       end="20:30", reason="Hospital appointment in the morning"))
    db.add(Notice(title="Diwali party on Friday", body="4 PM in the cafeteria. Snacks and games — everyone welcome!",
                  pinned=True, created_by="Demo Admin"))
    db.add(Notice(title="New team shifts", body="Developers now work 10 AM – 7 PM. Everyone else stays 9 – 6.",
                  created_by="Demo Admin", expires_on=today + timedelta(days=20)))
    db.add(Notice(title="Old notice", body="Expired, so the kiosk no longer shows it.",
                  created_by="Demo Admin", expires_on=today - timedelta(days=3)))
    yesterday = db.query(AttendanceLog).filter(AttendanceLog.employee_id == emps[4].id,
                                               AttendanceLog.date < today.isoformat())                   .order_by(AttendanceLog.date.desc()).first()
    if yesterday:
        yesterday.out_time = datetime.combine(date.fromisoformat(yesterday.date), time(18, 0))
        yesterday.auto_checkout = True
        audit.record(db, None, "attendance.auto_checkout", employee_id=emps[4].id,
                     details=f"{yesterday.date}: no check-out, closed at 18:00")
    audit.record(db, admin, "employee.added", employee_id=emps[-1].id, details=f"{emps[-1].name} (Admin)")
    audit.record(db, admin, "holiday.added", details=f"{today + timedelta(days=12)}: Diwali")
    audit.record(db, admin, "leave.approved", employee_id=emps[3].id, details=f"sick {today} → {today + timedelta(days=1)}")
    db.commit()
    print(f"Demo database written to {args.db}: {len(emps)} employees, "
          "admins 'demo-admin' (super) and 'hr-viewer' (read-only).")


if __name__ == "__main__":
    main()
