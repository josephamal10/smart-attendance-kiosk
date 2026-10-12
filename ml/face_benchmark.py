"""
Benchmark face verification engines on LFW (Labeled Faces in the Wild), standard
10-fold protocol: 6000 pairs (3000 same person, 3000 different). For each fold the
threshold is chosen on the other 9 folds, then accuracy is measured on the held-out one.

    python ml/face_benchmark.py                 # dlib vs YuNet+SFace
    python ml/face_benchmark.py --engines sface

Also reports TAR @ FAR (how many genuine pairs pass when only 1% / 0.1% of impostor pairs
may pass — the number that matters for a door or attendance system), detection
failures, and speed on a 1920x1080 webcam-sized frame.

Writes reports/face_benchmark.json. LFW is downloaded into data/lfw (see ml/lfw.py).
"""
import argparse
import json
import os
import sys
import time

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)

from ml import lfw  # noqa: E402


# ── Engines: image (RGB uint8) -> unit embedding, or None if no face found ────

class Dlib:
    name = "dlib (face_recognition)"
    higher_is_same = False  # Euclidean distance

    def __init__(self):
        import face_recognition
        self.fr = face_recognition

    def detect(self, rgb):
        return self.fr.face_locations(rgb)

    def embed(self, rgb):
        locs = self.detect(rgb)
        if not locs:
            return None
        biggest = max(locs, key=lambda l: (l[2] - l[0]) * (l[1] - l[3]))
        return self.fr.face_encodings(rgb, known_face_locations=[biggest])[0]

    @staticmethod
    def score(a, b):
        return float(np.linalg.norm(a - b))


class SFace:
    name = "YuNet + SFace (OpenCV Zoo)"
    higher_is_same = True  # cosine similarity

    def __init__(self):
        from services.face_engine import get_engine
        self.engine = get_engine()

    def detect(self, rgb):
        return self.engine.detect(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))

    def embed(self, rgb):
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        faces = self.engine.detect(bgr)
        if not faces:
            return None
        biggest = max(faces, key=lambda f: f.box[2] * f.box[3])
        return self.engine.embed(bgr, biggest)

    @staticmethod
    def score(a, b):
        return float(a @ b)


ENGINES = {"dlib": Dlib, "sface": SFace}


# ── Protocol ──────────────────────────────────────────────────────────────────

def _acc_at(scores, same, t, higher):
    pred = scores >= t if higher else scores <= t
    return float(np.mean(pred == same))


def best_threshold(scores, same, higher):
    cands = np.unique(scores)
    accs = [_acc_at(scores, same, t, higher) for t in cands]
    return float(cands[int(np.argmax(accs))])


def tar_at_far(scores, same, higher, far):
    s = scores if higher else -scores
    impostor = np.sort(s[~same])[::-1]
    k = int(np.floor(far * len(impostor)))
    t = impostor[k] if k < len(impostor) else impostor[-1]
    return float(np.mean(s[same] > t)), float(t if higher else -t)


def evaluate(engine_cls, pairs):
    eng = engine_cls()
    paths = sorted({p for a, b, _, _ in pairs for p in (a, b)})
    t0 = time.perf_counter()
    emb = {}
    for i, path in enumerate(paths):
        emb[path] = eng.embed(lfw.read_rgb(path))
        if (i + 1) % 1000 == 0:
            print(f"  {i + 1}/{len(paths)} images  ({time.perf_counter() - t0:.0f}s)")

    same = np.array([s for _, _, s, _ in pairs])
    folds = np.array([f for _, _, _, f in pairs])
    scores = np.empty(len(pairs))
    failed = np.zeros(len(pairs), bool)
    for i, (a, b, _, _) in enumerate(pairs):
        if emb[a] is None or emb[b] is None:
            failed[i] = True
            # A failed detection means the kiosk can't verify: count it as "not the same"
            scores[i] = -1.0 if eng.higher_is_same else 9.0
        else:
            scores[i] = eng.score(emb[a], emb[b])

    accs, thresholds = [], []
    for k in np.unique(folds):
        test = folds == k
        tune = ~test if (~test).any() else test  # a 1-fold quick check tunes on itself
        t = best_threshold(scores[tune], same[tune], eng.higher_is_same)
        thresholds.append(t)
        accs.append(_acc_at(scores[test], same[test], t, eng.higher_is_same))

    tar1, t1 = tar_at_far(scores, same, eng.higher_is_same, 0.01)
    tar01, t01 = tar_at_far(scores, same, eng.higher_is_same, 0.001)
    return eng, {
        "engine": eng.name,
        "accuracy_mean": float(np.mean(accs)),
        "accuracy_std": float(np.std(accs)),
        "threshold_mean": float(np.mean(thresholds)),
        "tar_at_far_1%": tar1, "threshold_far_1%": t1,
        "tar_at_far_0.1%": tar01, "threshold_far_0.1%": t01,
        "images_without_face": int(sum(v is None for v in emb.values())),
        "pairs_affected": int(failed.sum()),
        "pairs": len(pairs),
    }


def speed(eng, face_rgb, runs=20):
    """Detect + embed one face placed in a 1920x1080 frame, like a webcam capture."""
    frame = np.full((1080, 1920, 3), 90, np.uint8)
    big = cv2.resize(face_rgb, (500, 500))
    frame[290:790, 710:1210] = big
    eng.embed(frame)
    t = time.perf_counter()
    for _ in range(runs):
        eng.embed(frame)
    return (time.perf_counter() - t) / runs * 1000


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engines", nargs="+", default=list(ENGINES), choices=list(ENGINES))
    ap.add_argument("--folds", type=int, default=10, help="use only the first N folds (quick check)")
    args = ap.parse_args()

    pairs = [p for p in lfw.pairs() if p[3] < args.folds]
    print(f"LFW: {len(pairs)} pairs in {args.folds} folds")

    results = []
    for key in args.engines:
        print(f"\n== {ENGINES[key].name} ==")
        eng, r = evaluate(ENGINES[key], pairs)
        r["ms_per_1080p_frame"] = speed(eng, lfw.read_rgb(pairs[0][0]))
        results.append(r)
        print(f"  accuracy {r['accuracy_mean']:.2%} +/- {r['accuracy_std']:.2%}   "
              f"TAR@FAR1% {r['tar_at_far_1%']:.2%}   TAR@FAR0.1% {r['tar_at_far_0.1%']:.2%}   "
              f"no-face images {r['images_without_face']}   {r['ms_per_1080p_frame']:.0f} ms/1080p frame")

    os.makedirs(os.path.join(ROOT, "reports"), exist_ok=True)
    with open(os.path.join(ROOT, "reports", "face_benchmark.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print("\nreport: reports/face_benchmark.json")


if __name__ == "__main__":
    main()
