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

ROOT = os.path.dirname(os.path.abspath(__file__))
HEAD_OF_BASELINE = "0001"
# Tables that existed before migrations were introduced (revision 0001)
BASELINE_TABLES = ["employees", "face_images", "attendance_logs", "settings", "holidays",
                   "leave_requests", "correction_requests", "audit_logs", "notices"]


def init_db(bind=engine):
    """Bring the database to the latest schema by running the Alembic migrations in migrations/.

    A database made before migrations existed (by create_all) is first finished off with the
    old in-place upgrades, then recorded as being at the baseline, so no data is touched."""
    from alembic import command
    from alembic.config import Config
    from sqlalchemy import inspect

    cfg = Config(os.path.join(ROOT, "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(ROOT, "migrations"))
    with bind.begin() as conn:
        cfg.attributes["connection"] = conn
        tables = set(inspect(conn).get_table_names())
        if tables and "alembic_version" not in tables:
            _legacy_upgrade(conn)
            command.stamp(cfg, HEAD_OF_BASELINE)
        command.upgrade(cfg, "head")
        _no_employee_passwords(conn)


def _legacy_upgrade(conn):
    """Old in-place upgrades for pre-migration databases, up to exactly the baseline schema.
    Tables a very old database may lack (notices, holidays...) are created from the models; that
    is only right for tables unchanged since the baseline. employees and attendance_logs, which
    later migrations change, exist in every database this app ever made."""
    from sqlalchemy import inspect, text
    import models  # noqa: F401 — registers the tables on Base

    baseline = [Base.metadata.tables[t] for t in BASELINE_TABLES]
    Base.metadata.create_all(bind=conn, tables=baseline)
    for table in baseline:
        for index in table.indexes:
            index.create(bind=conn, checkfirst=True)
    columns = {c["name"] for c in inspect(conn).get_columns("employees")}
    log_columns = {c["name"] for c in inspect(conn).get_columns("attendance_logs")}
    if "category" not in columns:
        conn.execute(text("ALTER TABLE employees ADD COLUMN category VARCHAR(30)"))
    if "auto_checkout" not in log_columns:
        conn.execute(text("ALTER TABLE attendance_logs ADD COLUMN auto_checkout BOOLEAN NOT NULL DEFAULT 0"))


def _no_employee_passwords(conn):
    """Employees check in by face only; make sure no old employee password still works."""
    from sqlalchemy import text
    from models import NO_PASSWORD
    conn.execute(text("UPDATE employees SET password = :p WHERE role = 'user' AND password != :p"),
                 {"p": NO_PASSWORD})
