from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from auth import require_admin, require_super
from database import get_db
from models import Employee
from schemas import SettingsModel
from services import audit, backup, email_service, settings_service

router = APIRouter(prefix="/admin/settings", tags=["Settings"], dependencies=[Depends(require_admin)])


def _view(db: Session) -> dict:
    s = settings_service.get_all(db)
    return {**{k: s[k] for k in settings_service.EDITABLE},
            "smtp_configured": email_service.smtp_configured()}


@router.get("")
def get_settings(db: Session = Depends(get_db)):
    return _view(db)


@router.put("")
def save_settings(data: SettingsModel, db: Session = Depends(get_db), admin: Employee = Depends(require_super)):
    if settings_service.parse_hhmm(data.work_end) <= settings_service.parse_hhmm(data.work_start):
        raise HTTPException(status_code=422, detail="Office end time must be after the start time.")
    old = settings_service.get_all(db)
    changes = []
    for key, value in data.model_dump().items():
        if old.get(key) != value:
            changes.append(f"{key}: {old.get(key)} → {value}")
            settings_service.put(db, key, value)
    if changes:
        audit.record(db, admin, "settings.updated", details="; ".join(changes))
    db.commit()
    return _view(db)


@router.post("/test-email")
def test_email(db: Session = Depends(get_db), admin: Employee = Depends(require_super)):
    """Send (or save) today's summary right now, to check the setup."""
    recipients = settings_service.get(db, "hr_emails")
    try:
        result = email_service.send_daily_summary(db, date.today(), recipients)
    except Exception as e:  # SMTP login failures etc. — show the reason to the admin
        raise HTTPException(status_code=502, detail=f"Email failed: {e}")
    audit.record(db, admin, "email.test", details=result)
    db.commit()
    return {"message": result}


@router.get("/backups")
def list_backups():
    return {"supported": backup.db_path() is not None, "folder": backup.BACKUP_DIR,
            "keep": backup.KEEP, "backups": backup.list_backups()}


@router.post("/backups")
def make_backup(db: Session = Depends(get_db), admin: Employee = Depends(require_super)):
    try:
        name = backup.backup_now()
    except RuntimeError as e:
        raise HTTPException(status_code=400, detail=str(e))
    audit.record(db, admin, "backup.created", details=name)
    db.commit()
    return {"message": f"Backup saved as {name}"}
