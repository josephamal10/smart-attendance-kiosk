from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from schemas import FaceVerifyResponse, AttendanceOut
from services.face_service import recognize_face
from services.attendance_service import mark_attendance, get_today_log

router = APIRouter(prefix="/attendance", tags=["Attendance"])

@router.post("/verify", response_model=FaceVerifyResponse)
async def verify_and_mark(
    employee_id: int | None = Form(None),
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    contents = await file.read()
    employee = recognize_face(db, contents, employee_id=employee_id)

    if not employee:
        return FaceVerifyResponse(
            verified=False,
            message="Face not recognized. Please try again."
        )

    result = mark_attendance(db, employee)
    action = result["action"]

    if action == "done":
        return FaceVerifyResponse(
            verified=True,
            employee_id=employee.id,
            name=employee.name,
            action="done",
            time=result["time"],
            message=f"{employee.name} has already completed attendance for today."
        )

    return FaceVerifyResponse(
        verified=True,
        employee_id=employee.id,
        name=employee.name,
        action=action,
        time=result["time"],
        message=f"{'Checked IN' if action == 'in' else 'Checked OUT'} successfully — {employee.name}"
    )

@router.get("/today/{employee_id}", response_model=AttendanceOut)
def get_today(employee_id: int, db: Session = Depends(get_db)):
    log = get_today_log(db, employee_id)
    if not log:
        raise HTTPException(status_code=404, detail="No attendance record for today")
    return log
