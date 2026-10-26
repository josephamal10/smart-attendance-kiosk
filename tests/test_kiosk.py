"""Walk-up kiosk: blink → anti-spoof → 1:N identification → IN / OUT."""
import io
import json
from datetime import datetime, timedelta

import numpy as np
import pytest

from models import AttendanceLog, FaceImage
from routes import kiosk_routes
from services import face_service, settings_service
from services.face_engine import Face
from services.face_service import _ear

SID = "test-session-0123456789"


def _img():
    return {"file": ("f.jpg", io.BytesIO(b"fake"), "image/jpeg")}


def _unit(seed: int) -> np.ndarray:
    v = np.random.default_rng(seed).normal(size=128)
    return v / np.linalg.norm(v)


@pytest.fixture
def kiosk(monkeypatch, db_session):
    """Scripted EAR readings + a fake face engine whose next probe embedding we control."""
    state = {"ears": [], "probe": _unit(0)}

    monkeypatch.setattr(kiosk_routes, "measure_ear",
                        lambda b: {"ok": True, "ear": state["ears"].pop(0), "message": "OK"})

    class FakeEngine:
        def detect(self, img):
            return [Face((10, 10, 50, 60), np.zeros((5, 2)), 0.99, np.zeros(15))]

        def embed(self, img, face):
            return state["probe"]

    monkeypatch.setattr(face_service, "get_engine", lambda: FakeEngine())
    monkeypatch.setattr(face_service.cv2, "imdecode", lambda *a: np.zeros((10, 10, 3), np.uint8))
    monkeypatch.setattr(face_service.antispoof_service, "check", lambda img, box: (True, 0.97))

    def register(emp, seed):
        db = db_session()
        for _ in range(3):
            db.add(FaceImage(employee_id=emp.id, image_path="x.jpg", direction="straight",
                             embedding=json.dumps(_unit(seed).tolist())))
        db.commit()
        db.close()

    state["register"] = register
    return state


def _blink(client, state, sid=SID):
    state["ears"].extend([0.30, 0.31, 0.10])  # open, open, closed
    for _ in range(2):
        assert client.post("/kiosk/liveness", data={"session_id": sid}, files=_img()).json()["live"] is False
    res = client.post("/kiosk/liveness", data={"session_id": sid}, files=_img()).json()
    assert res["live"] is True
    return res["liveness_token"]


def _check_in(client, token, sid=SID):
    return client.post("/kiosk/check-in", data={"session_id": sid, "liveness_token": token}, files=_img())


def test_blink_then_recognised_and_checked_in(client, make_employee, kiosk):
    priya = make_employee("priya", category="HR")
    kiosk["register"](priya, seed=1)
    kiosk["probe"] = _unit(1)
    res = _check_in(client, _blink(client, kiosk)).json()
    assert res["recognized"] and res["name"] == "Priya" and res["category"] == "HR"
    assert res["action"] == "in"


def test_picks_the_right_person_among_many(client, make_employee, kiosk):
    for i, name in enumerate(["arun", "meera", "rahul"]):
        kiosk["register"](make_employee(name), seed=10 + i)
    kiosk["probe"] = _unit(11)  # meera
    assert _check_in(client, _blink(client, kiosk)).json()["name"] == "Meera"


def test_stranger_is_not_recognised(client, make_employee, kiosk):
    kiosk["register"](make_employee("arun"), seed=1)
    kiosk["probe"] = _unit(999)  # random vectors in 128-d are ~orthogonal
    res = _check_in(client, _blink(client, kiosk)).json()
    assert res["recognized"] is False


def test_lookalikes_are_refused_not_guessed(client, make_employee, kiosk):
    a, b = make_employee("twin-a"), make_employee("twin-b")
    kiosk["register"](a, seed=5)
    kiosk["register"](b, seed=5)  # identical embeddings: no margin between them
    kiosk["probe"] = _unit(5)
    res = _check_in(client, _blink(client, kiosk)).json()
    assert res["recognized"] is False and "for sure" in res["message"]


