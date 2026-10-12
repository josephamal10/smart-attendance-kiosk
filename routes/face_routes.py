from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from services.face_service import save_face_image, get_face_count_by_employee, detect_blink
from auth import decode_token
from fastapi.security import OAuth2PasswordBearer

router = APIRouter(prefix="/face", tags=["Face"])

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

def get_current_user(token: str = Depends(oauth2_scheme)):
    payload = decode_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return payload


@router.post("/register")
async def register_face(
    employee_id: int = Form(...),
    direction: str   = Form(...),
    file: UploadFile = File(...),
    db: Session      = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """
    Receive one face image, extract embedding, store in DB.
    Called 10 times per direction (straight / left / right).
    """
    if direction not in ("straight", "left", "right"):
        raise HTTPException(status_code=400, detail="Invalid direction")

    image_bytes = await file.read()
    result = save_face_image(db, employee_id, direction, image_bytes)

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
    current_user: dict = Depends(get_current_user),
):
    """Delete one captured face image."""
    from models import FaceImage
    import os

    row = db.query(FaceImage).filter(FaceImage.id == image_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="Face image not found")

    if current_user.get("role") != "admin" and str(row.employee_id) != current_user.get("sub"):
        raise HTTPException(status_code=403, detail="Not allowed to delete this face image")

    if os.path.exists(row.image_path):
        os.remove(row.image_path)
    db.delete(row)
    db.commit()
    return {"message": "Face image deleted"}


@router.delete("/delete/{employee_id}")
def delete_face_images(
    employee_id: int,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Delete all face images for an employee."""
    from models import FaceImage
    import os
    rows = db.query(FaceImage).filter(FaceImage.employee_id == employee_id).all()
    for row in rows:
        if os.path.exists(row.image_path):
            os.remove(row.image_path)
        db.delete(row)
    db.commit()
    return {"message": f"Deleted all face images for employee {employee_id}"}


@router.post("/blink")
async def check_blink(
    file: UploadFile = File(...),
):
    """Receive a frame, return EAR value for blink detection."""
    image_bytes = await file.read()
    result      = detect_blink(image_bytes)
    return result


@router.get("/count/{employee_id}")
def face_count(
    employee_id: int,
    db: Session = Depends(get_db),
):
    """Return how many face images are stored for an employee."""
    count = get_face_count_by_employee(db, employee_id)
    return {"employee_id": employee_id, "count": count, "total": count}
