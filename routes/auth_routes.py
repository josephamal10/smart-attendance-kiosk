from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from database import get_db
from services import demo
from models import Employee
from schemas import LoginRequest, TokenResponse, PasswordChange
from auth import ADMIN_ROLES, hash_password, verify_password, create_access_token, require_admin
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


@router.post("/login", response_model=TokenResponse)
def login(data: LoginRequest, request: Request, db: Session = Depends(get_db)):
    """Admin sign-in. Employees don't sign in at all — they check in with their face."""
    key = _key(data.username, request)
    _check_lockout(key)

    emp = db.query(Employee).filter(Employee.username == data.username).first()
    is_admin = emp is not None and emp.role in ADMIN_ROLES and emp.is_active
    if not is_admin or not verify_password(data.password, emp.password):
        attempts_left = _record_failure(key)
        if attempts_left <= 0:
            raise HTTPException(
                status_code=423,
                detail=f"Account locked for {LOCKOUT_MINUTES} minutes due to too many failed attempts."
            )
        raise HTTPException(
            status_code=401,
            detail=f"Wrong username or password. {attempts_left} attempt(s) remaining."
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


@router.post("/change-password")
def change_password(data: PasswordChange, db: Session = Depends(get_db),
                    admin: Employee = Depends(require_admin)):
    """The signed-in admin sets a new password. Any non-empty password is allowed."""
    demo.block_account_changes()
    if not verify_password(data.current_password, admin.password):
        raise HTTPException(status_code=400, detail="Current password is incorrect.")
    admin.password = hash_password(data.new_password)
    db.commit()
    return {"message": "Password changed."}
