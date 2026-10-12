# Backend API image. Works the same on Windows, macOS and Linux hosts.
#   docker compose up --build
FROM python:3.11-slim

# OpenCV/MediaPipe need these shared libraries even without a display
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
# Bake the face models into the image (downloads YuNet/SFace + checks their hashes)
RUN SECRET_KEY=build python -c "from services.face_engine import get_engine; get_engine()" \
    && python -c "from services.face_service import _get_landmarker; _get_landmarker()"

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
