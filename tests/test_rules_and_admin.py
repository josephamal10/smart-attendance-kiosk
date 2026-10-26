"""Work rules, corrections + audit, holidays & leave, self-service, analytics, scheduler, email."""
from datetime import date, datetime, timedelta

import pytest

from auth import create_access_token
from models import AttendanceLog, AuditLog, LeaveRequest
from services import email_service, rules as R, scheduler, settings_service

TODAY = date.today()


def _log(db_session, emp_id, day, t_in, t_out=None, auto=False):
    db = db_session()
    l = AttendanceLog(employee_id=emp_id, date=day.isoformat(), status="present", auto_checkout=auto,
                      in_time=datetime.combine(day, datetime.strptime(t_in, "%H:%M").time()),
                      out_time=datetime.combine(day, datetime.strptime(t_out, "%H:%M").time()) if t_out else None)
    db.add(l)
    db.commit()
    db.refresh(l)
    db.close()
    return l


def _rules(**kw):
    base = dict(start=datetime.strptime("09:00", "%H:%M").time(), end=datetime.strptime("18:00", "%H:%M").time(),
                grace=timedelta(minutes=15), half_day=timedelta(hours=4), weekend={5, 6})
    base.update(kw)
    return R.Rules(**base)


def _mk(day, t_in, t_out=None, auto=False):
    d = date.fromisoformat(day)
    return AttendanceLog(date=day, auto_checkout=auto,
                         in_time=datetime.combine(d, datetime.strptime(t_in, "%H:%M").time()),
                         out_time=datetime.combine(d, datetime.strptime(t_out, "%H:%M").time()) if t_out else None)


# ── Rules ────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("t_in,late,minutes", [("09:00", False, 0), ("09:15", False, 0), ("09:16", True, 16)])
def test_grace_period(t_in, late, minutes):
    ev = R.evaluate(_mk("2026-10-12", t_in), _rules())
    assert ("late" in ev.flags) is late and ev.late_minutes == minutes


def test_early_leave_and_half_day():
    ev = R.evaluate(_mk("2026-10-12", "09:00", "12:30"), _rules())
    assert {"early_leave", "half_day"} <= set(ev.flags)
    assert ev.early_minutes == 330 and ev.worked_minutes == 210


def test_leaving_within_grace_is_not_early():
    ev = R.evaluate(_mk("2026-10-12", "09:00", "17:50"), _rules())
    assert "early_leave" not in ev.flags
    ev = R.evaluate(_mk("2026-10-12", "09:00", "17:40"), _rules())
    assert "early_leave" in ev.flags and ev.early_minutes == 20


def test_team_shift_changes_what_counts_as_late():
    rules = _rules(shifts={"Developer": (datetime.strptime("10:00", "%H:%M").time(),
                                         datetime.strptime("19:00", "%H:%M").time())})
    log = _mk("2026-10-12", "09:50", "19:00")
    assert "late" not in R.evaluate(log, rules, team="Developer").flags  # their shift starts at 10
    assert "late" in R.evaluate(log, rules, team="HR").flags            # default 9:00 shift


def test_overtime_beyond_shift_length():
    ev = R.evaluate(_mk("2026-10-12", "09:00", "19:30"), _rules())
    assert ev.overtime_minutes == 90
    assert R.evaluate(_mk("2026-10-12", "09:00", "18:10"), _rules()).overtime_minutes == 0  # within grace


def test_team_shifts_saved_and_validated(client, make_employee, login):
    make_employee("boss", role="admin")
    h = login("boss")
    ok = client.put("/admin/settings", headers=h, json=_settings(team_shifts={"Developer": {"start": "10:00", "end": "19:00"}}))
    assert ok.status_code == 200 and ok.json()["team_shifts"]["Developer"]["start"] == "10:00"
    bad = client.put("/admin/settings", headers=h, json=_settings(team_shifts={"Developer": {"start": "19:00", "end": "10:00"}}))
    assert bad.status_code == 422
    assert client.put("/admin/settings", headers=h, json=_settings(team_shifts={"Astronaut": {"start": "09:00", "end": "17:00"}})).status_code == 422


def test_full_day_has_no_flags():
    ev = R.evaluate(_mk("2026-10-12", "08:55", "18:05"), _rules())
    assert ev.flags == [] and ev.worked_minutes == 550


def test_auto_checkout_is_flagged_not_called_early():
    ev = R.evaluate(_mk("2026-10-12", "09:00", "18:00", auto=True), _rules())
    assert ev.flags == ["missed_checkout"]


def test_working_days_skip_weekends_and_holidays():
    mon = date(2026, 10, 12)
    days = R.working_days(_rules(), {date(2026, 10, 14): "Festival"}, mon, mon + timedelta(days=6))
    assert days == [date(2026, 10, 12), date(2026, 10, 13), date(2026, 10, 15), date(2026, 10, 16)]


