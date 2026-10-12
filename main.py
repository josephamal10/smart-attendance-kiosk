import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from database import init_db
from routes import auth_routes, face_routes, attendance_routes, admin_routes
from services import antispoof_service

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

init_db()
if antispoof_service.is_enabled():
    antispoof_service.get_model()  # fail at startup, not at the first check-in, if models are missing

app = FastAPI(
    title="TECHNERDZ Attendance System API",
    description="Face recognition based automated attendance system",
    version="1.1.0"
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
app.include_router(attendance_routes.router)
app.include_router(admin_routes.router)

@app.get("/")
def root():
    return {"message": "TECHNERDZ Attendance API is running 🚀"}
