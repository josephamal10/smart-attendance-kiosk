import os

import cv2
import numpy as np
import pytest

from services.face_engine import cosine_similarity, get_engine


FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "astronaut.jpg")


@pytest.fixture(scope="module")
def portrait():
    """Eileen Collins, NASA portrait (public domain, via scikit-image's sample data)."""
    return cv2.imread(FIXTURE)


def test_no_face_in_blank_image():
    assert get_engine().detect(np.full((480, 640, 3), 127, np.uint8)) == []


def test_finds_exactly_one_face(portrait):
    faces = get_engine().detect(portrait)
    assert len(faces) == 1 and faces[0].score > 0.8


def test_embeddings_are_unit_length(portrait):
    face = get_engine().detect(portrait)[0]
    emb = get_engine().embed(portrait, face)
    assert emb.shape == (128,)
    assert np.linalg.norm(emb) == pytest.approx(1.0, abs=1e-5)


def test_detections_are_in_original_coordinates(portrait):
    """Detection runs on a downscaled copy of big frames; boxes must be scaled back up."""
    big = cv2.resize(portrait, (2048, 2048))
    small_box, big_box = get_engine().detect(portrait)[0].box, get_engine().detect(big)[0].box
    assert big_box[0] == pytest.approx(small_box[0] * 4, rel=0.1)
    assert big_box[2] == pytest.approx(small_box[2] * 4, rel=0.1)


def test_same_face_matches_itself_after_resizing_and_flip(portrait):
    eng = get_engine()
    a = eng.embed(portrait, eng.detect(portrait)[0])
    other = cv2.resize(portrait, (900, 900))
    b = eng.embed(other, eng.detect(other)[0])
    assert float(a @ b) > 0.8


def test_cosine_similarity_of_identical_vectors_is_one():
    v = np.ones(128) / np.sqrt(128)
    assert cosine_similarity(np.stack([v, -v]), v) == pytest.approx([1.0, -1.0])
