"""
Daily database backups (SQLite only), using SQLite's online backup API so a copy can
be taken safely while the server is running. Keeps the newest KEEP files.
"""
import glob
import os
import sqlite3
from datetime import datetime

from database import DATABASE_URL

BACKUP_DIR = os.getenv("BACKUP_DIR", "backups")
KEEP = int(os.getenv("BACKUP_KEEP", 14))


def db_path() -> str | None:
    prefix = "sqlite:///"
    return DATABASE_URL[len(prefix):] if DATABASE_URL.startswith(prefix) else None


def _stem(source: str) -> str:
    """Backups are named after their database file, so different databases never mix."""
    return os.path.splitext(os.path.basename(source))[0]


def _pattern(source: str) -> str:
    return os.path.join(BACKUP_DIR, f"{_stem(source)}-????-??-??_??????.db")


def list_backups(source: str | None = None) -> list[dict]:
    source = source or db_path()
    if not source:
        return []
    files = sorted(glob.glob(_pattern(source)), reverse=True)
    return [{"file": os.path.basename(f), "size_kb": round(os.path.getsize(f) / 1024),
             "created": datetime.fromtimestamp(os.path.getmtime(f)).isoformat(timespec="seconds")}
            for f in files]


def backup_now(source: str | None = None) -> str:
    """Copy the database to backups/technerdz-<timestamp>.db and prune old copies."""
    source = source or db_path()
    if not source:
        raise RuntimeError("Automatic backups only support SQLite; back up your MySQL server separately.")
    os.makedirs(BACKUP_DIR, exist_ok=True)
    target = os.path.join(BACKUP_DIR, f"{_stem(source)}-{datetime.now():%Y-%m-%d_%H%M%S}.db")
    src, dst = sqlite3.connect(source), sqlite3.connect(target)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()
    for old in sorted(glob.glob(_pattern(source)), reverse=True)[KEEP:]:
        os.remove(old)
    return os.path.basename(target)
