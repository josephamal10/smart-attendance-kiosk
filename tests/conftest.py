import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)  # face_service creates face_images/ relative to the cwd
os.environ.setdefault("SECRET_KEY", "test-secret-key-not-for-production")

from fastapi.testclient import TestClient          # noqa: E402
from sqlalchemy import create_engine               # noqa: E402
from sqlalchemy.orm import sessionmaker            # noqa: E402
from sqlalchemy.pool import StaticPool             # noqa: E402

import database                                    # noqa: E402
from auth import hash_password                     # noqa: E402
from models import Employee, NO_PASSWORD           # noqa: E402
from main import app                               # noqa: E402
from routes import auth_routes                     # noqa: E402
from services import liveness_service              # noqa: E402


@pytest.fixture
def db_session():
    # Fresh in-memory database per test; StaticPool shares one connection across threads
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    database.init_db(bind=engine)
    Session = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    yield Session
    engine.dispose()


@pytest.fixture
def client(db_session):
    def _get_db():
        db = db_session()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[database.get_db] = _get_db
    auth_routes._failed_attempts.clear()
    liveness_service.reset()
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def make_employee(db_session):
    def _make(username, role="user", password="secret123", active=True, category="Developer"):
        db = db_session()
        emp = Employee(name=username.title(), username=username, category=category,
                       password=hash_password(password) if role == "admin" else NO_PASSWORD,
                       role=role, is_active=active)
        db.add(emp)
        db.commit()
        db.refresh(emp)
        db.close()
        return emp
    return _make


@pytest.fixture
def login(client):
    def _login(username, password="secret123"):
        res = client.post("/auth/login", json={"username": username, "password": password})
        assert res.status_code == 200, res.text
        return {"Authorization": f"Bearer {res.json()['access_token']}"}
    return _login
