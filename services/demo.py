"""
Demo mode, for showing the project to recruiters and visitors without a camera or real people.

Turned on by DEMO_MODE=1 (scripts/run_demo.py does it), and only ever with a demo database:
if DATABASE_URL doesn't point at a database with "demo" in its name, demo mode stays off, so
the real kiosk can never show sign-in details or open dashboards without a face scan.
"""
import os

from sqlalchemy import func
from sqlalchemy.orm import Session

import database
from models import AttendanceLog, Employee

DEMO_PASSWORD = os.getenv("DEMO_PASSWORD", "demo-pass-2026")  # what seed_demo.py gives the demo admins
ROLE_LABELS = {"admin": "Super admin — can change everything", "viewer": "HR viewer — read-only"}


def enabled() -> bool:
    return os.getenv("DEMO_MODE") == "1" and "demo" in database.DATABASE_URL.lower()


def block_account_changes() -> None:
    """Every visitor shares the demo logins, so nobody may change them for the next person."""
    from fastapi import HTTPException
    if enabled():
        raise HTTPException(status_code=403, detail="Not available in the demo: the demo accounts are shared.")


def info(db: Session) -> dict:
    """Sign-in details and employees to show on the demo's sign-in screen."""
    admins = (db.query(Employee).filter(Employee.role.in_(("admin", "viewer")), Employee.is_active == True)  # noqa: E712
                .order_by(Employee.role, Employee.name).all())
    # Most complete records first: those make the best example dashboards
    logs = func.count(AttendanceLog.id)
    people = (db.query(Employee).outerjoin(AttendanceLog, AttendanceLog.employee_id == Employee.id)
                .filter(Employee.role == "user", Employee.is_active == True)  # noqa: E712
                .group_by(Employee.id).order_by(logs.desc(), Employee.name).limit(12).all())
    return {
        "accounts": [{"username": a.username, "password": DEMO_PASSWORD, "name": a.name,
                      "role": ROLE_LABELS.get(a.role, a.role)} for a in admins],
        "employees": [{"id": e.id, "name": e.name, "category": e.category} for e in people],
    }
