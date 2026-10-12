from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models import Employee
from schemas import LoginRequest, TokenResponse, EmployeeCreate, EmployeeOut
from auth import hash_password, verify_password, create_access_token
from datetime import datetime, timedelta

router = APIRouter(prefix="/auth", tags=["Auth"])

# In-memory failed attempt tracker
# { username: { "count": int, "locked_until": datetime | None } }
_failed_attempts: dict = {}
MAX_ATTEMPTS   = 5
LOCKOUT_MINUTES = 5


def _check_lockout(username: str):
    entry = _failed_attempts.get(username)
    if not entry:
        return
    if entry["locked_until"] and datetime.utcnow() < entry["locked_until"]:
        remaining = int((entry["locked_until"] - datetime.utcnow()).total_seconds() / 60) + 1
        raise HTTPException(
            status_code=423,
            detail=f"Account locked. Try again in {remaining} minute(s)."
        )
    # Lockout expired — reset
    if entry["locked_until"] and datetime.utcnow() >= entry["locked_until"]:
        _failed_attempts.pop(username, None)


def _record_failure(username: str):
    entry = _failed_attempts.get(username, {"count": 0, "locked_until": None})
    entry["count"] += 1
    if entry["count"] >= MAX_ATTEMPTS:
        entry["locked_until"] = datetime.utcnow() + timedelta(minutes=LOCKOUT_MINUTES)
    _failed_attempts[username] = entry


def _clear_failures(username: str):
    _failed_attempts.pop(username, None)


@router.post("/register", response_model=EmployeeOut)
def register(data: EmployeeCreate, db: Session = Depends(get_db)):
    existing = db.query(Employee).filter(Employee.username == data.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="Username already exists")
    emp = Employee(
        name=data.name,
        username=data.username,
        password=hash_password(data.password),
        role=data.role
    )
    db.add(emp)
    db.commit()
    db.refresh(emp)
    return emp


@router.post("/login", response_model=TokenResponse)
def login(data: LoginRequest, db: Session = Depends(get_db)):
    # Check lockout first
    _check_lockout(data.username)

    emp = db.query(Employee).filter(Employee.username == data.username).first()
    if not emp or not verify_password(data.password, emp.password):
        _record_failure(data.username)
        entry = _failed_attempts.get(data.username, {})
        attempts_left = MAX_ATTEMPTS - entry.get("count", 0)
        if attempts_left <= 0:
            raise HTTPException(
                status_code=423,
                detail=f"Account locked for {LOCKOUT_MINUTES} minutes due to too many failed attempts."
            )
        raise HTTPException(
            status_code=401,
            detail=f"Invalid credentials. {attempts_left} attempt(s) remaining."
        )

    # Success — clear any failed attempts
    _clear_failures(data.username)

    token = create_access_token({"sub": str(emp.id), "role": emp.role})
    return {
        "access_token": token,
        "token_type":   "bearer",
        "role":         emp.role,
        "employee_id":  emp.id,
        "name":         emp.name,
    }


@router.get("/employees", response_model=list[EmployeeOut])
def list_employees(db: Session = Depends(get_db)):
    return db.query(Employee).filter(Employee.is_active == True).all()