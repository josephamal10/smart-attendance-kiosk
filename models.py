from sqlalchemy import Column, Integer, String, Date, DateTime, Boolean, Text, ForeignKey, Index
from sqlalchemy.orm import relationship
from database import Base
from datetime import datetime, timezone


# Stored instead of a hash for employees. Not a valid bcrypt hash, so it can never match.
NO_PASSWORD = "!"


def _utcnow():
    return datetime.now(timezone.utc)


class Employee(Base):
    __tablename__ = "employees"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    username = Column(String(50), unique=True, nullable=False)  # only meaningful for admins
    # bcrypt hash for admins; employees check in by face and have no usable password
    password = Column(String(255), nullable=False, default=NO_PASSWORD)
    role = Column(String(10), default="user")  # "admin" (dashboard) or "user" (employee)
    category = Column(String(30), nullable=True)  # HR, Developer, ... (see schemas.CATEGORIES)
    is_active = Column(Boolean, default=True)
    birthday = Column(Date, nullable=True)        # optional: celebrated on the lock screen
    joined_on = Column(Date, nullable=True)       # optional: work anniversaries on the lock screen
    created_at = Column(DateTime, default=_utcnow)

    face_images = relationship("FaceImage", back_populates="employee")
    attendance_logs = relationship("AttendanceLog", back_populates="employee")


class FaceImage(Base):
    __tablename__ = "face_images"

    id = Column(Integer, primary_key=True, index=True)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=False)
    image_path = Column(String(255), nullable=False)
    direction = Column(String(10), nullable=False)  # straight, left, right
    embedding = Column(Text, nullable=False)  # JSON string of face embedding
    created_at = Column(DateTime, default=_utcnow)

    employee = relationship("Employee", back_populates="face_images")


class AttendanceLog(Base):
    __tablename__ = "attendance_logs"
    # One row per employee per day — stops two simultaneous scans creating duplicates
    __table_args__ = (Index("uq_attendance_employee_date", "employee_id", "date", unique=True),)

    id = Column(Integer, primary_key=True, index=True)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=False)
    date = Column(String(20), nullable=False)        # YYYY-MM-DD (local office date)
    in_time = Column(DateTime, nullable=True)        # local office time
    out_time = Column(DateTime, nullable=True)
    status = Column(String(10), default="present")   # present / absent
    # True when the system closed a day the person forgot to check out of
    auto_checkout = Column(Boolean, default=False, nullable=False)

    employee = relationship("Employee", back_populates="attendance_logs")
    # Late / early leave / half day are not stored: they're worked out from the current
    # work rules (services/rules.py), so changing office hours re-evaluates history.


class Setting(Base):
    """Key/value store for things the admin can change in the dashboard (work hours, email...)."""
    __tablename__ = "settings"

    key = Column(String(50), primary_key=True)
    value = Column(Text, nullable=False)


class Holiday(Base):
    __tablename__ = "holidays"

    id = Column(Integer, primary_key=True)
    date = Column(Date, nullable=False, unique=True)
    name = Column(String(100), nullable=False)


class LeaveRequest(Base):
    __tablename__ = "leave_requests"

    id = Column(Integer, primary_key=True)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=False, index=True)
    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=False)
    kind = Column(String(20), nullable=False)               # sick / casual / other / wfh (work from home)
    reason = Column(Text, default="")
    status = Column(String(10), default="pending", nullable=False)  # pending / approved / rejected
    created_at = Column(DateTime, default=_utcnow)
    decided_at = Column(DateTime, nullable=True)
    decided_by = Column(Integer, ForeignKey("employees.id"), nullable=True)

    employee = relationship("Employee", foreign_keys=[employee_id])


class CorrectionRequest(Base):
    """An employee telling the admin their attendance is wrong (e.g. forgot to check out)."""
    __tablename__ = "correction_requests"

    id = Column(Integer, primary_key=True)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=False, index=True)
    date = Column(Date, nullable=False)
    kind = Column(String(30), nullable=False)               # missed_checkout / wrong_time / other
    note = Column(Text, default="")
    status = Column(String(10), default="pending", nullable=False)  # pending / resolved / rejected
    created_at = Column(DateTime, default=_utcnow)
    resolved_at = Column(DateTime, nullable=True)

    employee = relationship("Employee", foreign_keys=[employee_id])


class AuditLog(Base):
    """Who changed what, when and why. Written for every admin action and system job."""
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True)
    at = Column(DateTime, default=datetime.now, nullable=False, index=True)  # local time
    actor_id = Column(Integer, ForeignKey("employees.id"), nullable=True)  # null = system
    actor_name = Column(String(100), nullable=False)
    action = Column(String(50), nullable=False)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=True)
    details = Column(Text, default="")
    reason = Column(Text, default="")


class Notice(Base):
    """A company announcement shown on the kiosk and in everyone's dashboard."""
    __tablename__ = "notices"

    id = Column(Integer, primary_key=True)
    title = Column(String(120), nullable=False)
    body = Column(Text, default="")
    pinned = Column(Boolean, default=False, nullable=False)
    expires_on = Column(Date, nullable=True)          # last day it's shown; null = until removed
    created_at = Column(DateTime, default=datetime.now, nullable=False)  # local time
    created_by = Column(String(100), nullable=False)


class ShiftChange(Base):
    """An employee asking to work different hours on one day (e.g. 11:00–20:00 for a doctor's
    appointment). Once approved, late / early leave / overtime use these hours for that day."""
    __tablename__ = "shift_changes"

    id = Column(Integer, primary_key=True)
    employee_id = Column(Integer, ForeignKey("employees.id"), nullable=False, index=True)
    date = Column(Date, nullable=False)
    start = Column(String(5), nullable=False)               # "HH:MM"
    end = Column(String(5), nullable=False)
    reason = Column(Text, default="")
    status = Column(String(10), default="pending", nullable=False)  # pending / approved / rejected
    created_at = Column(DateTime, default=datetime.now)
    decided_at = Column(DateTime, nullable=True)
    decided_by = Column(Integer, ForeignKey("employees.id"), nullable=True)

    employee = relationship("Employee", foreign_keys=[employee_id])
