import os
from typing import Literal

from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session

from auth import get_current_user, require_self_or_admin
from database import get_db
from models import Employee, FaceImage
from services import audit
from services.face_service import save_face_image, get_face_count_by_employee

router = APIRouter(prefix="/face", tags=["Face"])


def _delete_row(db: Session, row: FaceImage) -> None:
    if os.path.exists(row.image_path):
        os.remove(row.image_path)
    db.delete(row)


@router.post("/register")
def register_face(
    employee_id: int = Form(...),
    direction: Literal["straight", "left", "right"] = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: Employee = Depends(get_current_user),
):
    """
    Receive one face image, extract embedding, store in DB.
    Called 10 times per direction (straight / left / right).
    Users can only add faces to their own account; admins can add to anyone's.
    """
    require_self_or_admin(employee_id, user)
    if not db.get(Employee, employee_id):
        raise HTTPException(status_code=404, detail="Employee not found")

    result = save_face_image(db, employee_id, direction, file.file.read())
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["message"])

    return {
        "message": result["message"],
        "total": result["total"],
        "image_id": result.get("image_id"),
    }


@router.delete("/image/{image_id}")
def delete_face_image(
    image_id: int,
    db: Session = Depends(get_db),
    user: Employee = Depends(get_current_user),
):
    """Delete one captured face image."""
    row = db.get(FaceImage, image_id)
    if not row:
        raise HTTPException(status_code=404, detail="Face image not found")
    require_self_or_admin(row.employee_id, user)

    _delete_row(db, row)
    db.commit()
    return {"message": "Face image deleted"}


@router.delete("/delete/{employee_id}")
def delete_face_images(
    employee_id: int,
    db: Session = Depends(get_db),
    user: Employee = Depends(get_current_user),
):
    """Delete all face images for an employee."""
    require_self_or_admin(employee_id, user)
    rows = db.query(FaceImage).filter(FaceImage.employee_id == employee_id).all()
    for row in rows:
        _delete_row(db, row)
    if rows:
        audit.record(db, user, "faces.deleted", employee_id=employee_id, details=f"{len(rows)} photos")
    db.commit()
    return {"message": f"Deleted all face images for employee {employee_id}"}


@router.get("/count/{employee_id}")
def face_count(
    employee_id: int,
    db: Session = Depends(get_db),
    user: Employee = Depends(get_current_user),
):
    """Return how many face images are stored for an employee."""
    require_self_or_admin(employee_id, user)
    count = get_face_count_by_employee(db, employee_id)
    return {"employee_id": employee_id, "count": count, "total": count}
