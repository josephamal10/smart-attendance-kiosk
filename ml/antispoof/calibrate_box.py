"""
Carry the anti-spoofing face-box calibration over from dlib to YuNet.

The crop framing was tuned with dlib boxes grown 10% wide / 25% tall (best worst-case
P(real) on 126 real webcam captures, see README). YuNet draws its boxes differently, so
this measures, on LFW faces both detectors find, where that tuned box sits relative to
YuNet's box. Prints offsets for YUNET_TO_MODEL_BOX in services/antispoof_service.py.

    python ml/antispoof/calibrate_box.py
"""
import os
import sys

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
os.chdir(ROOT)


def grown_dlib_box(top, right, bottom, left):
    # The calibrated framing from the dlib era (kept here as the reference)
    w, h = right - left, bottom - top
    gw, gh = w * 0.10, h * 0.25
    return (left - gw / 2, top - gh * 0.8, w + gw, h + gh)


def main():
    import face_recognition
    from ml import lfw
    from services.face_engine import get_engine

    engine = get_engine()
    paths = sorted({p for a, b, _, _ in lfw.pairs() for p in (a, b)})[:2000]

    rel = []
    for path in paths:
        rgb = lfw.read_rgb(path)
        locs = face_recognition.face_locations(rgb)
        faces = engine.detect(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
        if len(locs) != 1 or len(faces) != 1:
            continue
        gx, gy, gw, gh = grown_dlib_box(*locs[0])
        yx, yy, yw, yh = faces[0].box
        rel.append(((gx - yx) / yw, (gy - yy) / yh, gw / yw, gh / yh))

    rel = np.array(rel)
    med, iqr = np.median(rel, 0), np.subtract(*np.percentile(rel, [75, 25], 0))
    print(f"faces found by both: {len(rel)}")
    for name, m, q in zip(("dx", "dy", "scale_w", "scale_h"), med, iqr):
        print(f"  {name:8s} median {m:+.3f}   IQR {q:.3f}")
    print(f"\nYUNET_TO_MODEL_BOX = ({med[0]:.3f}, {med[1]:.3f}, {med[2]:.3f}, {med[3]:.3f})")


if __name__ == "__main__":
    main()
