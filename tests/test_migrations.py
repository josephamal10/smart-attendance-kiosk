"""The Alembic migrations must build exactly the schema the models describe."""
from alembic import command
from alembic.migration import MigrationContext
from alembic.autogenerate import compare_metadata
from alembic.script import ScriptDirectory
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.pool import StaticPool

import database
from database import Base


def _engine():
    return create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)


def _head():
    cfg = Config("alembic.ini")
    return ScriptDirectory.from_config(cfg).get_current_head()


def _state(engine):
    with engine.connect() as conn:
        version = conn.execute(text("select version_num from alembic_version")).scalar()
        diff = compare_metadata(MigrationContext.configure(conn, opts={"compare_type": True}), Base.metadata)
    return version, diff


def test_fresh_database_matches_the_models():
    engine = _engine()
    database.init_db(bind=engine)
    version, diff = _state(engine)
    assert version == _head()
    assert diff == [], diff


def test_database_from_before_migrations_is_adopted_without_data_loss():
    engine = _engine()
    with engine.begin() as conn:  # an old database: the baseline schema, some data, no version table
        cfg = Config("alembic.ini")
        cfg.attributes["connection"] = conn
        command.upgrade(cfg, database.HEAD_OF_BASELINE)
        conn.execute(text("drop table alembic_version"))
        conn.execute(text("insert into settings (key, value) values ('company_name', '\"Acme\"')"))
    database.init_db(bind=engine)
    version, diff = _state(engine)
    assert version == _head() and diff == []
    with engine.connect() as conn:
        assert conn.execute(text("select value from settings where key='company_name'")).scalar() == '"Acme"'


def test_running_twice_is_harmless():
    engine = _engine()
    database.init_db(bind=engine)
    database.init_db(bind=engine)
    assert "alembic_version" in inspect(engine).get_table_names()