def test_disabled_employee_is_not_recognised(client, make_employee, kiosk):
    kiosk["register"](make_employee("gone", active=False), seed=3)
    kiosk["probe"] = _unit(3)
    assert _check_in(client, _blink(client, kiosk)).json()["recognized"] is False


def test_identify_opens_dashboard_without_checking_in(client, make_employee, kiosk, db_session):
    kiosk["register"](make_employee("priya", category="HR"), seed=1)
    kiosk["probe"] = _unit(1)
    token = _blink(client, kiosk)
    res = client.post("/kiosk/identify", data={"session_id": SID, "liveness_token": token}, files=_img()).json()
    assert res["recognized"] and res["name"] == "Priya" and res["action"] is None
    me = client.get("/me", headers={"Authorization": f"Bearer {res['self_token']}"})
    assert me.status_code == 200
    db = db_session()
    assert db.query(AttendanceLog).count() == 0  # nothing recorded
    db.close()


def test_identify_needs_a_blink(client, kiosk):
    res = client.post("/kiosk/identify", data={"session_id": SID, "liveness_token": "nope"}, files=_img())
    assert res.status_code == 403


def test_check_in_without_blink_is_refused(client, kiosk):
    assert _check_in(client, "made-up").status_code == 403


def test_liveness_token_is_single_use(client, make_employee, kiosk):
    kiosk["register"](make_employee("arun"), seed=1)
    kiosk["probe"] = _unit(1)
    token = _blink(client, kiosk)
    assert _check_in(client, token).status_code == 200
    assert _check_in(client, token).status_code == 403


def test_liveness_token_is_bound_to_its_scan_session(client, make_employee, kiosk):
    token = _blink(client, kiosk, sid="session-aaaaaaaaaaaaaaaa")
    assert _check_in(client, token, sid="session-bbbbbbbbbbbbbbbb").status_code == 403


def test_bad_session_id_rejected(client):
    res = client.post("/kiosk/liveness", data={"session_id": "../etc"}, files=_img())
    assert res.status_code == 422


def test_closed_eyes_alone_are_not_a_blink(client, kiosk):
    kiosk["ears"].extend([0.08, 0.09, 0.10])  # never saw the eyes open (a photo with eyes shut)
    for _ in range(3):
        assert client.post("/kiosk/liveness", data={"session_id": SID}, files=_img()).json()["live"] is False


def test_spoof_is_refused(client, make_employee, kiosk, monkeypatch):
    kiosk["register"](make_employee("arun"), seed=1)
    kiosk["probe"] = _unit(1)
    monkeypatch.setattr(face_service.antispoof_service, "check", lambda img, box: (False, 0.03))
    res = _check_in(client, _blink(client, kiosk)).json()
    assert res["recognized"] is False and res["message"] == face_service.SPOOF_MESSAGE


def test_quick_second_scan_does_not_check_out(client, make_employee, kiosk):
    kiosk["register"](make_employee("arun"), seed=1)
    kiosk["probe"] = _unit(1)
    _check_in(client, _blink(client, kiosk))
    assert _check_in(client, _blink(client, kiosk)).json()["action"] == "too_soon"


def test_check_out_after_gap(client, make_employee, kiosk, db_session):
    kiosk["register"](make_employee("arun"), seed=1)
    kiosk["probe"] = _unit(1)
    _check_in(client, _blink(client, kiosk))
    db = db_session()
    settings_service.put(db, "min_checkout_minutes", 0)
    db.commit()
    db.close()
    res = _check_in(client, _blink(client, kiosk)).json()
    assert res["action"] == "out" and res["worked_minutes"] is not None


def test_check_in_returns_greeting_summary_and_self_token(client, make_employee, kiosk):
    kiosk["register"](make_employee("priya", category="HR"), seed=1)
    kiosk["probe"] = _unit(1)
    res = _check_in(client, _blink(client, kiosk)).json()
    assert res["greeting"].endswith("Priya!")
    assert res["self_token"]
    # The token opens that person's own page...
    me = client.get("/me", headers={"Authorization": f"Bearer {res['self_token']}"})
    assert me.status_code == 200 and me.json()["name"] == "Priya"
    # ...but never the admin dashboard
    assert client.get("/admin/employees",
                      headers={"Authorization": f"Bearer {res['self_token']}"}).status_code == 401


