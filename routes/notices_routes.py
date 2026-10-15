"""Company notices: admins post them; the kiosk and every employee dashboard show them."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from auth import require_admin, require_super
from database import get_db
from models import Employee, Notice
from schemas import NoticeIn, NoticeOut
from services import audit, me_service

router = APIRouter(prefix="/admin/notices", tags=["Notices"], dependencies=[Depends(require_admin)])
# Read-only, no sign-in: the kiosk lock screen shows current notices to whoever walks by
public_router = APIRouter(tags=["Notices"])


@public_router.get("/notices", response_model=list[NoticeOut])
def current_notices(db: Session = Depends(get_db)):
    return me_service.active_notices(db, limit=5)


@router.get("", response_model=list[NoticeOut])
def list_notices(db: Session = Depends(get_db)):
    return db.query(Notice).order_by(Notice.pinned.desc(), Notice.created_at.desc()).all()


@router.post("", response_model=NoticeOut)
def post_notice(data: NoticeIn, db: Session = Depends(get_db), admin: Employee = Depends(require_super)):
    n = Notice(title=data.title.strip(), body=data.body.strip(), pinned=data.pinned,
               expires_on=data.expires_on, created_by=admin.name)
    db.add(n)
    audit.record(db, admin, "notice.posted", details=n.title)
    db.commit()
    db.refresh(n)
    return n


@router.put("/{notice_id}", response_model=NoticeOut)
def edit_notice(notice_id: int, data: NoticeIn, db: Session = Depends(get_db),
                admin: Employee = Depends(require_super)):
    n = db.get(Notice, notice_id)
    if not n:
        raise HTTPException(status_code=404, detail="Notice not found")
    n.title, n.body, n.pinned, n.expires_on = data.title.strip(), data.body.strip(), data.pinned, data.expires_on
    audit.record(db, admin, "notice.edited", details=n.title)
    db.commit()
    db.refresh(n)
    return n


@router.delete("/{notice_id}")
def remove_notice(notice_id: int, db: Session = Depends(get_db), admin: Employee = Depends(require_super)):
    n = db.get(Notice, notice_id)
    if not n:
        raise HTTPException(status_code=404, detail="Notice not found")
    audit.record(db, admin, "notice.removed", details=n.title)
    db.delete(n)
    db.commit()
    return {"message": "Notice removed"}
