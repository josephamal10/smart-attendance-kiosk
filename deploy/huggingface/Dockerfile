# Live demo on Hugging Face Spaces (Docker Space). The Space only holds this file and README.md:
# the build downloads the project from GitHub, builds the Flutter web dashboard, and starts the
# API in demo mode (made-up data, demo accounts on the sign-in page, fresh data every few hours).
# "Factory rebuild" in the Space settings picks up the latest code from GitHub.
ARG REPO=https://github.com/josephamal10/smart-attendance-kiosk.git
ARG REF=main

# ── 1. Build the web dashboard with the same Flutter version as the project ──
FROM debian:bookworm-slim AS web
ARG REPO
ARG REF
ARG FLUTTER_VERSION=3.47.7
RUN apt-get update && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /flutter
ENV PATH="/flutter/bin:${PATH}"
RUN git clone --depth 1 --branch ${REF} ${REPO} /src
WORKDIR /src/technerdz_app
RUN flutter config --no-analytics --no-cli-animations \
    && flutter pub get \
    && flutter build web --release --base-href /app/ -o /web --no-web-resources-cdn --no-wasm-dry-run

# ── 2. The API, serving that dashboard at /app/ ──
FROM python:3.11-slim
# OpenCV/MediaPipe need these shared libraries (OpenGL ES / EGL too) even without a display
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 libgles2 libegl1 \
    && rm -rf /var/lib/apt/lists/*
# Spaces run the app as user 1000, which must be able to write the demo database
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user PATH=/home/user/.local/bin:$PATH PYTHONUNBUFFERED=1
WORKDIR /home/user/app
COPY --from=web --chown=user /src/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt
COPY --from=web --chown=user /src .
COPY --from=web --chown=user /web technerdz_app/build/web_admin
# Download the face models now, not when the first visitor arrives
RUN SECRET_KEY=build python -c "from services.face_engine import get_engine; get_engine()" \
    && SECRET_KEY=build python -c "from services.face_service import _get_landmarker; _get_landmarker()"

# Swap in fresh demo data every 3 hours, so whatever visitors change doesn't stay for long
ENV DEMO_RESET_HOURS=3
EXPOSE 7860
CMD ["python", "scripts/run_demo.py", "--host", "0.0.0.0", "--port", "7860", "--behind-proxy"]
