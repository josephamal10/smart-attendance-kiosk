"""
Face anti-spoofing (presentation attack detection).

Blink liveness stops a printed photo, but not a phone or laptop replaying a video
of the person blinking. This module runs two small CNNs (MiniFASNet V2 and V1SE,
from Minivision's Silent-Face-Anti-Spoofing, Apache 2.0) that look at texture,
moiré, screen glare and bezel edges around the face, and outputs P(real).

Runtime needs only numpy + OpenCV + onnxruntime. The ONNX files are produced by
ml/antispoof/export_onnx.py (and can be fine-tuned by ml/antispoof/finetune.py).
"""
import json
import os
import threading
from dataclasses import dataclass

import cv2
import numpy as np

MODEL_DIR = os.getenv("ANTISPOOF_MODEL_DIR", os.path.join("models", "antispoof"))
# "fp32" (default) or "int8" — int8 is 2.6x smaller but was no faster and less
# accurate for these tiny 80x80 CNNs (see export_onnx.py output), so fp32 is served.
MODEL_VARIANT = os.getenv("ANTISPOOF_VARIANT", "fp32")
INPUT_SIZE = 80
REAL_CLASS = 1  # classes: 0 = print attack, 1 = real, 2 = replay attack


@dataclass(frozen=True)
class ModelSpec:
    name: str
    scale: float  # how much context around the face box each model sees


# Each model sees a different amount of context: 2.7x catches texture on the face,
# 4x catches phone/screen edges and hands around it.
MODELS = (
    ModelSpec("MiniFASNetV2", 2.7),
    ModelSpec("MiniFASNetV1SE", 4.0),
)


def _threshold_from_report() -> float:
    """Use the threshold chosen by ml/antispoof/evaluate.py if it has been run, else 0.5."""
    env = os.getenv("ANTISPOOF_THRESHOLD")
    if env:
        return float(env)
    report = os.path.join(MODEL_DIR, "threshold.json")
    if os.path.exists(report):
        with open(report, encoding="utf-8") as f:
            return float(json.load(f)["threshold"])
    return 0.5


# ── Preprocessing (shared with the ML scripts, so training and serving match) ──

def expand_box(src_w: int, src_h: int, box_xywh, scale: float) -> tuple[int, int, int, int]:
    """Grow a face box by `scale` around its centre, shifting it to stay inside the image.
    Same maths as the original Silent-Face-Anti-Spoofing code."""
    x, y, w, h = box_xywh
    scale = min((src_h - 1) / h, (src_w - 1) / w, scale)
    new_w, new_h = w * scale, h * scale
    cx, cy = x + w / 2, y + h / 2
    x1, y1 = cx - new_w / 2, cy - new_h / 2
    x2, y2 = cx + new_w / 2, cy + new_h / 2
    if x1 < 0:
        x2 -= x1; x1 = 0
    if y1 < 0:
        y2 -= y1; y1 = 0
    if x2 > src_w - 1:
        x1 -= x2 - src_w + 1; x2 = src_w - 1
    if y2 > src_h - 1:
        y1 -= y2 - src_h + 1; y2 = src_h - 1
    return int(x1), int(y1), int(x2), int(y2)


def crop_face(img_bgr: np.ndarray, box_xywh, scale: float) -> np.ndarray:
    """Return an 80x80 BGR crop around the face, as the models were trained on."""
    h, w = img_bgr.shape[:2]
    x1, y1, x2, y2 = expand_box(w, h, box_xywh, scale)
    return cv2.resize(img_bgr[y1:y2 + 1, x1:x2 + 1], (INPUT_SIZE, INPUT_SIZE))


def to_input(crops: list[np.ndarray]) -> np.ndarray:
    """HWC uint8 BGR crops → NCHW float32. Note: the models expect 0-255, not 0-1."""
    return np.stack([c.transpose(2, 0, 1) for c in crops]).astype(np.float32)


def box_from_trbl(top: int, right: int, bottom: int, left: int) -> tuple[int, int, int, int]:
    """face_recognition gives (top, right, bottom, left); the models want (x, y, w, h).

    dlib's HOG box is tight (eyebrows to lip line), while the RetinaFace detector these
    models were trained with draws a looser box. Growing it 10% wide / 25% tall (mostly
    upwards, to include the forehead) gave the highest worst-case P(real) on 126 real
    webcam captures: min 0.86 vs 0.69 for the raw dlib box (ml/antispoof/README.md)."""
    w, h = right - left, bottom - top
    grow_w, grow_h = w * 0.10, h * 0.25
    return (int(left - grow_w / 2), int(top - grow_h * 0.8), int(w + grow_w), int(h + grow_h))


def _softmax(z: np.ndarray) -> np.ndarray:
    e = np.exp(z - z.max(axis=1, keepdims=True))
    return e / e.sum(axis=1, keepdims=True)


# ── Inference ─────────────────────────────────────────────────────────────────

class AntiSpoof:
    def __init__(self, model_dir: str = MODEL_DIR, variant: str = MODEL_VARIANT):
        import onnxruntime as ort

        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 2
        self.sessions = []
        for spec in MODELS:
            path = os.path.join(model_dir, f"{spec.name}.{variant}.onnx")
            if not os.path.exists(path):
                raise FileNotFoundError(
                    f"{path} not found. Run: python ml/antispoof/export_onnx.py")
            self.sessions.append((spec, ort.InferenceSession(path, opts, providers=["CPUExecutionProvider"])))

    def probabilities(self, img_bgr: np.ndarray, box_xywh) -> np.ndarray:
        """Averaged 3-class probabilities [print, real, replay] for one face."""
        probs = np.zeros(3, dtype=np.float64)
        for spec, sess in self.sessions:
            x = to_input([crop_face(img_bgr, box_xywh, spec.scale)])
            logits = sess.run(None, {sess.get_inputs()[0].name: x})[0]
            probs += _softmax(logits)[0]
        return probs / len(self.sessions)

    def real_score(self, img_bgr: np.ndarray, box_xywh) -> float:
        return float(self.probabilities(img_bgr, box_xywh)[REAL_CLASS])


_instance: AntiSpoof | None = None
_lock = threading.Lock()


def get_model() -> AntiSpoof:
    global _instance
    with _lock:
        if _instance is None:
            _instance = AntiSpoof()
        return _instance


def is_enabled() -> bool:
    return os.getenv("ANTISPOOF_ENABLED", "true").lower() not in ("0", "false", "no")


def check(img_rgb: np.ndarray, face_location_trbl) -> tuple[bool, float]:
    """(is_real, score) for a face found by face_recognition in an RGB image."""
    score = get_model().real_score(
        cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR), box_from_trbl(*face_location_trbl))
    return score >= _threshold_from_report(), score
