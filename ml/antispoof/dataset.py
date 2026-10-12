"""
Folder dataset shared by evaluate.py and finetune.py.

    data/antispoof/
        real/     <session>_<n>.jpg     live person in front of the webcam
        print/    <session>_<n>.jpg     printed photo held up to the camera
        replay/   <session>_<n>.jpg     photo/video shown on a phone or laptop screen

`<session>` (e.g. "amal-office-day") groups frames recorded together. Splits are made by
session, never by frame: neighbouring frames are near-identical, so mixing them across
train/test would make the scores look far better than reality.

Faces are located once with YuNet (services/face_engine.py) and cached in boxes.json next to the data.
"""
import glob
import json
import os
from dataclasses import dataclass

import cv2

from services.antispoof_service import box_from_yunet

LABELS = ("real", "print", "replay")
# Model output classes (from the original training): 0 = print, 1 = real, 2 = replay
CLASS_INDEX = {"print": 0, "real": 1, "replay": 2}


@dataclass
class Sample:
    path: str
    label: str
    session: str
    box: tuple[int, int, int, int]  # x, y, w, h (already grown to the model's framing)


def session_of(path: str) -> str:
    return os.path.basename(path).rsplit("_", 1)[0]


def load(root: str) -> tuple[list[Sample], int]:
    """Return (samples with exactly one face, number of images skipped)."""
    from services.face_engine import get_engine

    engine = get_engine()
    cache_path = os.path.join(root, "boxes.json")
    cache = {}
    if os.path.exists(cache_path):
        with open(cache_path, encoding="utf-8") as f:
            cache = json.load(f)

    samples, skipped, dirty = [], 0, False
    for label in LABELS:
        for path in sorted(glob.glob(os.path.join(root, label, "*.jpg"))):
            key = os.path.relpath(path, root).replace("\\", "/")
            if key not in cache:
                cache[key] = [list(map(float, f.box)) for f in engine.detect(read_bgr(path))]
                dirty = True
            boxes = cache[key]
            if len(boxes) != 1:
                skipped += 1
                continue
            samples.append(Sample(path, label, session_of(path), box_from_yunet(boxes[0])))

    if dirty:
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump(cache, f)
    return samples, skipped


def read_bgr(path: str):
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"Cannot read {path}")
    return img


def split_by_session(samples: list[Sample], test_sessions: set[str]):
    train = [s for s in samples if s.session not in test_sessions]
    test = [s for s in samples if s.session in test_sessions]
    return train, test
