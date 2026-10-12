import io
import json
import os
import threading
import uuid

import cv2
import face_recognition
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python.vision import FaceLandmarker, FaceLandmarkerOptions
from mediapipe.tasks.python.vision.core.vision_task_running_mode import VisionTaskRunningMode
from sqlalchemy.orm import Session

from models import FaceImage, Employee

FACE_IMAGE_DIR = "face_images"
os.makedirs(FACE_IMAGE_DIR, exist_ok=True)

# Lower = stricter. 0.6 is face_recognition's default; 0.5 cuts false matches further.
MATCH_TOLERANCE = float(os.getenv("FACE_MATCH_TOLERANCE", 0.5))

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

def _single_face_encoding(image_bytes: bytes) -> tuple[np.ndarray | None, str]:
    image = face_recognition.load_image_file(io.BytesIO(image_bytes))
    encodings = face_recognition.face_encodings(image)
    if len(encodings) == 0:
        return None, "No face detected. Please try again."
    if len(encodings) > 1:
        return None, "More than one face detected. Only one person should be in frame."
    return encodings[0], "OK"


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
                tolerance: float = MATCH_TOLERANCE) -> tuple[Employee | None, str]:
    """1:1 check — does this photo match the stored faces of `employee_id`?"""
    rows = db.query(FaceImage).filter(FaceImage.employee_id == employee_id).all()
    if not rows:
        return None, "No faces registered yet. Ask admin to register your face first."

    unknown_enc, msg = _single_face_encoding(image_bytes)
    if unknown_enc is None:
        return None, msg

    known_encs = [np.array(json.loads(r.embedding)) for r in rows]
    best_dist  = float(np.min(face_recognition.face_distance(known_encs, unknown_enc)))
    if best_dist <= tolerance:
        return db.get(Employee, employee_id), "OK"
    return None, "Face not recognized. Please try again."
