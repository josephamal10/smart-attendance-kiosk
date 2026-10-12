"""
Score a labelled folder dataset and report APCER / BPCER / ACER / EER / AUC.

    python ml/antispoof/evaluate.py                                   # data/antispoof
    python ml/antispoof/evaluate.py --test-sessions amal-lab-night    # held-out sessions only
    python ml/antispoof/evaluate.py --model-dir runs/ft1 --name finetuned
    python ml/antispoof/evaluate.py --max-bpcer 0.05 --save-threshold # write threshold.json

Writes reports/antispoof/<name>/{report.json, scores.csv, scores.png}.
"""
import argparse
import csv
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)

from ml.antispoof import dataset, metrics                 # noqa: E402
from services.antispoof_service import AntiSpoof, MODEL_DIR  # noqa: E402


def plot(scores, labels, threshold, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(7, 3.5))
    bins = np.linspace(0, 1, 41)
    for label, color in (("real", "#2a9d8f"), ("print", "#e76f51"), ("replay", "#9b5de5")):
        s = scores[labels == label]
        if len(s):
            ax.hist(s, bins=bins, alpha=0.6, label=f"{label} (n={len(s)})", color=color)
    ax.axvline(threshold, color="black", linestyle="--", linewidth=1, label=f"threshold {threshold:.2f}")
    ax.set_xlabel("P(real)")
    ax.set_ylabel("frames")
    ax.set_title("Anti-spoofing scores by presentation type")
    ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", default=os.path.join(ROOT, "data", "antispoof"))
    ap.add_argument("--model-dir", default=MODEL_DIR)
    ap.add_argument("--variant", default="fp32", choices=["fp32", "int8"])
    ap.add_argument("--name", default="pretrained")
    ap.add_argument("--test-sessions", nargs="*", help="only score these sessions")
    ap.add_argument("--threshold", type=float, default=0.5)
    ap.add_argument("--max-bpcer", type=float, default=0.05,
                    help="real-user rejection budget used to pick a tuned threshold")
    ap.add_argument("--save-threshold", action="store_true",
                    help=f"write the tuned threshold to {MODEL_DIR}/threshold.json for the server")
    args = ap.parse_args()

    samples, skipped = dataset.load(args.data)
    if args.test_sessions:
        samples = [s for s in samples if s.session in set(args.test_sessions)]
    if not samples:
        sys.exit(f"No usable images under {args.data} (see ml/antispoof/capture.py)")

    model = AntiSpoof(args.model_dir, args.variant)
    scores = np.array([model.real_score(dataset.read_bgr(s.path), s.box) for s in samples])
    labels = np.array([s.label for s in samples])

    out_dir = os.path.join(ROOT, "reports", "antispoof", args.name)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "scores.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["path", "label", "session", "p_real"])
        for s, score in zip(samples, scores):
            w.writerow([os.path.relpath(s.path, ROOT), s.label, s.session, f"{score:.4f}"])

    counts = {l: int((labels == l).sum()) for l in dataset.LABELS}
    report = {"name": args.name, "variant": args.variant, "counts": counts,
              "skipped_no_single_face": skipped,
              "sessions": sorted({s.session for s in samples})}
    print(f"samples: {counts}  (skipped {skipped} without exactly one face)")

    if counts["real"] == len(samples) or counts["real"] == 0:
        # Only one class: we can still report the error rate for that class
        if counts["real"]:
            report["bpcer@threshold"] = float(np.mean(scores < args.threshold))
            print(f"BPCER @ {args.threshold}: {report['bpcer@threshold']:.1%}  "
                  f"(real only — record attacks to measure APCER)")
        else:
            report["apcer@threshold"] = float(np.mean(scores >= args.threshold))
            print(f"APCER @ {args.threshold}: {report['apcer@threshold']:.1%}  (attacks only)")
        tuned = args.threshold
    else:
        at_default = metrics.apcer_bpcer(scores, labels, args.threshold)
        eer, eer_t = metrics.eer(scores, labels)
        tuned = metrics.threshold_for_bpcer(scores, labels, args.max_bpcer)
        at_tuned = metrics.apcer_bpcer(scores, labels, tuned)
        report.update({
            "auc": metrics.roc_auc(scores, labels),
            "eer": eer, "eer_threshold": eer_t,
            "at_default_threshold": at_default,
            "at_tuned_threshold": at_tuned,
        })
        print(f"AUC {report['auc']:.3f}   EER {eer:.1%} (at {eer_t:.3f})")
        for title, m in (("default", at_default), (f"tuned for BPCER<={args.max_bpcer:.0%}", at_tuned)):
            per = ", ".join(f"{k} {v:.1%}" for k, v in m["apcer_per_type"].items())
            print(f"[{title}] threshold {m['threshold']:.3f}: APCER {m['apcer']:.1%} ({per})  "
                  f"BPCER {m['bpcer']:.1%}  ACER {m['acer']:.1%}")

    plot(scores, labels, tuned, os.path.join(out_dir, "scores.png"))
    with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"report: {os.path.relpath(out_dir, ROOT)}")

    if args.save_threshold:
        with open(os.path.join(args.model_dir, "threshold.json"), "w", encoding="utf-8") as f:
            json.dump({"threshold": tuned, "max_bpcer": args.max_bpcer, "from_report": args.name}, f, indent=2)
        print(f"saved threshold {tuned:.3f} to {args.model_dir}/threshold.json")


if __name__ == "__main__":
    main()
