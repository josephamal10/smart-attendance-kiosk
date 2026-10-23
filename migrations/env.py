"""Alembic environment. The database comes from the app's DATABASE_URL, or from a live
connection handed over by database.init_db (that's how tests migrate their in-memory DB)."""
from alembic import context
from sqlalchemy import engine_from_config, pool

import models  # noqa: F401 — registers every table on Base
from database import DATABASE_URL, Base

config = context.config
target_metadata = Base.metadata


def _configure(connection):
    # render_as_batch: SQLite can't ALTER most things, so Alembic rebuilds the table instead
    context.configure(connection=connection, target_metadata=target_metadata,
                      render_as_batch=True, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


connection = config.attributes.get("connection")
if connection is not None:
    _configure(connection)
else:
    engine = engine_from_config({"sqlalchemy.url": DATABASE_URL}, prefix="sqlalchemy.", poolclass=pool.NullPool)
    with engine.connect() as conn:
        _configure(conn)
