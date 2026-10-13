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


def test_employees_cannot_sign_in(client, make_employee):
    """Employees have no password at all — even the old default can't get a token."""
    make_employee("amal")
    for pw in ("secret123", "!", ""):
        assert client.post("/auth/login", json={"username": "amal", "password": pw}).status_code == 401


def test_admin_routes_work_for_admin(client, make_employee, login):
    make_employee("boss", role="admin")
    assert client.get("/admin/employees", headers=login("boss")).status_code == 200


def test_creating_employees_needs_admin(client):
    res = client.post("/admin/employees", json={"name": "Mallory", "category": "Developer"})
    assert res.status_code == 401


def test_admin_creates_employee_with_category(client, make_employee, login):
    make_employee("boss", role="admin")
    res = client.post("/admin/employees", headers=login("boss"),
                      json={"name": "Priya Raman", "category": "HR"})
    assert res.status_code == 200
    body = res.json()
    assert body["category"] == "HR" and body["role"] == "user"
    assert "password" not in body and "username" not in body


def test_unknown_category_rejected(client, make_employee, login):
    make_employee("boss", role="admin")
    res = client.post("/admin/employees", headers=login("boss"),
                      json={"name": "X", "category": "Astronaut"})
    assert res.status_code == 422


def test_admin_can_edit_category_and_deactivate(client, make_employee, login):
    make_employee("boss", role="admin")
    emp = make_employee("arun", category="Developer")
    h = login("boss")
    res = client.patch(f"/admin/employees/{emp.id}", headers=h, json={"category": "Tester", "is_active": False})
    assert res.json()["category"] == "Tester" and res.json()["is_active"] is False


def test_admin_accounts_cannot_be_edited_as_employees(client, make_employee, login):
    boss = make_employee("boss", role="admin")
    res = client.patch(f"/admin/employees/{boss.id}", headers=login("boss"), json={"is_active": False})
    assert res.status_code == 404


def test_categories_listed_for_admin(client, make_employee, login):
    make_employee("boss", role="admin")
    cats = client.get("/admin/categories", headers=login("boss")).json()
    assert cats == ["HR", "Project Manager", "Admin", "Developer", "Tester"]


def test_no_public_list_of_employee_names(client):
    assert client.get("/auth/employees").status_code == 404


def test_admin_can_set_any_password(client, make_employee, login):
    make_employee("boss", role="admin")
    h = login("boss")
    res = client.post("/auth/change-password", headers=h,
                      json={"current_password": "secret123", "new_password": "x"})
    assert res.status_code == 200
    assert client.post("/auth/login", json={"username": "boss", "password": "x"}).status_code == 200


def test_change_password_needs_current_one(client, make_employee, login):
    make_employee("boss", role="admin")
    res = client.post("/auth/change-password", headers=login("boss"),
                      json={"current_password": "wrong", "new_password": "x"})
    assert res.status_code == 400


def test_registering_faces_needs_admin(client, make_employee, monkeypatch):
    emp = make_employee("amal")
    monkeypatch.setattr(face_routes, "save_face_image",
                        lambda *a: pytest.fail("should not reach save"))
    res = client.post("/face/register", data={"employee_id": emp.id, "direction": "straight"}, files=IMG)
    assert res.status_code == 401


def test_admin_can_register_face(client, make_employee, login, monkeypatch):
    make_employee("boss", role="admin")
    emp = make_employee("amal")
    monkeypatch.setattr(face_routes, "save_face_image",
                        lambda db, eid, d, b: {"success": True, "message": "ok", "total": 1, "image_id": 1})
    res = client.post("/face/register", headers=login("boss"),
                      data={"employee_id": emp.id, "direction": "straight"}, files=IMG)
    assert res.status_code == 200


def test_deleting_faces_needs_admin(client, make_employee):
    emp = make_employee("amal")
    assert client.delete(f"/face/delete/{emp.id}").status_code == 401


def test_disabled_admin_cannot_log_in(client, make_employee):
    make_employee("gone", role="admin", active=False)
    res = client.post("/auth/login", json={"username": "gone", "password": "secret123"})
    assert res.status_code == 401


def test_lockout_after_five_failures(client, make_employee):
    make_employee("amal", role="admin")
    for _ in range(4):
        assert client.post("/auth/login", json={"username": "amal", "password": "bad"}).status_code == 401
    assert client.post("/auth/login", json={"username": "amal", "password": "bad"}).status_code == 423
    # Even the right password is refused while locked
    assert client.post("/auth/login", json={"username": "amal", "password": "secret123"}).status_code == 423
