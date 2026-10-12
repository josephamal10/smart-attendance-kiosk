from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from database import engine, Base
from routes import auth_routes, face_routes, attendance_routes, admin_routes

# Create all tables
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="TECHNERDZ Attendance System API",
    description="Face recognition based automated attendance system",
    version="1.0.0"
)

# Allow Flutter desktop app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
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
