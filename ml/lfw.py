"""
LFW (Labeled Faces in the Wild) pairs, read lazily from disk.

scikit-learn's fetch_lfw_pairs loads every image as float arrays (~9 GB in colour at full
size), so we only use it to download, then read the official 10-fold pairs.txt ourselves.
"""
import os

import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LFW_HOME = os.path.join(ROOT, "data", "lfw", "lfw_home")


def ensure_downloaded():
    if not os.path.exists(os.path.join(LFW_HOME, "pairs.txt")):
        from sklearn.datasets._lfw import _check_fetch_lfw
        _check_fetch_lfw(data_home=os.path.join(ROOT, "data", "lfw"), funneled=True,
                         download_if_missing=True)


def _path(name: str, n: str) -> str:
    return os.path.join(LFW_HOME, "lfw_funneled", name, f"{name}_{int(n):04d}.jpg")


def pairs() -> list[tuple[str, str, bool, int]]:
    """6000 (image_a, image_b, same_person, fold) tuples from the standard 10-fold protocol."""
    ensure_downloaded()
    with open(os.path.join(LFW_HOME, "pairs.txt"), encoding="utf-8") as f:
        n_folds, per = map(int, f.readline().split())
        out = []
        for fold in range(n_folds):
            for _ in range(per):        # same person: name  i  j
                name, i, j = f.readline().split()
                out.append((_path(name, i), _path(name, j), True, fold))
            for _ in range(per):        # different: name1  i  name2  j
                a, i, b, j = f.readline().split()
                out.append((_path(a, i), _path(b, j), False, fold))
    return out


def read_rgb(path: str):
    return cv2.cvtColor(cv2.imread(path, cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
