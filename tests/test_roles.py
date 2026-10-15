"""Super admin vs HR viewer, and managing dashboard accounts."""
import io


def test_viewer_can_sign_in_and_read(client, make_employee, login):
    make_employee("hr", role="viewer")
    h = login("hr")
    for path in ("/admin/employees", "/admin/attendance/today", "/admin/register", "/admin/analytics",
                 "/admin/reports/export", "/admin/register.xlsx", "/admin/settings", "/admin/audit"):
        assert client.get(path, headers=h).status_code == 200, path


def test_viewer_cannot_change_anything(client, make_employee, login):
    make_employee("hr", role="viewer")
    emp = make_employee("arun")
    h = login("hr")
    attempts = [
        client.post("/admin/employees", headers=h, json={"name": "X", "category": "HR"}),
        client.patch(f"/admin/employees/{emp.id}", headers=h, json={"category": "Tester"}),
        client.post("/admin/holidays", headers=h, json={"date": "2026-12-25", "name": "Xmas"}),
        client.post("/admin/settings/backups", headers=h),
        client.post("/face/register", headers=h, data={"employee_id": emp.id, "direction": "straight"},
                    files={"file": ("f.jpg", io.BytesIO(b"x"), "image/jpeg")}),
        client.delete(f"/face/delete/{emp.id}", headers=h),
        client.get("/admin/admins", headers=h),
    ]
    assert all(r.status_code == 403 for r in attempts), [r.status_code for r in attempts]


def test_viewer_still_sees_face_counts(client, make_employee, login):
    make_employee("hr", role="viewer")
    emp = make_employee("arun")
    assert client.get(f"/face/count/{emp.id}", headers=login("hr")).status_code == 200


def test_super_admin_manages_accounts(client, make_employee, login):
    make_employee("boss", role="admin")
    h = login("boss")
    new = client.post("/admin/admins", headers=h, json={"name": "Hema", "username": "hema",
                                                        "password": "x", "role": "viewer"})
    assert new.status_code == 200 and new.json()["role"] == "viewer"
    assert client.post("/auth/login", json={"username": "hema", "password": "x"}).status_code == 200
    promoted = client.patch(f"/admin/admins/{new.json()['id']}", headers=h, json={"role": "admin"})
    assert promoted.json()["role"] == "admin"
    assert {a["username"] for a in client.get("/admin/admins", headers=h).json()} == {"boss", "hema"}


def test_cannot_remove_the_last_super_admin(client, make_employee, login):
    boss = make_employee("boss", role="admin")
    h = login("boss")
    assert client.patch(f"/admin/admins/{boss.id}", headers=h, json={"role": "viewer"}).status_code == 400
    assert client.patch(f"/admin/admins/{boss.id}", headers=h, json={"is_active": False}).status_code == 400


def test_duplicate_admin_username_rejected(client, make_employee, login):
    make_employee("boss", role="admin")
    h = login("boss")
    assert client.post("/admin/admins", headers=h, json={"name": "B", "username": "boss", "password": "x"}).status_code == 400


def test_employee_ids_are_not_admin_accounts(client, make_employee, login):
    make_employee("boss", role="admin")
    emp = make_employee("arun")
    assert client.patch(f"/admin/admins/{emp.id}", headers=login("boss"), json={"role": "admin"}).status_code == 404
