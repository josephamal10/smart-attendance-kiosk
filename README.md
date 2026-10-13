# TECHNERDZ — Face Recognition Attendance Kiosk

A desktop kiosk where employees check in and out by looking at a camera.
**FastAPI** backend + **Flutter (Windows)** frontend, with face recognition
(YuNet + SFace, ONNX via OpenCV), a server-enforced blink liveness check (MediaPipe Face Landmarker), a **face
anti-spoofing CNN served with ONNX Runtime** ([ml/antispoof](ml/antispoof/README.md))
and an admin dashboard.

```
 Flutter kiosk                         FastAPI server
 ┌───────────────┐   password login    ┌──────────────────────────────┐
 │ Lock screen   │ ──────────────────▶ │ /auth   JWT, bcrypt, lockout  │
 │ Face verify   │   camera frames     │ /attendance/liveness          │
 │   (blink)     │ ──────────────────▶ │   EAR blink → 60s one-time    │
 │               │   photo + token     │   liveness token              │
 │               │ ──────────────────▶ │ /attendance/verify            │
 │               │                     │   anti-spoof CNN (ONNX)       │
 │ Admin panel   │                     │   1:1 face match → IN / OUT   │
 └───────────────┘                     │ /admin  (admin role only)     │
                                       └──────────────┬───────────────┘
                                          SQLite / MySQL + face_images/
```

## How a check-in works
Employees have **no username or password** — they walk up, look at the camera and blink.
1. The kiosk streams frames to `/kiosk/liveness` under a random per-scan session id. The server
   computes the **Eye Aspect Ratio** from 478 face landmarks and waits for open → closed eyes.
2. On a blink it issues a **single-use liveness token** (60 s, bound to that scan session).
3. `/kiosk/check-in` refuses without that token, runs the **anti-spoofing model**
   (live face, or a print / phone / monitor?), then **identifies** the person: their 128-d SFace
   embedding is compared with every active employee's ~30 registered photos. The best match must
   clear the threshold *and* beat the runner-up by a margin, so look-alikes are refused, not guessed.
4. First scan of the day = IN; a scan at least `MIN_CHECKOUT_MINUTES` later = OUT.

Employees belong to a team: **HR, Project Manager, Admin, Developer, Tester**. "Admin" is a job
title; dashboard access comes only from an admin account (small icon on the kiosk → username +
password, any password you like, changeable in the dashboard; signs out after 5 idle minutes).

## Run it

**Quickest (Windows, after setup):** double-click `run.bat`. It starts the server in its own
window, waits until it's ready, then opens the kiosk app. Close the server window to stop it.

**Backend with Docker** (any OS):
```bash
copy .env.example .env          # then set SECRET_KEY
docker compose up --build       # API on http://localhost:8000, data kept in ./docker-data
docker compose exec api python scripts/create_admin.py --username admin
```

**Backend without Docker** (Python 3.11):
```bash
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements-dev.txt
copy .env.example .env          # then set SECRET_KEY
python scripts/create_admin.py --username admin --name "Admin"
uvicorn main:app --reload       # API docs at http://127.0.0.1:8000/docs
pytest                          # 58 tests, no camera needed
```

**App** (Flutter, Windows desktop):
```bash
cd technerdz_app
flutter pub get
flutter run -d windows                                     # local server
flutter run -d windows --dart-define=API_URL=http://<server-ip>:8000
```

## Security notes
- Only the two kiosk endpoints are open, and both are gated by liveness + anti-spoofing; everything
  else needs an admin JWT. There is no public list of employee names.
- Employees have no password at all (`!` placeholder that can never match), so their accounts
  can't be used to sign in.
- Login lockout is per (username, IP) so one machine can't lock someone out everywhere.
- Blink liveness stops printed photos; the anti-spoofing CNN (MiniFASNet, ~7 ms) targets
  phone/screen replays. Its attack-detection rate still needs measuring on real attack
  recordings — see [ml/antispoof/README.md](ml/antispoof/README.md).

## Privacy
`face_images/`, the database and `.env` are git-ignored — they contain biometric data and secrets.

## Benchmarks
Face verification on LFW (6,000 pairs, standard 10-fold protocol), `python ml/face_benchmark.py`:
see [reports/face_benchmark.json](reports/face_benchmark.json) and the table in
[ml/README.md](ml/README.md).
