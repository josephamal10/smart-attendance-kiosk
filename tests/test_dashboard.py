"""Employee dashboard: streaks, badges, leave balance, notices, team, report PDF."""
from datetime import date, datetime, timedelta

from auth import create_access_token
from models import AttendanceLog, Employee, Holiday, LeaveRequest
from services import me_service

TODAY = date.today()


def _me(emp):
    return {"Authorization": "Bearer " + create_access_token({"sub": str(emp.id), "type": "self"})}


def _add(db_session, *objs):
    db = db_session()
    for o in objs:
        db.add(o)
    db.commit()
    db.close()


def _log(emp_id, day, t_in, t_out="18:00"):
    at = lambda t: datetime.combine(day, datetime.strptime(t, "%H:%M").time())  # noqa: E731
    return AttendanceLog(employee_id=emp_id, date=day.isoformat(), status="present",
                         in_time=at(t_in), out_time=at(t_out) if t_out else None)


def _joined(db_session, emp, when):
    db = db_session()
    db.query(Employee).filter(Employee.id == emp.id).update({"created_at": when})
    db.commit()
    db.close()


def _october(db_session, make_employee):
    """Mon 5 Oct late, 6–9 on time, Mon 12 on leave, 13–16 on time (2026)."""
    emp = make_employee("arun")
    _joined(db_session, emp, datetime(2026, 10, 5))
    logs = [_log(emp.id, date(2026, 10, 5), "09:40")]
    logs += [_log(emp.id, date(2026, 10, d), "08:45") for d in (6, 7, 8, 9, 13, 14, 15, 16)]
    _add(db_session, *logs, LeaveRequest(employee_id=emp.id, start_date=date(2026, 10, 12),
                                         end_date=date(2026, 10, 12), kind="casual", status="approved"))
    return emp


def _history(db_session, emp, today):
    db = db_session()
    h = me_service.History(db, db.get(Employee, emp.id), today)
    db.close()
    return h


def test_streak_survives_leave_but_not_a_late_day(db_session, make_employee):
    emp = _october(db_session, make_employee)
    assert me_service.streaks(_history(db_session, emp, date(2026, 10, 16))) == {"current": 8, "best": 8}


def test_today_without_a_scan_yet_does_not_break_the_streak(db_session, make_employee):
    emp = _october(db_session, make_employee)
    assert me_service.streaks(_history(db_session, emp, date(2026, 10, 19)))["current"] == 8


def test_an_absence_resets_the_streak(db_session, make_employee):
    emp = _october(db_session, make_employee)
    s = me_service.streaks(_history(db_session, emp, date(2026, 10, 20)))  # nothing on Mon 19
    assert s == {"current": 0, "best": 8}


def test_badges(db_session, make_employee):
    emp = _october(db_session, make_employee)
    h = _history(db_session, emp, date(2026, 10, 19))
    got = {b["key"]: b for b in me_service.badges(h, me_service.streaks(h))}
    assert got["on_a_roll"]["earned"]
    assert got["perfect_week"]["earned"]          # 12–16 Oct: leave + four on-time days
    assert got["early_bird"]["earned"]            # 08:45 is 15 min early, 8 times this month
    assert got["clean_exits"]["earned"]
    assert not got["extra_mile"]["earned"]
    h = _history(db_session, emp, date(2026, 10, 16))
    assert not {b["key"]: b for b in me_service.badges(h, me_service.streaks(h))}["perfect_week"]["earned"]


def test_weekly_hours_compare_worked_with_expected(db_session, make_employee):
    emp = _october(db_session, make_employee)
    weeks = me_service.weekly_hours(_history(db_session, emp, date(2026, 10, 16)), weeks=2)
    assert [w["week_start"] for w in weeks] == ["2026-10-05", "2026-10-12"]
    assert weeks[1]["expected"] == 36.0   # 4 working days (Mon was leave) x 9 h
    assert weeks[1]["hours"] == 37.0      # 4 x 9h15m


def test_leave_balance_counts_working_days_only(db_session, make_employee):
    emp = make_employee("arun")
    _add(db_session,
         Holiday(date=date(2026, 3, 3), name="Spring day"),
         LeaveRequest(employee_id=emp.id, start_date=date(2026, 3, 2), end_date=date(2026, 3, 8),
                      kind="casual", status="approved"),   # Mon–Sun with a holiday: 4 working days
         LeaveRequest(employee_id=emp.id, start_date=date(2026, 3, 9), end_date=date(2026, 3, 9),
                      kind="sick", status="pending"),
         LeaveRequest(employee_id=emp.id, start_date=date(2026, 3, 10), end_date=date(2026, 3, 10),
                      kind="sick", status="rejected"))
    db = db_session()
    bal = {b["kind"]: b for b in me_service.leave_balance(db, db.get(Employee, emp.id), 2026)}
    db.close()
    assert bal["casual"] == {"kind": "casual", "label": "Casual", "allowance": 12, "used": 4,
                             "pending": 0, "remaining": 8}
    assert bal["sick"]["used"] == 0 and bal["sick"]["pending"] == 1
    assert "other" not in bal   # no allowance and never used


