"""
Create a separate demo database full of made-up people and a month of attendance,
for screenshots and UI work. Never touches the real technerdz.db.

    python scripts/seed_demo.py                       # writes demo.db
    set DATABASE_URL=sqlite:///./demo.db && set CORS_ORIGINS=http://localhost:5180
    python -m uvicorn main:app --port 8001

Demo admin: username "demo-admin", password from --password (default below).
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
    "Aarav Menon", "Priya Raman", "Karthik Subramanian", "Divya Nair", "Rahul Verma",
    "Sneha Iyer", "Vikram Joshi", "Ananya Krishnan", "Arjun Pillai", "Meera Das",
    "Rohan Kapoor", "Lakshmi Prasad",
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
    from models import AttendanceLog, Employee, FaceImage
    from auth import hash_password

    engine = create_engine(os.environ["DATABASE_URL"])
    init_db(bind=engine)
    db = sessionmaker(bind=engine)()
    rng = random.Random(args.seed)

    db.add(Employee(name="Demo Admin", username="demo-admin",
                    password=hash_password(args.password), role="admin"))
    emps = []
    for name in PEOPLE:
        e = Employee(name=name, username=name.split()[0].lower(),
                     password=hash_password(args.password), role="user")
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
        for d in range(1, today.day + 1):
            day = date(today.year, today.month, d)
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
    print(f"Demo database written to {args.db}: {len(emps)} employees, admin 'demo-admin'.")


if __name__ == "__main__":
    main()
