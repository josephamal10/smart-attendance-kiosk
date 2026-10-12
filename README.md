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
1. Employee picks their name and enters their password → access token.
2. The app streams frames to `/attendance/liveness`. The server computes the
   **Eye Aspect Ratio** from 478 face landmarks and waits for open → closed eyes.
3. On a blink the server issues a **single-use liveness token** (60s, bound to that employee).
4. `/attendance/verify` refuses without that token, runs the **anti-spoofing model**
   (is this a live face, or a print / phone / monitor?), then compares the photo's 128-d SFace
   embedding (cosine similarity) against only that employee's 30 registered images.
5. First scan of the day = IN; a scan at least `MIN_CHECKOUT_MINUTES` later = OUT.

## Run it

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
pytest                          # 44 tests, no camera needed
```

**App** (Flutter, Windows desktop):
```bash
cd technerdz_app
flutter pub get
flutter run -d windows                                     # local server
flutter run -d windows --dart-define=API_URL=http://<server-ip>:8000
```

## Security notes
- Every route except login and the kiosk name list requires a JWT; `/admin/*` requires the admin role.
- Users can only register / delete / read their *own* faces and attendance.
- Only admins can create accounts; roles are validated server-side.
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
