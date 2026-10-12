from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, Index
from sqlalchemy.orm import relationship
from database import Base
from datetime import datetime, timezone


def _utcnow():
    return datetime.now(timezone.utc)


class Employee(Base):
    __tablename__ = "employees"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    username = Column(String(50), unique=True, nullable=False)
    password = Column(String(255), nullable=False)
    role = Column(String(10), default="user")  # "admin" or "user"
    is_active = Column(Boolean, default=True)
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

    employee = relationship("Employee", back_populates="attendance_logs")
