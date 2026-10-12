from pydantic import BaseModel, ConfigDict, Field
from typing import Literal, Optional
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
    name: str = Field(min_length=1, max_length=100)
    username: str = Field(min_length=2, max_length=50)
    password: str = Field(min_length=6)
    role: Literal["user", "admin"] = "user"

class EmployeePublic(BaseModel):
    """What the login screen is allowed to see before anyone signs in."""
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    username: str

class EmployeeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    username: str
    role: str
    is_active: bool
    created_at: datetime

# ---------- Attendance ----------
class AttendanceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    employee_id: int
    date: str
    in_time: Optional[datetime]
    out_time: Optional[datetime]
    status: str

# ---------- Face ----------
class LivenessResponse(BaseModel):
    live: bool
    face_found: bool
    ear: float
    message: str
    liveness_token: Optional[str] = None

class FaceVerifyResponse(BaseModel):
    verified: bool
    employee_id: Optional[int] = None
    name: Optional[str] = None
    action: Optional[Literal["in", "out", "done", "too_soon"]] = None
    time: Optional[datetime] = None
    message: str
