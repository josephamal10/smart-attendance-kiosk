# TECHNERDZ — Face Recognition Attendance Kiosk

A desktop kiosk where employees check in and out by looking at a camera.
**FastAPI** backend + **Flutter (Windows)** frontend, with face recognition (dlib),
a server-enforced blink liveness check (MediaPipe Face Landmarker) and an admin dashboard.

```
 Flutter kiosk                         FastAPI server
 ┌───────────────┐   password login    ┌──────────────────────────────┐
 │ Lock screen   │ ──────────────────▶ │ /auth   JWT, bcrypt, lockout  │
 │ Face verify   │   camera frames     │ /attendance/liveness          │
 │   (blink)     │ ──────────────────▶ │   EAR blink → 60s one-time    │
 │               │   photo + token     │   liveness token              │
 │               │ ──────────────────▶ │ /attendance/verify            │
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
4. `/attendance/verify` refuses without that token, then compares the photo's 128-d face
   embedding against only that employee's 30 registered images (straight / left / right).
5. First scan of the day = IN; a scan at least `MIN_CHECKOUT_MINUTES` later = OUT.

## Run it

**Backend** (Python 3.11):
```bash
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements-dev.txt
copy .env.example .env          # then set SECRET_KEY
python scripts/create_admin.py --username admin --name "Admin"
uvicorn main:app --reload       # API docs at http://127.0.0.1:8000/docs
pytest                          # 28 tests, no camera needed
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
- **Known limitation:** blink liveness defeats printed photos but not a replayed video.
  A trained anti-spoofing model is the planned next step.

## Privacy
`face_images/`, the database and `.env` are git-ignored — they contain biometric data and secrets.
