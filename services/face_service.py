import json
import logging
import os
import threading
import uuid

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python.vision import FaceLandmarker, FaceLandmarkerOptions
from mediapipe.tasks.python.vision.core.vision_task_running_mode import VisionTaskRunningMode
from sqlalchemy.orm import Session

from models import FaceImage, Employee
from services import antispoof_service
from services.face_engine import cosine_similarity, get_engine

log = logging.getLogger("technerdz.face")

FACE_IMAGE_DIR = "face_images"
os.makedirs(FACE_IMAGE_DIR, exist_ok=True)

# SFace cosine similarity needed to accept a match (higher = stricter). On LFW, 0.45 let
# 0 of 3,000 impostor pairs through (highest impostor scored 0.412) while accepting 95% of
# genuine pairs, which span years and lighting changes. A kiosk compares same-camera photos and
# takes the best of ~30 registered images, so genuine scores run much higher. Erring strict
# also offsets the extra impostor chances that best-of-30 gives. See ml/README.md.
MATCH_THRESHOLD = float(os.getenv("FACE_MATCH_THRESHOLD", 0.45))

# Eye landmark indices (MediaPipe 478 landmarks)
LEFT_EYE  = [362, 385, 387, 263, 373, 380]
RIGHT_EYE = [33,  160, 158, 133, 153, 144]

_MODEL_PATH = "face_landmarker.task"
_MODEL_URL  = ("https://storage.googleapis.com/mediapipe-models/face_landmarker/"
               "face_landmarker/float16/1/face_landmarker.task")

# Building a FaceLandmarker loads the model from disk, so do it once and reuse it.
# detect() isn't documented as thread-safe, and FastAPI runs sync endpoints in a thread pool.
_landmarker: FaceLandmarker | None = None
_load_lock   = threading.Lock()
_detect_lock = threading.Lock()


def _get_landmarker() -> FaceLandmarker:
    global _landmarker
    with _load_lock:
        if _landmarker is None:
            if not os.path.exists(_MODEL_PATH):
                import urllib.request
                print("Downloading face landmarker model...")
                urllib.request.urlretrieve(_MODEL_URL, _MODEL_PATH)
            options = FaceLandmarkerOptions(
                base_options=mp_python.BaseOptions(model_asset_path=_MODEL_PATH),
                running_mode=VisionTaskRunningMode.IMAGE,
                num_faces=2,  # 2 so we can reject frames with more than one person
            )
            _landmarker = FaceLandmarker.create_from_options(options)
        return _landmarker


def _ear(landmarks, eye_indices, width: int, height: int) -> float:
    """Eye Aspect Ratio. Landmarks are normalised to 0-1 per axis, so scale back to
    pixels first — otherwise non-square frames distort the ratio."""
    pts = np.array([[landmarks[i].x * width, landmarks[i].y * height] for i in eye_indices])
    A = np.linalg.norm(pts[1] - pts[5])
    B = np.linalg.norm(pts[2] - pts[4])
    C = np.linalg.norm(pts[0] - pts[3])
    return float((A + B) / (2.0 * C)) if C > 0 else 0.0


def _decode(image_bytes: bytes) -> np.ndarray | None:
    """Decode JPEG/PNG bytes into an RGB array."""
    img = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
    return None if img is None else cv2.cvtColor(img, cv2.COLOR_BGR2RGB)


# ── Eye openness (used by liveness) ───────────────────────────────────────────

def measure_ear(image_bytes: bytes) -> dict:
    """Return the average EAR for the single face in the frame."""
    rgb = _decode(image_bytes)
    if rgb is None:
        return {"ok": False, "ear": 0.0, "message": "Invalid image"}

    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    landmarker = _get_landmarker()
    with _detect_lock:
        result = landmarker.detect(mp_image)

    if not result.face_landmarks:
        return {"ok": False, "ear": 0.0, "message": "No face detected"}
    if len(result.face_landmarks) > 1:
        return {"ok": False, "ear": 0.0, "message": "Only one person should be in frame"}

    h, w = rgb.shape[:2]
    lm  = result.face_landmarks[0]
    avg = (_ear(lm, LEFT_EYE, w, h) + _ear(lm, RIGHT_EYE, w, h)) / 2.0
    return {"ok": True, "ear": round(avg, 4), "message": "OK"}



# ── Face embeddings ───────────────────────────────────────────────────────────

SPOOF_MESSAGE = "Live face not confirmed. Look at the camera directly — no photos or screens."


def _single_face_encoding(image_bytes: bytes, check_spoof: bool = True) -> tuple[np.ndarray | None, str]:
    """Embedding of the one face in the photo, or (None, reason).

    With check_spoof, the anti-spoofing model must also judge the face as a live person
    (not a print, phone or monitor) — otherwise anyone could register or check in with
    someone else's photo."""
    img = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        return None, "Invalid image"
    engine = get_engine()
    faces = engine.detect(img)
    if len(faces) == 0:
        return None, "No face detected. Please try again."
    if len(faces) > 1:
        return None, "More than one face detected. Only one person should be in frame."

    if check_spoof and antispoof_service.is_enabled():
        is_real, score = antispoof_service.check(img, faces[0].box)
        log.info("anti-spoof P(real)=%.3f -> %s", score, "real" if is_real else "SPOOF")
        if not is_real:
            return None, SPOOF_MESSAGE

    return engine.embed(img, faces[0]), "OK"


def save_face_image(db: Session, employee_id: int, direction: str,
                    image_bytes: bytes) -> dict:
    embedding, msg = _single_face_encoding(image_bytes)
    if embedding is None:
        return {"success": False, "message": msg}

    filename  = f"{employee_id}_{direction}_{uuid.uuid4().hex[:8]}.jpg"
    save_path = os.path.join(FACE_IMAGE_DIR, filename)
    with open(save_path, "wb") as f:
        f.write(image_bytes)

    face_img = FaceImage(
        employee_id = employee_id,
        image_path  = save_path,
        direction   = direction,
        embedding   = json.dumps(embedding.tolist()),
    )
    db.add(face_img)
    db.commit()
    db.refresh(face_img)

    return {
        "success": True,
        "message": "Face saved successfully.",
        "total": get_face_count_by_employee(db, employee_id),
        "image_id": face_img.id,
    }


def get_face_count_by_employee(db: Session, employee_id: int) -> int:
    return db.query(FaceImage).filter(FaceImage.employee_id == employee_id).count()


def verify_face(db: Session, image_bytes: bytes, employee_id: int,
                threshold: float = MATCH_THRESHOLD) -> tuple[Employee | None, str]:
    """1:1 check — does this photo match the stored faces of `employee_id`?"""
    rows = db.query(FaceImage).filter(FaceImage.employee_id == employee_id).all()
    if not rows:
        return None, "No faces registered yet. Ask admin to register your face first."

    probe, msg = _single_face_encoding(image_bytes)
    if probe is None:
        return None, msg

    known = np.array([json.loads(r.embedding) for r in rows])
    best = float(np.max(cosine_similarity(known, probe)))
    log.info("face match: best cosine %.3f (threshold %.2f)", best, threshold)
    if best >= threshold:
        return db.get(Employee, employee_id), "OK"
    return None, "Face not recognized. Please try again."
