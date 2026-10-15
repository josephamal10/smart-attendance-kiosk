"""
Run the API against the demo database (see seed_demo.py) on port 8001, with CORS open
for the Flutter web build served on port 5180. For UI previews and screenshots only.

    python scripts/seed_demo.py
    python scripts/run_demo.py
"""
import os
import sys

import uvicorn

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, ROOT)
os.environ["DATABASE_URL"] = "sqlite:///./demo.db"
os.environ.setdefault("CORS_ORIGINS", "http://localhost:5180,http://127.0.0.1:5180")

if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8001)
