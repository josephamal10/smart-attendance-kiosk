"""
Settings the admin can change from the dashboard, stored in the `settings` table.
Every key has a default here, so a fresh database works without any setup.
"""
import json
from datetime import time
from typing import Any

from sqlalchemy.orm import Session

from models import Setting

DEFAULTS: dict[str, Any] = {
    "company_name":         "TECHNERDZ",
    "work_start":           "09:00",
    "work_end":             "18:00",
    "grace_minutes":        15,       # check-in later than start + grace = Late
    "half_day_hours":       4.0,      # worked less than this = Half day
    "weekend_days":         [5, 6],   # Monday = 0 ... Sunday = 6
    "min_checkout_minutes": 5,        # scans sooner than this after check-in don't check out
    "team_shifts":          {},       # {"Developer": {"start": "10:00", "end": "19:00"}}
    "leave_allowance":      {"casual": 12, "sick": 7, "other": 0},  # days per year
    "hr_emails":            [],       # who gets the daily summary
    "email_enabled":        False,
    "email_time":           "19:00",
    "last_email_date":      "",       # internal: stops the summary going out twice a day
    "last_backup_date":     "",       # internal: one automatic backup per day
}

# Keys the dashboard may edit (the last_* keys are internal bookkeeping)
EDITABLE = [k for k in DEFAULTS if not k.startswith("last_")]


def get_all(db: Session) -> dict[str, Any]:
    values = dict(DEFAULTS)
    for row in db.query(Setting).all():
        if row.key in values:
            values[row.key] = json.loads(row.value)
    return values


def get(db: Session, key: str) -> Any:
    row = db.get(Setting, key)
    return json.loads(row.value) if row else DEFAULTS[key]


def put(db: Session, key: str, value: Any) -> None:
    row = db.get(Setting, key)
    if row:
        row.value = json.dumps(value)
    else:
        db.add(Setting(key=key, value=json.dumps(value)))


def parse_hhmm(s: str) -> time:
    h, m = s.split(":")
    return time(int(h), int(m))
