from pydantic import BaseModel
from typing import Optional
from datetime import datetime

# ---------- Auth ----------
class LoginRequest(BaseModel):
    username: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str
    role: str
    employee_id: int
    name: str

# ---------- Employee ----------
class EmployeeCreate(BaseModel):
    name: str
    username: str
    password: str
    role: str = "user"

class EmployeeOut(BaseModel):
    id: int
    name: str
    username: str
    role: str
    is_active: bool
    created_at: datetime

    class Config:
        orm_mode = True

# ---------- Attendance ----------
class AttendanceOut(BaseModel):
    id: int
    employee_id: int
    date: str
    in_time: Optional[datetime]
    out_time: Optional[datetime]
    status: str

    class Config:
        orm_mode = True

# ---------- Face ----------
class FaceVerifyResponse(BaseModel):
    verified: bool
    employee_id: Optional[int]
    name: Optional[str]
    action: Optional[str]   # "in" or "out"
    time: Optional[datetime]
    message: str
