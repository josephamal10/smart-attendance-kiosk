"""Append-only record of admin actions and automatic system changes."""
from sqlalchemy.orm import Session

from models import AuditLog, Employee


def record(db: Session, actor: Employee | None, action: str, *,
           employee_id: int | None = None, details: str = "", reason: str = "") -> None:
    """Add an audit entry to the current transaction (the caller commits)."""
    db.add(AuditLog(
        actor_id=actor.id if actor else None,
        actor_name=actor.name if actor else "System",
        action=action,
        employee_id=employee_id,
        details=details,
        reason=reason,
    ))
