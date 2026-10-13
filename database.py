from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from dotenv import load_dotenv
import os

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./technerdz.db")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def init_db(bind=engine):
    """Create missing tables, plus any indexes added to existing tables since
    (create_all only creates indexes together with a brand-new table)."""
    import models  # noqa: F401 — registers the tables on Base
    Base.metadata.create_all(bind=bind)
    for table in Base.metadata.sorted_tables:
        for index in table.indexes:
            index.create(bind=bind, checkfirst=True)
    _upgrade(bind)


def _upgrade(bind):
    """Small in-place upgrades for databases created by older versions.
    (A bigger project would use Alembic migrations for this.)"""
    from sqlalchemy import inspect, text
    from models import NO_PASSWORD

    columns = {c["name"] for c in inspect(bind).get_columns("employees")}
    log_columns = {c["name"] for c in inspect(bind).get_columns("attendance_logs")}
    with bind.begin() as conn:
        if "category" not in columns:
            conn.execute(text("ALTER TABLE employees ADD COLUMN category VARCHAR(30)"))
        if "auto_checkout" not in log_columns:
            conn.execute(text("ALTER TABLE attendance_logs ADD COLUMN auto_checkout BOOLEAN NOT NULL DEFAULT 0"))
        # Employees check in by face only; make sure no old employee password still works
        conn.execute(text("UPDATE employees SET password = :p WHERE role = 'user' AND password != :p"),
                     {"p": NO_PASSWORD})
