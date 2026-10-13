from pydantic import BaseModel, ConfigDict, Field
from typing import Literal, Optional, get_args
from datetime import datetime

# Job categories. "Admin" is a job title like the others; dashboard access comes only from
# an account with role="admin" (created with scripts/create_admin.py).
Category = Literal["HR", "Project Manager", "Admin", "Developer", "Tester"]
CATEGORIES: list[str] = list(get_args(Category))

# ---------- Auth (admin accounts only) ----------
class LoginRequest(BaseModel):
    username: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str
    role: str
    employee_id: int
    name: str

class PasswordChange(BaseModel):
    current_password: str
    new_password: str = Field(min_length=1, max_length=128)  # any password the admin likes

# ---------- Employee ----------
class EmployeeCreate(BaseModel):
    """Employees have no username or password: they check in with their face."""
    name: str = Field(min_length=1, max_length=100)
    category: Category

class EmployeeUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=100)
    category: Optional[Category] = None
    is_active: Optional[bool] = None

class EmployeeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    category: Optional[str]
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

# ---------- Kiosk ----------
class LivenessResponse(BaseModel):
    live: bool
    face_found: bool
    ear: float
    message: str
    liveness_token: Optional[str] = None

class CheckInResponse(BaseModel):
    recognized: bool
    employee_id: Optional[int] = None
    name: Optional[str] = None
    category: Optional[str] = None
    action: Optional[Literal["in", "out", "done", "too_soon"]] = None
    time: Optional[datetime] = None
    message: str
