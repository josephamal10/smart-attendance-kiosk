"""Each test here pins down one of the holes found in the original code."""
import io

import pytest

from routes import face_routes

IMG = {"file": ("f.jpg", io.BytesIO(b"fake"), "image/jpeg")}


@pytest.mark.parametrize("path", [
    "/admin/attendance/today",
    "/admin/attendance/all",
    "/admin/employees",
    "/admin/attendance/percentage",
    "/admin/reports/export",
])
def test_admin_routes_need_login(client, path):
    assert client.get(path).status_code == 401


def test_admin_routes_reject_normal_users(client, make_employee, login):
    make_employee("amal")
    assert client.get("/admin/employees", headers=login("amal")).status_code == 403


def test_admin_routes_work_for_admin(client, make_employee, login):
    make_employee("boss", role="admin")
    assert client.get("/admin/employees", headers=login("boss")).status_code == 200


def test_cannot_self_register_as_admin(client):
    res = client.post("/auth/register", json={
        "name": "Mallory", "username": "mallory", "password": "hunter22", "role": "admin"})
    assert res.status_code == 401


def test_admin_can_register_employee(client, make_employee, login):
    make_employee("boss", role="admin")
    res = client.post("/auth/register", headers=login("boss"), json={
        "name": "New Hire", "username": "newhire", "password": "hunter22"})
    assert res.status_code == 200
    assert res.json()["role"] == "user"


def test_register_rejects_unknown_role(client, make_employee, login):
    make_employee("boss", role="admin")
    res = client.post("/auth/register", headers=login("boss"), json={
        "name": "X", "username": "xx", "password": "hunter22", "role": "superuser"})
    assert res.status_code == 422


def test_public_employee_list_hides_roles(client, make_employee):
    make_employee("boss", role="admin")
    data = client.get("/auth/employees").json()
    assert data and set(data[0]) == {"id", "name", "username"}


def test_cannot_register_face_on_someone_elses_account(client, make_employee, login, monkeypatch):
    make_employee("amal")
    victim = make_employee("jp")
    monkeypatch.setattr(face_routes, "save_face_image",
                        lambda *a: pytest.fail("should not reach save"))
    res = client.post("/face/register", headers=login("amal"),
                      data={"employee_id": victim.id, "direction": "straight"}, files=IMG)
    assert res.status_code == 403


def test_can_register_own_face(client, make_employee, login, monkeypatch):
    me = make_employee("amal")
    monkeypatch.setattr(face_routes, "save_face_image",
                        lambda db, eid, d, b: {"success": True, "message": "ok", "total": 1, "image_id": 1})
    res = client.post("/face/register", headers=login("amal"),
                      data={"employee_id": me.id, "direction": "straight"}, files=IMG)
    assert res.status_code == 200


def test_cannot_wipe_someone_elses_faces(client, make_employee, login):
    make_employee("amal")
    victim = make_employee("jp")
    assert client.delete(f"/face/delete/{victim.id}", headers=login("amal")).status_code == 403


def test_disabled_account_cannot_log_in(client, make_employee):
    make_employee("gone", active=False)
    res = client.post("/auth/login", json={"username": "gone", "password": "secret123"})
    assert res.status_code == 401


def test_lockout_after_five_failures(client, make_employee):
    make_employee("amal")
    for _ in range(4):
        assert client.post("/auth/login", json={"username": "amal", "password": "bad"}).status_code == 401
    assert client.post("/auth/login", json={"username": "amal", "password": "bad"}).status_code == 423
    # Even the right password is refused while locked
    assert client.post("/auth/login", json={"username": "amal", "password": "secret123"}).status_code == 423
