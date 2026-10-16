import asyncio
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from database import init_db
from routes import (admin_routes, admins_routes, auth_routes, face_routes, insights_routes, kiosk_routes,
                    me_routes, notices_routes, requests_routes, settings_routes)
from services import antispoof_service, scheduler
from services.face_engine import get_engine

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

init_db()
# Load models at startup so a missing file fails now, not at the first check-in
get_engine()
if antispoof_service.is_enabled():
    antispoof_service.get_model()

@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Auto check-out + daily HR email. Tests set DISABLE_SCHEDULER so they never touch real data.
    task = None if os.getenv("DISABLE_SCHEDULER") else asyncio.create_task(scheduler.run_forever())
    yield
    if task:
        task.cancel()


app = FastAPI(
    title="NanoNino Attendance System API",
    description="Face recognition based automated attendance system",
    version="1.2.0",
    lifespan=lifespan,
)

# The Flutter desktop app isn't a browser, so it doesn't need CORS.
# Only enable it for a web frontend, listing its exact origins in CORS_ORIGINS.
_origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "").split(",") if o.strip()]
if _origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

# Register routers
app.include_router(auth_routes.router)
app.include_router(face_routes.router)
app.include_router(kiosk_routes.router)
app.include_router(admin_routes.router)
app.include_router(admins_routes.router)
app.include_router(requests_routes.router)
app.include_router(insights_routes.router)
app.include_router(settings_routes.router)
app.include_router(me_routes.router)
app.include_router(me_routes.public_router)
app.include_router(notices_routes.router)
app.include_router(notices_routes.public_router)

# The admin dashboard for HR's own computers: the Flutter web build, served from this same
# server so it needs no CORS and no separate hosting. Build it with scripts/build_web.bat.
WEB_ADMIN_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "technerdz_app", "build", "web_admin")
if os.path.isfile(os.path.join(WEB_ADMIN_DIR, "index.html")):
    app.mount("/app", StaticFiles(directory=WEB_ADMIN_DIR, html=True), name="web-admin")


@app.get("/")
def root():
    return {"message": "NanoNino Attendance API is running",
            "web_dashboard": "/app/" if any(getattr(r, "name", "") == "web-admin" for r in app.routes) else None}