# ── Admin corrections + audit ────────────────────────────────────────────────

def test_correction_needs_reason_and_is_audited(client, make_employee, login, db_session):
    make_employee("boss", role="admin")
    emp = make_employee("arun")
    day = TODAY - timedelta(days=1)
    log = _log(db_session, emp.id, day, "09:30")
    h = login("boss")
    assert client.patch(f"/admin/attendance/{log.id}", headers=h, json={"out_time": "18:00"}).status_code == 422
    res = client.patch(f"/admin/attendance/{log.id}", headers=h,
                       json={"out_time": "18:10", "reason": "Forgot to scan out, confirmed by manager"})
    assert res.status_code == 200 and res.json()["out_time"].endswith("18:10:00")
    entry = client.get("/admin/audit", headers=h).json()[0]
    assert entry["action"] == "attendance.corrected" and "Forgot" in entry["reason"]
    assert entry["actor_name"] == "Boss"


def test_check_out_must_be_after_check_in(client, make_employee, login, db_session):
    make_employee("boss", role="admin")
    log = _log(db_session, make_employee("arun").id, TODAY, "10:00")
    res = client.patch(f"/admin/attendance/{log.id}", headers=login("boss"),
                       json={"out_time": "09:00", "reason": "test"})
    assert res.status_code == 422


def test_admin_can_add_a_missing_day_once(client, make_employee, login):
    make_employee("boss", role="admin")
    emp = make_employee("arun")
    h = login("boss")
    body = {"employee_id": emp.id, "date": (TODAY - timedelta(days=2)).isoformat(),
            "in_time": "09:05", "out_time": "17:55", "reason": "Kiosk was offline"}
    assert client.post("/admin/attendance", headers=h, json=body).status_code == 200
    assert client.post("/admin/attendance", headers=h, json=body).status_code == 409


def test_attendance_list_includes_flags(client, make_employee, login, db_session):
    make_employee("boss", role="admin")
    _log(db_session, make_employee("arun").id, TODAY, "09:40")
    row = client.get("/admin/attendance/today", headers=login("boss")).json()[0]
    assert row["flags"] == ["late"] and row["late_minutes"] == 40


# ── Holidays & leave ─────────────────────────────────────────────────────────

def test_holiday_crud_and_duplicates(client, make_employee, login):
    make_employee("boss", role="admin")
    h = login("boss")
    hol = client.post("/admin/holidays", headers=h, json={"date": "2026-12-25", "name": "Christmas"}).json()
    assert client.post("/admin/holidays", headers=h, json={"date": "2026-12-25", "name": "Dup"}).status_code == 409
    assert [x["name"] for x in client.get("/admin/holidays?year=2026", headers=h).json()] == ["Christmas"]
    assert client.delete(f"/admin/holidays/{hol['id']}", headers=h).status_code == 200


def test_leave_request_flow_from_kiosk_to_admin(client, make_employee, login):
    make_employee("boss", role="admin")
    emp = make_employee("priya", category="HR")
    me = {"Authorization": "Bearer " + create_access_token({"sub": str(emp.id), "type": "self"})}
    req = client.post("/me/leave", headers=me, json={
        "start_date": (TODAY + timedelta(days=3)).isoformat(),
        "end_date": (TODAY + timedelta(days=4)).isoformat(), "kind": "casual", "reason": "Family function"})
    assert req.status_code == 200 and req.json()["status"] == "pending"
    h = login("boss")
    pending = client.get("/admin/leave?status=pending", headers=h).json()
    assert [p["id"] for p in pending] == [req.json()["id"]]
    done = client.post(f"/admin/leave/{req.json()['id']}/decision", headers=h, json={"status": "approved"})
    assert done.json()["status"] == "approved"


def test_leave_end_before_start_rejected(client, make_employee):
    emp = make_employee("priya")
    me = {"Authorization": "Bearer " + create_access_token({"sub": str(emp.id), "type": "self"})}
    res = client.post("/me/leave", headers=me, json={"start_date": "2026-10-20", "end_date": "2026-10-18",
                                                     "kind": "sick"})
    assert res.status_code == 422


def test_correction_request_reaches_admin(client, make_employee, login):
    make_employee("boss", role="admin")
    emp = make_employee("arun")
    me = {"Authorization": "Bearer " + create_access_token({"sub": str(emp.id), "type": "self"})}
    client.post("/me/corrections", headers=me, json={"date": TODAY.isoformat(), "kind": "missed_checkout",
                                                     "note": "Left at 6:30"})
    h = login("boss")
    cr = client.get("/admin/corrections?status=pending", headers=h).json()[0]
    assert cr["note"] == "Left at 6:30"
    assert client.post(f"/admin/corrections/{cr['id']}/decision", headers=h,
                       json={"status": "resolved"}).json()["status"] == "resolved"


