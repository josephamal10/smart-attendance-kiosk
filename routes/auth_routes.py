from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from database import get_db
from models import Employee
from schemas import LoginRequest, TokenResponse, EmployeeCreate, EmployeeOut, EmployeePublic
from auth import hash_password, verify_password, create_access_token, require_admin
from datetime import datetime, timedelta

router = APIRouter(prefix="/auth", tags=["Auth"])

# In-memory failed attempt tracker, keyed by (username, client IP) so that someone
# guessing passwords from one machine can't lock the real user out everywhere.
# { (username, ip): { "count": int, "locked_until": datetime | None } }
_failed_attempts: dict = {}
MAX_ATTEMPTS   = 5
LOCKOUT_MINUTES = 5


def _key(username: str, request: Request) -> tuple[str, str]:
    return (username.lower(), request.client.host if request.client else "?")


def _check_lockout(key):
    entry = _failed_attempts.get(key)
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
        _failed_attempts.pop(key, None)


def _record_failure(key) -> int:
    """Record a failed attempt and return how many attempts are left."""
    entry = _failed_attempts.get(key, {"count": 0, "locked_until": None})
    entry["count"] += 1
    if entry["count"] >= MAX_ATTEMPTS:
        entry["locked_until"] = datetime.utcnow() + timedelta(minutes=LOCKOUT_MINUTES)
    _failed_attempts[key] = entry
    return MAX_ATTEMPTS - entry["count"]


@router.post("/register", response_model=EmployeeOut)
def register(data: EmployeeCreate, db: Session = Depends(get_db),
             _admin: Employee = Depends(require_admin)):
    """Create an employee. Admin only — otherwise anyone could make themselves an admin."""
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
def login(data: LoginRequest, request: Request, db: Session = Depends(get_db)):
    key = _key(data.username, request)
    _check_lockout(key)

    emp = db.query(Employee).filter(Employee.username == data.username).first()
    if not emp or not emp.is_active or not verify_password(data.password, emp.password):
        attempts_left = _record_failure(key)
        if attempts_left <= 0:
            raise HTTPException(
                status_code=423,
                detail=f"Account locked for {LOCKOUT_MINUTES} minutes due to too many failed attempts."
            )
        raise HTTPException(
            status_code=401,
            detail=f"Invalid credentials. {attempts_left} attempt(s) remaining."
        )

    _failed_attempts.pop(key, None)

    token = create_access_token({"sub": str(emp.id), "role": emp.role, "type": "access"})
    return {
        "access_token": token,
        "token_type":   "bearer",
        "role":         emp.role,
        "employee_id":  emp.id,
        "name":         emp.name,
    }


@router.get("/employees", response_model=list[EmployeePublic])
def list_employees(db: Session = Depends(get_db)):
    """Public: names for the kiosk login dropdown. Roles and other details stay private."""
    return db.query(Employee).filter(Employee.is_active == True).order_by(Employee.name).all()
