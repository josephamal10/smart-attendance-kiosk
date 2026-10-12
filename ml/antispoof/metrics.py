"""
Presentation-attack-detection metrics (ISO/IEC 30107-3).

Scores are P(real): higher = more likely a live person. A sample is *accepted*
as real when score >= threshold.

  APCER  attack presentations wrongly accepted as real, computed per attack type
         (print, replay, ...); the standard reports the WORST type, since a system
         is only as strong as its weakest attack.
  BPCER  bona fide (real) presentations wrongly rejected — annoyed employees.
  ACER   (APCER + BPCER) / 2, a single headline number.
  EER    the point where APCER == BPCER (the face analogue of a voice-spoofing EER).
"""
import numpy as np


def apcer_bpcer(scores, labels, threshold: float) -> dict:
    """labels: "real" for bona fide, anything else is an attack type name."""
    scores, labels = np.asarray(scores, float), np.asarray(labels)
    real = labels == "real"
    if not real.any() or real.all():
        raise ValueError("Need both real and attack samples")

    per_type = {
        t: float(np.mean(scores[labels == t] >= threshold))
        for t in sorted(set(labels[~real].tolist()))
    }
    apcer = max(per_type.values())
    bpcer = float(np.mean(scores[real] < threshold))
    return {
        "threshold": float(threshold),
        "apcer": apcer,
        "apcer_per_type": per_type,
        "bpcer": bpcer,
        "acer": (apcer + bpcer) / 2,
    }


def _candidate_thresholds(scores) -> np.ndarray:
    s = np.unique(np.asarray(scores, float))
    # Every distinct score, plus just above the max so "reject everything" is an option
    return np.concatenate([s, [np.nextafter(s[-1], np.inf)]])


def eer(scores, labels) -> tuple[float, float]:
    """(equal error rate, threshold at which it occurs), using the worst-case APCER."""
    best = None
    for t in _candidate_thresholds(scores):
        m = apcer_bpcer(scores, labels, t)
        gap = abs(m["apcer"] - m["bpcer"])
        if best is None or gap < best[0]:
            best = (gap, (m["apcer"] + m["bpcer"]) / 2, t)
    return float(best[1]), float(best[2])


def threshold_for_bpcer(scores, labels, max_bpcer: float) -> float:
    """Strictest threshold (lowest APCER) that still rejects at most `max_bpcer` of real
    users. This is how you'd tune a kiosk: decide how often a genuine employee may be
    asked to retry, then block as many attacks as possible within that budget."""
    scores, labels = np.asarray(scores, float), np.asarray(labels)
    real_scores = np.sort(scores[labels == "real"])
    # We may reject k real samples. Setting the threshold to the k-th lowest real score
    # (0-indexed) rejects only the k scores strictly below it.
    k = int(np.floor(max_bpcer * len(real_scores)))
    return float(real_scores[k])


def roc_auc(scores, labels) -> float:
    """Probability a random real sample scores higher than a random attack (ties count half)."""
    scores, labels = np.asarray(scores, float), np.asarray(labels)
    pos, neg = scores[labels == "real"], scores[labels != "real"]
    greater = (pos[:, None] > neg[None, :]).sum()
    ties = (pos[:, None] == neg[None, :]).sum()
    return float((greater + 0.5 * ties) / (len(pos) * len(neg)))