def test_self_token_cannot_be_an_admin_token_and_vice_versa(client, make_employee, login):
    make_employee("boss", role="admin")
    assert client.get("/me", headers=login("boss")).status_code == 401
    assert client.get("/me").status_code == 401


def test_approved_leave_reduces_expected_days(client, make_employee, login, db_session):
    make_employee("boss", role="admin")
    emp = make_employee("arun")
    db = db_session()
    db.add(LeaveRequest(employee_id=emp.id, start_date=TODAY.replace(day=1), end_date=TODAY,
                        kind="sick", status="approved"))
    db.commit()
    db.close()
    row = client.get("/admin/attendance/percentage", headers=login("boss")).json()[0]
    assert row["working_days"] == 0 and row["leave_days"] >= 0


# ── Settings ─────────────────────────────────────────────────────────────────

def _settings(**kw):
    base = {"company_name": "Smart Attendance Kiosk", "work_start": "09:00", "work_end": "18:00", "grace_minutes": 15,
            "half_day_hours": 4, "weekend_days": [5, 6], "min_checkout_minutes": 5,
            "hr_emails": ["hr@example.com"], "email_enabled": True, "email_time": "19:00"}
    base.update(kw)
    return base


def test_settings_roundtrip_and_audit(client, make_employee, login):
    make_employee("boss", role="admin")
    h = login("boss")
    assert client.get("/admin/settings", headers=h).json()["work_start"] == "09:00"
    res = client.put("/admin/settings", headers=h, json=_settings(work_start="09:30", grace_minutes=10))
    assert res.status_code == 200 and res.json()["work_start"] == "09:30"
    assert client.get("/admin/audit", headers=h).json()[0]["action"] == "settings.updated"


@pytest.mark.parametrize("bad", [
    {"work_start": "18:00", "work_end": "09:00"},
    {"work_start": "9am"},
    {"hr_emails": ["not-an-email"]},
    {"weekend_days": [7]},
])
def test_bad_settings_rejected(client, make_employee, login, bad):
    make_employee("boss", role="admin")
    assert client.put("/admin/settings", headers=login("boss"), json=_settings(**bad)).status_code == 422


# ── Analytics ────────────────────────────────────────────────────────────────

def test_analytics_shape(client, make_employee, login, db_session):
    make_employee("boss", role="admin")
    a, b = make_employee("arun", category="Developer"), make_employee("priya", category="HR")
    # The last working day: weekends don't count towards punctuality, and tests also run on Sundays
    day = TODAY
    while day.weekday() >= 5:
        day -= timedelta(days=1)
    _log(db_session, a.id, day, "09:05", None)
    _log(db_session, b.id, day, "09:45", None)
    data = client.get("/admin/analytics?days=7", headers=login("boss")).json()
    assert len(data["daily"]) == 7
    that_day = next(d for d in data["daily"] if d["date"] == day.isoformat())
    assert that_day["present"] == 2 and that_day["late"] == 1
    assert {t["team"] for t in data["teams"]} == {"Developer", "HR"}
    assert data["punctuality"][0]["name"] == "Arun"  # on time beats late


# ── Background jobs ──────────────────────────────────────────────────────────

def test_auto_checkout_closes_yesterday_only(db_session, make_employee):
    emp = make_employee("arun")
    old = _log(db_session, emp.id, TODAY - timedelta(days=1), "09:10")
    now = _log(db_session, make_employee("priya").id, TODAY, "09:10")
    db = db_session()
    assert scheduler.auto_checkout(db) == 1
    closed, still_open = db.get(AttendanceLog, old.id), db.get(AttendanceLog, now.id)
    assert closed.auto_checkout and closed.out_time.strftime("%H:%M") == "18:00"
    assert still_open.out_time is None
    assert db.query(AuditLog).one().action == "attendance.auto_checkout"
    db.close()


def test_daily_email_sends_once_after_time(db_session, make_employee, monkeypatch, tmp_path):
    make_employee("arun")
    monkeypatch.setattr(email_service, "OUTBOX", str(tmp_path))
    monkeypatch.delenv("SMTP_USER", raising=False)
    db = db_session()
    settings_service.put(db, "email_enabled", True)
    settings_service.put(db, "hr_emails", ["hr@example.com"])
    db.commit()
    before = datetime.combine(TODAY, datetime.strptime("18:59", "%H:%M").time())
    after = before + timedelta(minutes=2)
    assert scheduler.maybe_send_daily_email(db, before) is None
    result = scheduler.maybe_send_daily_email(db, after)
    assert result and "Saved to" in result  # no SMTP in tests → written to a file
    assert scheduler.maybe_send_daily_email(db, after + timedelta(hours=1)) is None  # once a day
    html = (tmp_path / f"{TODAY.isoformat()}.html").read_text(encoding="utf-8")
    assert "Arun" in html and "Absent" in html
    db.close()
