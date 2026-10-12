import glob
import io

import numpy as np
import pytest

from ml.antispoof import metrics
from services import antispoof_service as asp
from services import face_service


# ── Metrics ───────────────────────────────────────────────────────────────────

LABELS = ["real"] * 4 + ["print"] * 2 + ["replay"] * 2
SCORES = [0.9, 0.8, 0.7, 0.4, 0.1, 0.6, 0.2, 0.3]


def test_apcer_reports_worst_attack_type():
    m = metrics.apcer_bpcer(SCORES, LABELS, 0.5)
    assert m["apcer_per_type"] == {"print": 0.5, "replay": 0.0}
    assert m["apcer"] == 0.5          # worst type, not the average
    assert m["bpcer"] == 0.25         # the 0.4 real sample is rejected
    assert m["acer"] == pytest.approx(0.375)


def test_perfectly_separated_scores_have_zero_eer_and_auc_one():
    labels = ["real", "real", "print", "replay"]
    scores = [0.9, 0.8, 0.2, 0.1]
    assert metrics.eer(scores, labels)[0] == 0.0
    assert metrics.roc_auc(scores, labels) == 1.0


def test_tuned_threshold_respects_bpcer_budget():
    rng = np.random.default_rng(0)
    scores = np.concatenate([rng.uniform(0.3, 1, 100), rng.uniform(0, 0.7, 100)])
    labels = ["real"] * 100 + ["replay"] * 100
    t = metrics.threshold_for_bpcer(scores, labels, 0.05)
    assert metrics.apcer_bpcer(scores, labels, t)["bpcer"] <= 0.05


# ── Preprocessing ─────────────────────────────────────────────────────────────

@pytest.mark.parametrize("box", [(0, 0, 100, 120), (580, 400, 60, 80), (300, 200, 50, 60)])
@pytest.mark.parametrize("scale", [2.7, 4.0])
def test_expanded_box_stays_inside_image(box, scale):
    x1, y1, x2, y2 = asp.expand_box(640, 480, box, scale)
    assert 0 <= x1 < x2 <= 639 and 0 <= y1 < y2 <= 479


def test_crop_is_80x80_bgr():
    img = np.zeros((480, 640, 3), np.uint8)
    assert asp.crop_face(img, (300, 200, 80, 100), 2.7).shape == (80, 80, 3)


def test_model_input_is_0_to_255_nchw():
    crop = np.full((80, 80, 3), 200, np.uint8)
    x = asp.to_input([crop])
    assert x.shape == (1, 3, 80, 80) and x.dtype == np.float32 and x.max() == 200.0


def test_onnx_models_output_valid_probabilities():
    model = asp.AntiSpoof()
    img = np.random.default_rng(1).integers(0, 255, (480, 640, 3), dtype=np.uint8)
    p = model.probabilities(img, (280, 180, 80, 100))
    assert p.shape == (3,) and p.sum() == pytest.approx(1.0, abs=1e-5)


@pytest.mark.skipif(not glob.glob("face_images/*.jpg"), reason="no local face captures")
def test_real_webcam_captures_are_judged_real():
    import face_recognition
    paths = sorted(glob.glob("face_images/*.jpg"))[:10]
    for path in paths:
        rgb = face_recognition.load_image_file(path)
        locs = face_recognition.face_locations(rgb)
        if len(locs) == 1:
            is_real, score = asp.check(rgb, locs[0])
            assert is_real, f"{path} scored {score:.3f}"


# ── Wiring into check-in / registration ──────────────────────────────────────

@pytest.fixture
def one_face(monkeypatch):
    monkeypatch.setattr(face_service.face_recognition, "load_image_file", lambda f: np.zeros((10, 10, 3)))
    monkeypatch.setattr(face_service.face_recognition, "face_locations", lambda img: [(1, 2, 3, 4)])
    monkeypatch.setattr(face_service.face_recognition, "face_encodings",
                        lambda img, known_face_locations=None: [np.zeros(128)])


def test_spoofed_face_is_refused(one_face, monkeypatch):
    monkeypatch.setattr(asp, "check", lambda img, loc: (False, 0.02))
    enc, msg = face_service._single_face_encoding(b"x")
    assert enc is None and msg == face_service.SPOOF_MESSAGE


def test_live_face_passes(one_face, monkeypatch):
    monkeypatch.setattr(asp, "check", lambda img, loc: (True, 0.97))
    enc, msg = face_service._single_face_encoding(b"x")
    assert enc is not None and msg == "OK"


def test_antispoof_can_be_disabled(one_face, monkeypatch):
    monkeypatch.setenv("ANTISPOOF_ENABLED", "false")
    monkeypatch.setattr(asp, "check", lambda img, loc: pytest.fail("should not run"))
    assert face_service._single_face_encoding(b"x")[1] == "OK"
