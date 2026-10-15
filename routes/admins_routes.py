"""Dashboard accounts: super admins and HR viewers. Managed by super admins only."""
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from auth import ADMIN_ROLES, hash_password, require_super
from database import get_db
from models import Employee
from services import audit

router = APIRouter(prefix="/admin/admins", tags=["Admins"])

Role = Literal["admin", "viewer"]


class AdminOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    username: str
    role: str
    is_active: bool


class AdminCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    username: str = Field(min_length=2, max_length=50, pattern=r"^[A-Za-z0-9._-]+$")
    password: str = Field(min_length=1, max_length=128)
    role: Role = "viewer"


class AdminUpdate(BaseModel):
    role: Optional[Role] = None
    is_active: Optional[bool] = None
    password: Optional[str] = Field(default=None, min_length=1, max_length=128)


def _supers_left(db: Session, excluding: int) -> int:
    return db.query(Employee).filter(Employee.role == "admin", Employee.is_active == True,  # noqa: E712
                                     Employee.id != excluding).count()


@router.get("", response_model=list[AdminOut])
def list_admins(db: Session = Depends(get_db), _: Employee = Depends(require_super)):
    return db.query(Employee).filter(Employee.role.in_(ADMIN_ROLES)).order_by(Employee.name).all()


@router.post("", response_model=AdminOut)
def add_admin(data: AdminCreate, db: Session = Depends(get_db), me: Employee = Depends(require_super)):
    if db.query(Employee).filter(Employee.username == data.username).first():
        raise HTTPException(status_code=400, detail="That username is already taken.")
    a = Employee(name=data.name.strip(), username=data.username, password=hash_password(data.password),
                 role=data.role)
    db.add(a)
    db.flush()
    audit.record(db, me, "admin.added", details=f"{a.name} (@{a.username}) as {_label(a.role)}")
    db.commit()
    db.refresh(a)
    return a


@router.patch("/{admin_id}", response_model=AdminOut)
def update_admin(admin_id: int, data: AdminUpdate, db: Session = Depends(get_db),
                 me: Employee = Depends(require_super)):
    a = db.get(Employee, admin_id)
    if not a or a.role not in ADMIN_ROLES:
        raise HTTPException(status_code=404, detail="Account not found")
    losing_super = a.role == "admin" and ((data.role and data.role != "admin") or data.is_active is False)
    if losing_super and _supers_left(db, excluding=a.id) == 0:
        raise HTTPException(status_code=400, detail="There must always be at least one active super admin.")
    changes = []
    if data.role and data.role != a.role:
        changes.append(f"role → {_label(data.role)}")
        a.role = data.role
    if data.is_active is not None and data.is_active != a.is_active:
        changes.append("enabled" if data.is_active else "disabled")
        a.is_active = data.is_active
    if data.password:
        changes.append("password reset")
        a.password = hash_password(data.password)
    if changes:
        audit.record(db, me, "admin.updated", details=f"{a.name}: {', '.join(changes)}")
    db.commit()
    db.refresh(a)
    return a


def _label(role: str) -> str:
    return "Super admin" if role == "admin" else "HR viewer"
