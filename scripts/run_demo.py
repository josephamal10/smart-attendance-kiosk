"""
Run the API against the demo database (see seed_demo.py) on port 8001, in demo mode:
the sign-in screen shows the demo accounts and lets visitors open any employee's dashboard
without a face scan. The demo data is made fresh on every start.

    python scripts/run_demo.py        then open http://127.0.0.1:8001/app/
"""
import argparse
import os
import secrets
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
# Demo sign-ins only need to last while it runs; a fresh secret each start is fine
os.environ.setdefault("SECRET_KEY", secrets.token_urlsafe(32))

if __name__ == "__main__":
    # Fresh made-up data on every start, so changes visitors made last time are gone
    # (the screenshot tool seeds it itself and sets DEMO_FRESH=1)
    if not os.getenv("DEMO_FRESH"):
        import subprocess
        subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "seed_demo.py")], check=True)
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8001)
    ap.add_argument("--behind-proxy", action="store_true",
                    help="hosted (e.g. Hugging Face Spaces): trust the proxy's https/host headers")
    args = ap.parse_args()
    print(f"Demo running: open http://127.0.0.1:{args.port}/app/  (close this window to stop it)")
    uvicorn.run("main:app", host=args.host, port=args.port,
                proxy_headers=args.behind_proxy, forwarded_allow_ips="*" if args.behind_proxy else None)
