"""
Face detection + recognition with OpenCV Zoo models (both ONNX, run by cv2.dnn):

  YuNet  (MIT)        face detector, ~0.2 MB, returns a box + 5 landmarks per face
  SFace  (Apache 2.0) recognizer: aligns the face with those landmarks and outputs
                      a 128-d embedding; same person ⇔ high cosine similarity

Replaces dlib/face_recognition: no C++ build step on Windows, and much faster
detection on HD webcam frames (see ml/face_benchmark.py for the LFW comparison).
"""
import hashlib
import os
import threading
import urllib.request
from dataclasses import dataclass

import cv2
import numpy as np

MODEL_DIR = os.getenv("FACE_MODEL_DIR", os.path.join("models", "face"))
_ZOO = "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/"
_MODELS = {
    "detector": ("face_detection_yunet_2023mar.onnx",
                 "face_detection_yunet/",
                 "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"),
    "recognizer": ("face_recognition_sface_2021dec.onnx",
                   "face_recognition_sface/",
                   "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"),
}

# Detection runs on a downscaled copy: faces at a kiosk are big, and YuNet's cost grows
# with pixel count (a 1920x1080 frame is ~7x the work of 720 px wide for no benefit).
DETECT_MAX_SIDE = 720
DETECT_SCORE = 0.8


@dataclass
class Face:
    box: tuple[float, float, float, float]   # x, y, w, h in original-image pixels
    landmarks: np.ndarray                    # 5x2: right eye, left eye, nose, mouth corners
    score: float
    raw: np.ndarray                          # YuNet's 15-value row, needed by SFace alignment


def _model_path(key: str) -> str:
    filename, zoo_dir, sha256 = _MODELS[key]
    path = os.path.join(MODEL_DIR, filename)
    if not os.path.exists(path):
        os.makedirs(MODEL_DIR, exist_ok=True)
        print(f"Downloading {filename} from OpenCV Zoo...")
        urllib.request.urlretrieve(_ZOO + zoo_dir + filename, path)
    with open(path, "rb") as f:
        if hashlib.sha256(f.read()).hexdigest() != sha256:
            raise RuntimeError(f"{path} is corrupted or not the expected model; delete it to re-download")
    return path


class FaceEngine:
    def __init__(self):
        self._detector = cv2.FaceDetectorYN.create(_model_path("detector"), "", (320, 320), DETECT_SCORE)
        self._recognizer = cv2.FaceRecognizerSF.create(_model_path("recognizer"), "")
        # cv2.dnn networks are not safe to call from several threads at once
        self._lock = threading.Lock()

    def detect(self, img_bgr: np.ndarray) -> list[Face]:
        h, w = img_bgr.shape[:2]
        f = min(1.0, DETECT_MAX_SIDE / max(h, w))
        small = cv2.resize(img_bgr, (round(w * f), round(h * f))) if f < 1 else img_bgr
        with self._lock:
            self._detector.setInputSize((small.shape[1], small.shape[0]))
            _, rows = self._detector.detect(small)
        faces = []
        for row in rows if rows is not None else []:
            row = row.copy()
            row[:14] /= f  # back to original-image coordinates
            faces.append(Face(tuple(row[:4]), row[4:14].reshape(5, 2), float(row[14]), row))
        return faces

    def embed(self, img_bgr: np.ndarray, face: Face) -> np.ndarray:
        """L2-normalised 128-d embedding (so a dot product = cosine similarity)."""
        with self._lock:
            aligned = self._recognizer.alignCrop(img_bgr, face.raw)
            feat = self._recognizer.feature(aligned).flatten()
        return feat / (np.linalg.norm(feat) + 1e-12)


def cosine_similarity(known: np.ndarray, probe: np.ndarray) -> np.ndarray:
    """Similarity of `probe` to each row of `known` (all L2-normalised)."""
    return np.atleast_2d(known) @ probe


_engine: FaceEngine | None = None
_engine_lock = threading.Lock()


def get_engine() -> FaceEngine:
    global _engine
    with _engine_lock:
        if _engine is None:
            _engine = FaceEngine()
        return _engine
