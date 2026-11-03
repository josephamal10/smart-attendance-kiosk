---
title: Smart Attendance Kiosk
emoji: 🪪
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
short_description: Face-recognition attendance kiosk — live demo
---

# Smart Attendance Kiosk — live demo

A face-recognition attendance system: a walk-up kiosk (face match, blink liveness, anti-spoofing),
an admin dashboard and every employee's own dashboard. This demo runs the web dashboard with a
made-up company; the sign-in page lists the demo accounts.

| To see | Username | Password |
|---|---|---|
| Admin dashboard (full access) | `demo-admin` | `demo-pass-2026` |
| Admin dashboard (read-only HR) | `hr-viewer` | `demo-pass-2026` |
| An employee's own dashboard | click a name under *Employee dashboards* | — |

The data resets every few hours. Face check-in itself needs the Windows kiosk app and a camera —
see the code and screenshots on GitHub:
**https://github.com/josephamal10/smart-attendance-kiosk**
