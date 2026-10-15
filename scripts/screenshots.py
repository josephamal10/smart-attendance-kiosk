"""
Regenerate docs/screenshots/*.png from demo data (Windows, needs Flutter + Microsoft Edge).

    python scripts/screenshots.py            # build + capture everything
    python scripts/screenshots.py --no-build # reuse the last screenshot build

Uses only the demo database (scripts/seed_demo.py) — never real employees or faces.
"""
import argparse
import http.server
import os
import socketserver
import subprocess
import sys
import threading
import time
import urllib.request
from datetime import timedelta
from functools import partial

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "technerdz_app")
OUT_WEB = os.path.join(APP, "build", "screens")
OUT_PNG = os.path.join(ROOT, "docs", "screenshots")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
FLUTTER = os.environ.get("FLUTTER", r"C:\flutter\flutter\bin\flutter.bat")
WEB_PORT, API_PORT = 5181, 8001

SHOTS = {
    "kiosk":            "screen=kiosk",
    "admin-login":      "screen=login",
    "overview":         "screen=dashboard&page=overview",
    "register":         "screen=dashboard&page=attendance:register",
    "analytics":        "screen=dashboard&page=analytics",
    "analytics-dark":   "screen=dashboard&page=analytics&dark=1",
    "requests":         "screen=dashboard&page=requests",
    "employees":        "screen=dashboard&page=employees",
    "profile":          "screen=profile&id={priya}",
    "my-attendance":    "screen=me",
    "settings-dark":    "screen=dashboard&page=settings&dark=1",
}


def tokens() -> tuple[str, str, int]:
    os.environ["DATABASE_URL"] = "sqlite:///./demo.db"
    sys.path.insert(0, ROOT)
    from auth import create_access_token
    import sqlite3
    con = sqlite3.connect(os.path.join(ROOT, "demo.db"))
    admin = con.execute("select id from employees where username='demo-admin'").fetchone()[0]
    priya = con.execute("select id from employees where name='Priya Raman'").fetchone()[0]
    ttl = timedelta(hours=2)
    return (create_access_token({"sub": str(admin), "role": "admin", "type": "access"}, expires=ttl),
            create_access_token({"sub": str(priya), "type": "self"}, expires=ttl), priya)


def wait_for(url: str, seconds: int = 90) -> None:
    for _ in range(seconds):
        try:
            urllib.request.urlopen(url, timeout=2)
            return
        except Exception:
            time.sleep(1)
    raise RuntimeError(f"{url} did not come up")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-build", action="store_true")
    ap.add_argument("--only", nargs="*", help="names from SHOTS")
    args = ap.parse_args()
    os.chdir(ROOT)

    subprocess.run([sys.executable, "scripts/seed_demo.py"], check=True)
    admin_token, self_token, priya = tokens()

    if not args.no_build:
        subprocess.run([FLUTTER, "build", "web", "-t", "lib/dev/screenshots.dart", "-o", OUT_WEB,
                        "--no-web-resources-cdn", "--no-wasm-dry-run",
                        f"--dart-define=API_URL=http://127.0.0.1:{API_PORT}",
                        f"--dart-define=DEMO_TOKEN={admin_token}", f"--dart-define=SELF_TOKEN={self_token}"],
                       cwd=APP, check=True)

    env = dict(os.environ, CORS_ORIGINS=f"http://localhost:{WEB_PORT},http://127.0.0.1:{WEB_PORT}")
    api = subprocess.Popen([sys.executable, "scripts/run_demo.py"], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    handler = partial(http.server.SimpleHTTPRequestHandler, directory=OUT_WEB)
    handler.log_message = lambda *a, **k: None
    web = socketserver.ThreadingTCPServer(("127.0.0.1", WEB_PORT), handler)
    threading.Thread(target=web.serve_forever, daemon=True).start()
    try:
        wait_for(f"http://127.0.0.1:{API_PORT}/")
        os.makedirs(OUT_PNG, exist_ok=True)
        for name, query in SHOTS.items():
            if args.only and name not in args.only:
                continue
            url = f"http://localhost:{WEB_PORT}/?{query.format(priya=priya)}"
            out = os.path.join(OUT_PNG, f"{name}.png")
            subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                            "--window-size=1440,900", "--force-device-scale-factor=1.5",
                            "--virtual-time-budget=60000", "--run-all-compositor-stages-before-draw", f"--screenshot={out}", url],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
            print(f"  {name}.png")
    finally:
        api.terminate()
        web.shutdown()


if __name__ == "__main__":
    main()