def test_one_row_per_employee_per_day(db_session, make_employee):
    from sqlalchemy.exc import IntegrityError
    emp = make_employee("amal")
    db = db_session()
    db.add(AttendanceLog(employee_id=emp.id, date="2026-10-12", in_time=datetime.now()))
    db.add(AttendanceLog(employee_id=emp.id, date="2026-10-12", in_time=datetime.now()))
    with pytest.raises(IntegrityError):
        db.commit()


class _P:
    def __init__(self, x, y):
        self.x, self.y = x, y


def test_ear_uses_pixel_coordinates():
    """The same physical eye must give the same EAR regardless of frame shape."""
    W, H = 640, 480
    px = [(300, 240), (313, 234), (327, 234), (340, 240), (327, 246), (313, 246)]
    lm = {i: _P(x / W, y / H) for i, (x, y) in enumerate(px)}
    assert _ear(lm, list(range(6)), W, H) == pytest.approx(12 / 40, rel=1e-6)


def test_lock_screen_gets_the_company_name_without_signing_in(client, make_employee, login):
    assert client.get("/kiosk/info").json()["company_name"] == "Smart Attendance Kiosk"
    make_employee("boss", role="admin")
    s = client.get("/admin/settings", headers=login("boss")).json()
    s.pop("smtp_configured", None)
    client.put("/admin/settings", headers=login("boss"), json={**s, "company_name": "Acme Corp"})
    assert client.get("/kiosk/info").json()["company_name"] == "Acme Corp"


# ── Demo mode ────────────────────────────────────────────────

def test_demo_mode_is_off_by_default(client, make_employee):
    arun = make_employee("arun")
    assert client.get("/kiosk/info").json()["demo"] is None
    assert client.post("/demo/dashboard", json={"employee_id": arun.id}).status_code == 404


def test_demo_mode_never_runs_on_a_real_database(monkeypatch):
    import database
    from services import demo
    monkeypatch.setenv("DEMO_MODE", "1")
    monkeypatch.setattr(database, "DATABASE_URL", "sqlite:///./technerdz.db")
    assert not demo.enabled()
    monkeypatch.setattr(database, "DATABASE_URL", "sqlite:///./demo.db")
    assert demo.enabled()


def test_demo_shows_accounts_and_opens_employee_dashboards(client, make_employee, monkeypatch):
    from services import demo
    monkeypatch.setattr(demo, "enabled", lambda: True)
    boss = make_employee("boss", role="admin")
    arun = make_employee("arun", category="Tester")
    info = client.get("/kiosk/info").json()["demo"]
    assert info["accounts"][0]["username"] == "boss" and info["accounts"][0]["password"] == demo.DEMO_PASSWORD
    assert info["employees"] == [{"id": arun.id, "name": "Arun", "category": "Tester"}]
    opened = client.post("/demo/dashboard", json={"employee_id": arun.id}).json()
    me = client.get("/me", headers={"Authorization": f"Bearer {opened['self_token']}"})
    assert me.status_code == 200 and me.json()["name"] == "Arun"
    # admin accounts can't be opened this way
    assert client.post("/demo/dashboard", json={"employee_id": boss.id}).status_code == 404


def test_demo_accounts_cannot_be_changed_by_visitors(client, make_employee, login, monkeypatch):
    from services import demo
    boss = make_employee("boss", role="admin")
    headers = login("boss")
    monkeypatch.setattr(demo, "enabled", lambda: True)
    assert client.post("/auth/change-password", headers=headers,
                       json={"current_password": "secret123", "new_password": "mine"}).status_code == 403
    assert client.patch(f"/admin/admins/{boss.id}", headers=headers, json={"password": "x"}).status_code == 403
    assert client.post("/admin/admins", headers=headers,
                       json={"name": "Eve", "username": "eve", "password": "x", "role": "admin"}).status_code == 403
    assert client.post("/auth/login", json={"username": "boss", "password": "secret123"}).status_code == 200
