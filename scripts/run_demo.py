"""
Run the API against the demo database (see seed_demo.py) on port 8001, in demo mode:
the sign-in screen shows the demo accounts and lets visitors open any employee's dashboard
without a face scan. The demo data is made fresh on every start.

    python scripts/run_demo.py        then open http://127.0.0.1:8001/app/
"""
import os
import sys

import uvicorn

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, ROOT)
os.environ["DATABASE_URL"] = "sqlite:///./demo.db"
os.environ["DEMO_MODE"] = "1"   # only ever honoured with a demo database (services/demo.py)
os.environ.setdefault("CORS_ORIGINS", "http://localhost:5180,http://127.0.0.1:5180")
# Demo data needs no auto check-outs, emails or backups (backups would mix with the real ones)
os.environ["DISABLE_SCHEDULER"] = "1"

if __name__ == "__main__":
    # Fresh made-up data on every start, so changes visitors made last time are gone
    # (the screenshot tool seeds it itself and sets DEMO_FRESH=1)
    if not os.getenv("DEMO_FRESH"):
        import subprocess
        subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "seed_demo.py")], check=True)
    print("Demo running: open http://127.0.0.1:8001/app/  (close this window to stop it)")
    uvicorn.run("main:app", host="127.0.0.1", port=8001)
