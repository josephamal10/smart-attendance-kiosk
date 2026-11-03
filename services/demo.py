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


def block_in_demo(why: str) -> None:
    """Refuse something a public demo mustn't allow, with a reason the visitor can read."""
    from fastapi import HTTPException
    if enabled():
        raise HTTPException(status_code=403, detail=f"Not available in the demo: {why}")


def block_account_changes() -> None:
    """Every visitor shares the demo logins, so nobody may change them for the next person."""
    block_in_demo("the demo accounts are shared.")


def reset() -> None:
    """Swap in freshly made demo data (the live demo does this every few hours, so whatever
    visitors changed — notices, records, approvals — doesn't stay for long)."""
    import subprocess
    import sys
    path = database.DATABASE_URL.split("///", 1)[1]
    fresh = path + ".fresh"
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    subprocess.run([sys.executable, os.path.join(root, "scripts", "seed_demo.py"), "--db", fresh],
                   check=True, capture_output=True)
    os.replace(fresh, path)      # atomic on Linux; new connections see the new file
    database.engine.dispose()    # drop pooled connections to the old one


async def reset_forever(hours: float) -> None:
    import asyncio
    import logging
    from fastapi.concurrency import run_in_threadpool
    log = logging.getLogger("attendance.demo")
    while True:
        await asyncio.sleep(hours * 3600)
        try:
            await run_in_threadpool(reset)
            log.info("demo data reset")
        except Exception:
            log.exception("demo reset failed; trying again next time")


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
