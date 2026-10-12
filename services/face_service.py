import face_recognition
import numpy as np
import json
import os
import uuid
import tempfile
import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python.vision import FaceLandmarker, FaceLandmarkerOptions
from mediapipe.tasks.python.vision.core.vision_task_running_mode import VisionTaskRunningMode
from sqlalchemy.orm import Session
from models import FaceImage, Employee

FACE_IMAGE_DIR = "face_images"
os.makedirs(FACE_IMAGE_DIR, exist_ok=True)

# Eye landmark indices (MediaPipe 478 landmarks)
LEFT_EYE  = [362, 385, 387, 263, 373, 380]
RIGHT_EYE = [33,  160, 158, 133, 153, 144]

# Face landmarker model path
_MODEL_PATH = "face_landmarker.task"


def _ensure_model():
    """Download face landmarker model if not present."""
    if not os.path.exists(_MODEL_PATH):
        import urllib.request
        url = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
        print("Downloading face landmarker model...")
        urllib.request.urlretrieve(url, _MODEL_PATH)
        print("Model downloaded.")


def _ear(landmarks, eye_indices):
    """Calculate Eye Aspect Ratio for blink detection."""
    pts = np.array([[landmarks[i].x, landmarks[i].y] for i in eye_indices])
    A = np.linalg.norm(pts[1] - pts[5])
    B = np.linalg.norm(pts[2] - pts[4])
    C = np.linalg.norm(pts[0] - pts[3])
    return (A + B) / (2.0 * C) if C > 0 else 0


# ── Blink Detection ───────────────────────────────────────────────────────────

def detect_blink(image_bytes: bytes) -> dict:
    """
    Analyze a single frame and return EAR value.
    Flutter sends multiple frames; blink = EAR drops below threshold.
    """
    try:
        _ensure_model()
    except Exception as e:
        return {"success": False, "ear": 0.0, "message": f"Model error: {e}"}

    np_arr = np.frombuffer(image_bytes, np.uint8)
    img    = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    if img is None:
        return {"success": False, "ear": 0.0, "message": "Invalid image"}

    rgb      = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

    options = FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=_MODEL_PATH),
        running_mode=VisionTaskRunningMode.IMAGE,
        num_faces=1,
    )

    with FaceLandmarker.create_from_options(options) as detector:
        result = detector.detect(mp_image)

    if not result.face_landmarks:
        return {"success": False, "ear": 0.0, "message": "No face detected"}

    lm    = result.face_landmarks[0]
    left  = _ear(lm, LEFT_EYE)
    right = _ear(lm, RIGHT_EYE)
    avg   = (left + right) / 2.0

    return {"success": True, "ear": round(avg, 4), "message": "OK"}


# ── Save Face Image + Embedding ───────────────────────────────────────────────

def save_face_image(db: Session, employee_id: int, direction: str,
                    image_bytes: bytes) -> dict:
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        tmp.write(image_bytes)
        tmp_path = tmp.name

    try:
        image     = face_recognition.load_image_file(tmp_path)
        encodings = face_recognition.face_encodings(image)

        if len(encodings) == 0:
            return {"success": False, "message": "No face detected. Please try again."}

        embedding = encodings[0]

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

        total = get_face_count_by_employee(db, employee_id)
        return {
            "success": True,
            "message": "Face saved successfully.",
            "total": total,
            "image_id": face_img.id,
        }

    finally:
        os.remove(tmp_path)


# ── Get Face Count ────────────────────────────────────────────────────────────

def get_face_count_by_employee(db: Session, employee_id: int) -> int:
    return db.query(FaceImage).filter(
        FaceImage.employee_id == employee_id).count()


# ── Recognize Face ────────────────────────────────────────────────────────────

def recognize_face(db: Session, image_bytes: bytes,
                   tolerance: float = 0.55,
                   employee_id: int | None = None) -> Employee | None:
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        tmp.write(image_bytes)
        tmp_path = tmp.name

    try:
        image     = face_recognition.load_image_file(tmp_path)
        encodings = face_recognition.face_encodings(image)

        if len(encodings) == 0:
            return None

        unknown_enc = encodings[0]
        query = db.query(FaceImage)
        if employee_id is not None:
            query = query.filter(FaceImage.employee_id == employee_id)
        rows = query.all()
        if not rows:
            return None

        known_encs = [np.array(json.loads(r.embedding)) for r in rows]
        emp_ids    = [r.employee_id for r in rows]

        distances = face_recognition.face_distance(known_encs, unknown_enc)
        best_idx  = int(np.argmin(distances))
        best_dist = float(distances[best_idx])

        if best_dist <= tolerance:
            return db.query(Employee).filter(
                Employee.id == emp_ids[best_idx]).first()
        return None

    finally:
        os.remove(tmp_path)
