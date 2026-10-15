from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
from typing import Literal, Optional, get_args
from datetime import date, datetime

_HHMM = r"^([01]\d|2[0-3]):[0-5]\d$"  # "09:30"


def hhmm(default=...):
    return Field(default, pattern=_HHMM)

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
Flag = Literal["late", "early_leave", "half_day", "missed_checkout"]

class AttendanceOut(BaseModel):
    id: int
    employee_id: int
    date: str
    in_time: Optional[datetime]
    out_time: Optional[datetime]
    status: str
    auto_checkout: bool = False
    flags: list[Flag] = []
    late_minutes: int = 0
    early_minutes: int = 0
    worked_minutes: Optional[int] = None
    overtime_minutes: int = 0

class AttendanceEdit(BaseModel):
    """Admin correction. Times are HH:MM on the record's own date; out_time "" clears it."""
    in_time: Optional[str] = hhmm(None)
    out_time: Optional[str] = Field(default=None, pattern=r"^(([01]\d|2[0-3]):[0-5]\d)?$")
    reason: str = Field(min_length=3, max_length=500)

class AttendanceCreate(BaseModel):
    employee_id: int
    date: date
    in_time: str = hhmm()
    out_time: Optional[str] = hhmm(None)
    reason: str = Field(min_length=3, max_length=500)

# ---------- Settings ----------
class Shift(BaseModel):
    start: str = hhmm()
    end: str = hhmm()

    @field_validator("end")
    @classmethod
    def _after(cls, v, info):
        if "start" in info.data and v <= info.data["start"]:
            raise ValueError("shift must end after it starts")
        return v

class SettingsModel(BaseModel):
    company_name: str = Field(min_length=1, max_length=60)
    work_start: str = hhmm()
    work_end: str = hhmm()
    grace_minutes: int = Field(ge=0, le=180)
    half_day_hours: float = Field(gt=0, le=12)
    weekend_days: list[int]
    min_checkout_minutes: int = Field(ge=0, le=240)
    team_shifts: dict[Category, Shift] = {}
    leave_allowance: dict[Literal["casual", "sick", "other"], int] = {"casual": 12, "sick": 7, "other": 0}
    hr_emails: list[EmailStr]
    email_enabled: bool
    email_time: str = hhmm()

    @field_validator("weekend_days")
    @classmethod
    def _days(cls, v):
        if any(d < 0 or d > 6 for d in v):
            raise ValueError("weekend days are 0 (Mon) to 6 (Sun)")
        return sorted(set(v))

# ---------- Holidays, leave, corrections ----------
class HolidayIn(BaseModel):
    date: date
    name: str = Field(min_length=1, max_length=100)

class HolidayOut(HolidayIn):
    model_config = ConfigDict(from_attributes=True)
    id: int

LeaveKind = Literal["sick", "casual", "other"]

class LeaveIn(BaseModel):
    start_date: date
    end_date: date
    kind: LeaveKind
    reason: str = Field(default="", max_length=500)

    @field_validator("end_date")
    @classmethod
    def _order(cls, v, info):
        if "start_date" in info.data and v < info.data["start_date"]:
            raise ValueError("end date is before start date")
        return v

class AdminLeaveIn(LeaveIn):
    employee_id: int

class LeaveOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    employee_id: int
    start_date: date
    end_date: date
    kind: str
    reason: str
    status: str
    created_at: datetime
    decided_at: Optional[datetime]

class Decision(BaseModel):
    status: Literal["approved", "rejected"]

CorrectionKind = Literal["missed_checkout", "wrong_time", "other"]

class CorrectionIn(BaseModel):
    date: date
    kind: CorrectionKind
    note: str = Field(default="", max_length=500)

class CorrectionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    employee_id: int
    date: date
    kind: str
    note: str
    status: str
    created_at: datetime

class CorrectionDecision(BaseModel):
    status: Literal["resolved", "rejected"]

class AuditOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    at: datetime
    actor_name: str
    action: str
    employee_id: Optional[int]
    details: str
    reason: str

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
    # Today's summary for the result card
    greeting: Optional[str] = None
    flags: list[Flag] = []
    late_minutes: int = 0
    early_minutes: int = 0
    worked_minutes: Optional[int] = None
    overtime_minutes: int = 0
    # Short-lived token for the "My attendance" page (this person only)
    self_token: Optional[str] = None

# ---------- Notices ----------
class NoticeIn(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(default="", max_length=2000)
    pinned: bool = False
    expires_on: Optional[date] = None

class NoticeOut(NoticeIn):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime
    created_by: str