def test_dashboard_has_everything(client, make_employee, login, db_session):
    make_employee("boss", role="admin")
    arun = make_employee("arun", category="Tester")
    mira = make_employee("mira", category="Tester")
    make_employee("dev", category="Developer")
    _add(db_session,
         LeaveRequest(employee_id=mira.id, start_date=TODAY, end_date=TODAY, kind="sick", status="approved"),
         Holiday(date=TODAY + timedelta(days=10), name="Founders day"))
    client.post("/admin/notices", headers=login("boss"), json={"title": "Fire drill Friday", "pinned": True})
    client.post("/me/leave", headers=_me(arun), json={"start_date": TODAY.isoformat(),
                                                       "end_date": TODAY.isoformat(), "kind": "casual"})

    d = client.get("/me", headers=_me(arun)).json()
    assert len(d["calendar"]["row"]["cells"]) == len(d["calendar"]["days"])
    assert len(d["weekly_hours"]) == 8
    assert len(d["badges"]) == 6 and set(d["streak"]) == {"current", "best"}
    assert d["leave_balance"][0]["kind"] == "casual" and d["leave_balance"][0]["pending"] >= 0
    assert d["updates"][0]["type"] == "leave" and d["updates"][0]["status"] == "pending"
    assert d["notices"][0]["title"] == "Fire drill Friday"
    assert d["team"]["name"] == "Tester" and d["team"]["members"] == 2
    assert d["team"]["on_leave_today"] == ["Mira"]
    assert d["team"]["upcoming_holidays"][0] == {"date": (TODAY + timedelta(days=10)).isoformat(),
                                                 "name": "Founders day", "in_days": 10}
    assert "overtime_hours" in d["month"]


def test_dashboard_calendar_can_show_another_month(client, make_employee):
    arun = make_employee("arun")
    d = client.get("/me?year=2026&month=2", headers=_me(arun)).json()
    assert d["calendar"]["month_name"] == "February 2026" and len(d["calendar"]["days"]) == 28


def test_notices_permissions_and_expiry(client, make_employee, login):
    make_employee("boss", role="admin")
    make_employee("hr", role="viewer")
    boss, hr = login("boss"), login("hr")
    assert client.post("/admin/notices", headers=hr, json={"title": "x"}).status_code == 403
    n = client.post("/admin/notices", headers=boss, json={"title": "Team lunch", "body": "1 PM"}).json()
    client.post("/admin/notices", headers=boss,
                json={"title": "Old news", "expires_on": (TODAY - timedelta(days=1)).isoformat()})
    assert [x["title"] for x in client.get("/notices").json()] == ["Team lunch"]   # public, no sign-in
    assert len(client.get("/admin/notices", headers=hr).json()) == 2              # admins see expired too
    edited = client.put(f"/admin/notices/{n['id']}", headers=boss,
                        json={"title": "Team lunch moved", "body": "2 PM", "pinned": True}).json()
    assert edited["pinned"] and edited["created_by"] == "Boss"
    assert client.delete(f"/admin/notices/{n['id']}", headers=hr).status_code == 403
    assert client.delete(f"/admin/notices/{n['id']}", headers=boss).status_code == 200
    actions = [a["action"] for a in client.get("/admin/audit", headers=boss).json()]
    assert {"notice.posted", "notice.edited", "notice.removed"} <= set(actions)


def test_my_report_pdf_and_phone_link(client, make_employee, login, db_session):
    make_employee("boss", role="admin")
    arun = make_employee("arun")
    _add(db_session, _log(arun.id, TODAY, "09:00", None))
    res = client.get("/me/report.pdf", headers=_me(arun))
    assert res.status_code == 200 and res.headers["content-type"] == "application/pdf"
    assert res.content.startswith(b"%PDF")

    link = client.post("/me/report-link", headers=_me(arun)).json()
    assert "/r/" in link["url"] and link["expires_in_minutes"] == 10
    token = link["url"].rsplit("/r/", 1)[1]
    assert client.get(f"/r/{token}").content.startswith(b"%PDF")   # no sign-in needed: the link is the key
    # ...but that link is only for the report
    assert client.get("/me", headers={"Authorization": f"Bearer {token}"}).status_code == 401
    assert client.get("/admin/employees", headers={"Authorization": f"Bearer {token}"}).status_code == 401
    # and other tokens don't open reports
    assert client.get("/r/" + _me(arun)["Authorization"][7:]).status_code == 404
    assert client.get("/r/not-a-token").status_code == 404


def test_web_dashboard_is_served_when_built(client):
    import os
    import pytest
    import main
    if not os.path.isfile(os.path.join(main.WEB_ADMIN_DIR, "index.html")):
        pytest.skip("web dashboard not built (scripts/build_web.bat)")
    page = client.get("/app/")
    assert page.status_code == 200 and '<base href="/app/">' in page.text
    assert client.get("/").json()["web_dashboard"] == "/app/"


def test_todays_shift_is_only_expected_once_the_day_is_done(db_session, make_employee):
    emp = _october(db_session, make_employee)
    _add(db_session, _log(emp.id, date(2026, 10, 19), "08:50", None))   # Monday, still at work
    week = me_service.weekly_hours(_history(db_session, emp, date(2026, 10, 19)), weeks=1)[0]
    assert week["expected"] == 0.0


def test_report_link_from_the_kiosk_points_phones_at_https(client, make_employee, monkeypatch):
    from routes import me_routes
    arun = make_employee("arun")
    monkeypatch.setattr(me_routes, "_lan_ip", lambda: "192.168.1.50")
    monkeypatch.setenv("HTTPS_PORT", "8443")
    client.base_url = "http://127.0.0.1:8000"   # the kiosk app talks to the local server
    url = client.post("/me/report-link", headers=_me(arun)).json()["url"]
    assert url.startswith("https://192.168.1.50:8443/r/")
