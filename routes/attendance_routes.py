from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session

from auth import get_current_user, require_self_or_admin
from database import get_db
from models import Employee
from schemas import FaceVerifyResponse, AttendanceOut, LivenessResponse
from services import liveness_service
from services.face_service import measure_ear, verify_face
from services.attendance_service import mark_attendance, get_today_log

router = APIRouter(prefix="/attendance", tags=["Attendance"])

# These endpoints are plain `def`, not `async def`: face detection is slow CPU work,
# and FastAPI runs sync endpoints in a thread pool so one scan doesn't freeze the server.


@router.post("/liveness", response_model=LivenessResponse)
def liveness_frame(
    file: UploadFile = File(...),
    user: Employee = Depends(get_current_user),
):
    """Send camera frames here until `live` is true; then use the returned token to verify."""
    m = measure_ear(file.file.read())
    if not m["ok"]:
        return LivenessResponse(live=False, face_found=False, ear=0.0, message=m["message"])

    if liveness_service.observe(user.id, m["ear"]):
        return LivenessResponse(
            live=True, face_found=True, ear=m["ear"], message="Blink detected",
            liveness_token=liveness_service.issue_token(user.id),
        )
    return LivenessResponse(live=False, face_found=True, ear=m["ear"], message="Please blink")


@router.post("/verify", response_model=FaceVerifyResponse)
def verify_and_mark(
    liveness_token: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: Employee = Depends(get_current_user),
):
    if not liveness_service.consume_token(liveness_token, user.id):
        raise HTTPException(status_code=403, detail="Liveness check missing or expired. Please blink again.")

    employee, msg = verify_face(db, file.file.read(), employee_id=user.id)
    if not employee:
        return FaceVerifyResponse(verified=False, message=msg)

    result = mark_attendance(db, employee)
    action = result["action"]
    messages = {
        "in":       f"Checked IN successfully — {employee.name}",
        "out":      f"Checked OUT successfully — {employee.name}",
        "done":     f"{employee.name} has already completed attendance for today.",
        "too_soon": "You just checked in. Scan again later to check out.",
    }
    return FaceVerifyResponse(
        verified=True,
        employee_id=employee.id,
        name=employee.name,
        action=action,
        time=result["time"],
        message=messages[action],
    )


@router.get("/today/{employee_id}", response_model=AttendanceOut)
def get_today(employee_id: int, db: Session = Depends(get_db),
              user: Employee = Depends(get_current_user)):
    require_self_or_admin(employee_id, user)
    log = get_today_log(db, employee_id)
    if not log:
        raise HTTPException(status_code=404, detail="No attendance record for today")
    return log
