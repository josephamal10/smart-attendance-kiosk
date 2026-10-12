import io
from datetime import datetime, timedelta

import pytest

from routes import attendance_routes
from services import attendance_service
from services.face_service import _ear


def _img():
    return {"file": ("f.jpg", io.BytesIO(b"fake"), "image/jpeg")}


@pytest.fixture
def fake_face(monkeypatch, db_session):
    """Replace the camera/ML parts with a scripted sequence of EAR readings."""
    ears = []

    def measure(_bytes):
        return {"ok": True, "ear": ears.pop(0), "message": "OK"}

    def verify(db, _bytes, employee_id):
        from models import Employee
        return db.get(Employee, employee_id), "OK"

    monkeypatch.setattr(attendance_routes, "measure_ear", measure)
    monkeypatch.setattr(attendance_routes, "verify_face", verify)
    return ears


def _blink(client, headers, ears):
    """Eyes open, open, then closed → server should issue a liveness token."""
    ears.extend([0.30, 0.31, 0.10])
    for _ in range(2):
        assert client.post("/attendance/liveness", headers=headers, files=_img()).json()["live"] is False
    res = client.post("/attendance/liveness", headers=headers, files=_img()).json()
    assert res["live"] is True
    return res["liveness_token"]


def test_verify_without_blink_is_refused(client, make_employee, login, fake_face):
    make_employee("amal")
    res = client.post("/attendance/verify", headers=login("amal"),
                      data={"liveness_token": "made-up"}, files=_img())
    assert res.status_code == 403


def test_verify_needs_login(client):
    res = client.post("/attendance/verify", data={"liveness_token": "x"}, files=_img())
    assert res.status_code == 401


def test_blink_then_check_in(client, make_employee, login, fake_face):
    make_employee("amal")
    h = login("amal")
    token = _blink(client, h, fake_face)
    res = client.post("/attendance/verify", headers=h, data={"liveness_token": token}, files=_img())
    assert res.status_code == 200
    assert res.json()["action"] == "in"


def test_liveness_token_is_single_use(client, make_employee, login, fake_face):
    make_employee("amal")
    h = login("amal")
    token = _blink(client, h, fake_face)
    client.post("/attendance/verify", headers=h, data={"liveness_token": token}, files=_img())
    res = client.post("/attendance/verify", headers=h, data={"liveness_token": token}, files=_img())
    assert res.status_code == 403


def test_liveness_token_cannot_be_used_by_another_user(client, make_employee, login, fake_face):
    make_employee("amal")
    make_employee("jp")
    token = _blink(client, login("amal"), fake_face)
    res = client.post("/attendance/verify", headers=login("jp"),
                      data={"liveness_token": token}, files=_img())
    assert res.status_code == 403


def test_liveness_token_is_not_an_access_token(client, make_employee, login, fake_face):
    make_employee("boss", role="admin")
    token = _blink(client, login("boss"), fake_face)
    res = client.get("/admin/employees", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 401


def test_closed_eyes_alone_are_not_a_blink(client, make_employee, login, fake_face):
    make_employee("amal")
    fake_face.extend([0.08, 0.09, 0.10])  # never saw the eyes open (e.g. a photo with eyes shut)
    h = login("amal")
    for _ in range(3):
        assert client.post("/attendance/liveness", headers=h, files=_img()).json()["live"] is False


def test_quick_second_scan_does_not_check_out(client, make_employee, login, fake_face):
    make_employee("amal")
    h = login("amal")
    client.post("/attendance/verify", headers=h, files=_img(),
                data={"liveness_token": _blink(client, h, fake_face)})
    res = client.post("/attendance/verify", headers=h, files=_img(),
                      data={"liveness_token": _blink(client, h, fake_face)})
    assert res.json()["action"] == "too_soon"


def test_check_out_after_gap(client, make_employee, login, fake_face, monkeypatch):
    make_employee("amal")
    h = login("amal")
    client.post("/attendance/verify", headers=h, files=_img(),
                data={"liveness_token": _blink(client, h, fake_face)})
    monkeypatch.setattr(attendance_service, "MIN_CHECKOUT_GAP", timedelta(0))
    res = client.post("/attendance/verify", headers=h, files=_img(),
                      data={"liveness_token": _blink(client, h, fake_face)})
    assert res.json()["action"] == "out"


def test_users_cannot_read_each_others_attendance(client, make_employee, login):
    make_employee("amal")
    jp = make_employee("jp")
    assert client.get(f"/attendance/today/{jp.id}", headers=login("amal")).status_code == 403


def test_one_row_per_employee_per_day(db_session, make_employee):
    from sqlalchemy.exc import IntegrityError
    from models import AttendanceLog
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
    # An eye 40px wide and 12px tall, drawn into a 640x480 frame
    W, H = 640, 480
    px = [(300, 240), (313, 234), (327, 234), (340, 240), (327, 246), (313, 246)]
    lm = {i: _P(x / W, y / H) for i, (x, y) in enumerate(px)}
    ear = _ear(lm, list(range(6)), W, H)
    assert ear == pytest.approx(12 / 40, rel=1e-6)
