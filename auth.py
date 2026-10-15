from passlib.context import CryptContext
from jose import JWTError, jwt
from datetime import datetime, timedelta, timezone
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from dotenv import load_dotenv
import os
import uuid

from database import get_db
from models import Employee

load_dotenv()

SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("SECRET_KEY is not set. Copy .env.example to .env and fill it in.")
ALGORITHM = os.getenv("ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 60))

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    # A non-hash value (e.g. employees' "!" placeholder) must simply never match, not crash
    try:
        return pwd_context.verify(plain, hashed)
    except (ValueError, TypeError):
        return False

def create_access_token(data: dict, expires: timedelta | None = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire, "jti": uuid.uuid4().hex})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None


# ── FastAPI dependencies ──────────────────────────────────────────────────────

def get_current_user(token: str = Depends(oauth2_scheme),
                     db: Session = Depends(get_db)) -> Employee:
    payload = decode_token(token)
    # Liveness tokens are signed with the same key, so reject anything that isn't an access token
    if not payload or payload.get("type", "access") != "access":
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    emp = db.get(Employee, int(payload["sub"]))
    if not emp or not emp.is_active:
        raise HTTPException(status_code=401, detail="Account not found or disabled")
    return emp

# Dashboard roles: "admin" = super admin (everything), "viewer" = HR viewer (read + export only)
ADMIN_ROLES = ("admin", "viewer")


def require_admin(user: Employee = Depends(get_current_user)) -> Employee:
    """Any dashboard account — enough to view and export."""
    if user.role not in ADMIN_ROLES:
        raise HTTPException(status_code=403, detail="Admin access required")
    return user


def require_super(user: Employee = Depends(get_current_user)) -> Employee:
    """Changes (edits, approvals, settings, faces) need a super admin."""
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="Your account can view but not change things. Ask a super admin.")
    return user

def require_self_or_admin(employee_id: int, user: Employee) -> None:
    """Raise 403 unless the caller is that employee or an admin."""
    if user.role != "admin" and user.id != employee_id:
        raise HTTPException(status_code=403, detail="Not allowed for this employee")
