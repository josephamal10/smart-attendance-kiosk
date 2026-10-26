"""Demo mode only: open an employee's own dashboard without a face scan (see services/demo.py)."""
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from auth import create_access_token
from database import get_db
from models import Employee
from services import demo

router = APIRouter(prefix="/demo", tags=["Demo"])


class DemoDashboardIn(BaseModel):
    employee_id: int


@router.post("/dashboard")
def open_dashboard(data: DemoDashboardIn, db: Session = Depends(get_db)):
    if not demo.enabled():
        raise HTTPException(status_code=404, detail="Not found")
    emp = db.get(Employee, data.employee_id)
    if not emp or emp.role != "user" or not emp.is_active:
        raise HTTPException(status_code=404, detail="Employee not found")
    return {"self_token": create_access_token({"sub": str(emp.id), "type": "self"}, expires=timedelta(minutes=5)),
            "name": emp.name, "category": emp.category}
