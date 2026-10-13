"""
Create a separate demo database full of made-up people and a month of attendance,
for screenshots and UI work. Never touches the real technerdz.db.

    python scripts/seed_demo.py                       # writes demo.db
    set DATABASE_URL=sqlite:///./demo.db && set CORS_ORIGINS=http://localhost:5180
    python -m uvicorn main:app --port 8001

Demo admin: username "demo-admin", password from --password (default below).
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default=os.path.join(ROOT, "demo.db"))
    ap.add_argument("--password", default="demo-pass-2026")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    if os.path.exists(args.db):
        os.remove(args.db)
    os.environ["DATABASE_URL"] = "sqlite:///" + args.db.replace("\\", "/")
    os.environ.setdefault("SECRET_KEY", "demo-only-secret")

    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    from database import init_db
    from models import (AttendanceLog, CorrectionRequest, Employee, FaceImage, Holiday,
                        LeaveRequest, NO_PASSWORD)
    from services import audit
    from auth import hash_password

    engine = create_engine(os.environ["DATABASE_URL"])
    init_db(bind=engine)
    db = sessionmaker(bind=engine)()
    rng = random.Random(args.seed)

    db.add(Employee(name="Demo Admin", username="demo-admin",
                    password=hash_password(args.password), role="admin"))
    emps = []
    for name, category in PEOPLE:
        e = Employee(name=name, username=f"emp-{name.split()[0].lower()}", category=category,
                     password=NO_PASSWORD, role="user")
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
    for e in emps:
        reliability = rng.uniform(0.6, 0.98)
        for back in range(42, -1, -1):
            day = today - timedelta(days=back)
            if day.weekday() >= 5 or rng.random() > reliability:
                continue
            start = datetime.combine(day, time(8, 45)) + timedelta(minutes=rng.gauss(20, 18))
            end = start + timedelta(hours=rng.uniform(7.5, 9.5))
            if day == today:
                if rng.random() < 0.25:
                    continue  # not in yet today
                now = datetime.now()
                start = min(start, now - timedelta(minutes=rng.randint(5, 90)))
                end = end if end < now and rng.random() < 0.3 else None
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
    print(f"Demo database written to {args.db}: {len(emps)} employees, admin 'demo-admin'.")


if __name__ == "__main__":
    main()
