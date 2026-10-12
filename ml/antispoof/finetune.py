"""
Fine-tune both MiniFASNet models on your own captures (domain adaptation).

The pretrained models were trained on other people's cameras and screens. A few hundred
frames from *this* kiosk's webcam, lighting and likely attack devices usually help a lot.

    python ml/antispoof/finetune.py --val-sessions amal-lab-night --out runs/ft1
    python ml/antispoof/export_onnx.py --weights-dir runs/ft1 --out-dir runs/ft1
    python ml/antispoof/evaluate.py --model-dir runs/ft1 --name ft1 --test-sessions amal-lab-night

Validation sessions are never trained on (frames from one session are near-duplicates,
so a frame-level split would leak). Class imbalance is handled with weighted sampling.
"""
import argparse
import json
import os
import random
import sys

import cv2
import numpy as np
import torch
from torch.utils.data import DataLoader, Dataset, WeightedRandomSampler

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)

from ml.antispoof import dataset, metrics                          # noqa: E402
from ml.antispoof.export_onnx import WEIGHT_FILES, load_torch        # noqa: E402
from services.antispoof_service import MODELS, REAL_CLASS, crop_face  # noqa: E402

# Final layers only; the rest stays frozen with --freeze (good when you have < ~500 frames)
HEAD_PREFIXES = ("conv_6_sep", "conv_6_dw", "linear", "bn", "prob")


class CropDataset(Dataset):
    def __init__(self, samples, scale: float, train: bool):
        self.samples, self.scale, self.train = samples, scale, train
        self._cache = {}

    def __len__(self):
        return len(self.samples)

    def _image(self, path):
        if path not in self._cache:
            img = dataset.read_bgr(path)
            # Frames are large; keep a downscaled copy in memory (box coords scaled to match)
            f = min(1.0, 960 / max(img.shape[:2]))
            self._cache[path] = (cv2.resize(img, None, fx=f, fy=f) if f < 1 else img, f)
        return self._cache[path]

    def __getitem__(self, i):
        s = self.samples[i]
        img, f = self._image(s.path)
        x, y, w, h = (v * f for v in s.box)
        if self.train:
            # Jitter the box like an imperfect face detector would
            j = random.uniform(0.9, 1.1)
            x += random.uniform(-0.05, 0.05) * w + w * (1 - j) / 2
            y += random.uniform(-0.05, 0.05) * h + h * (1 - j) / 2
            w, h = w * j, h * j
        crop = crop_face(img, (x, y, w, h), self.scale)
        if self.train:
            crop = augment(crop)
        x_t = torch.from_numpy(crop.transpose(2, 0, 1).astype(np.float32))  # 0-255, like serving
        return x_t, dataset.CLASS_INDEX[s.label]


def augment(crop: np.ndarray) -> np.ndarray:
    if random.random() < 0.5:
        crop = cv2.flip(crop, 1)
    if random.random() < 0.5:
        angle = random.uniform(-10, 10)
        m = cv2.getRotationMatrix2D((40, 40), angle, 1.0)
        crop = cv2.warpAffine(crop, m, (80, 80), borderMode=cv2.BORDER_REFLECT)
    # Lighting changes (lamp vs window), but not so strong that screen glare disappears
    alpha, beta = random.uniform(0.8, 1.2), random.uniform(-20, 20)
    crop = np.clip(crop.astype(np.float32) * alpha + beta, 0, 255).astype(np.uint8)
    if random.random() < 0.3:
        q = random.randint(60, 95)
        crop = cv2.imdecode(cv2.imencode(".jpg", crop, [cv2.IMWRITE_JPEG_QUALITY, q])[1], cv2.IMREAD_COLOR)
    return crop


def weighted_sampler(samples) -> WeightedRandomSampler:
    counts = {}
    for s in samples:
        counts[s.label] = counts.get(s.label, 0) + 1
    weights = [1.0 / counts[s.label] for s in samples]
    return WeightedRandomSampler(weights, num_samples=len(samples), replacement=True)


@torch.no_grad()
def p_real(model, loader) -> np.ndarray:
    model.eval()
    out = [torch.softmax(model(x), 1)[:, REAL_CLASS] for x, _ in loader]
    return torch.cat(out).numpy()


def train_one(spec, train_s, val_s, args) -> dict:
    model = load_torch(spec.name, args.weights_dir)
    if args.freeze:
        for name, p in model.named_parameters():
            p.requires_grad = name.startswith(HEAD_PREFIXES)
    params = [p for p in model.parameters() if p.requires_grad]
    opt = torch.optim.AdamW(params, lr=args.lr, weight_decay=5e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=args.epochs)
    loss_fn = torch.nn.CrossEntropyLoss(label_smoothing=0.05)

    train_dl = DataLoader(CropDataset(train_s, spec.scale, True), batch_size=args.batch,
                          sampler=weighted_sampler(train_s), drop_last=True)
    val_dl = DataLoader(CropDataset(val_s, spec.scale, False), batch_size=64)
    val_labels = np.array([s.label for s in val_s])

    def score():
        p = p_real(model, val_dl)
        e, _ = metrics.eer(p, val_labels)
        return e, metrics.apcer_bpcer(p, val_labels, 0.5)["acer"]

    best_eer, best_acer = score()
    print(f"  pretrained      val EER {best_eer:.1%}  ACER@0.5 {best_acer:.1%}")
    history = [{"epoch": 0, "val_eer": best_eer, "val_acer": best_acer}]
    filename = WEIGHT_FILES[spec.name][0]
    torch.save(model.state_dict(), os.path.join(args.out, filename))  # baseline = fallback

    for epoch in range(1, args.epochs + 1):
        model.train()
        if args.freeze:  # keep frozen BatchNorm statistics frozen too
            for name, m in model.named_modules():
                if isinstance(m, (torch.nn.BatchNorm1d, torch.nn.BatchNorm2d)) and not name.startswith(HEAD_PREFIXES):
                    m.eval()
        total = 0.0
        for x, y in train_dl:
            opt.zero_grad()
            loss = loss_fn(model(x), y)
            loss.backward()
            opt.step()
            total += loss.item() * len(y)
        sched.step()

        val_eer, val_acer = score()
        history.append({"epoch": epoch, "train_loss": total / (len(train_dl) * args.batch),
                        "val_eer": val_eer, "val_acer": val_acer})
        better = (val_eer, val_acer) < (best_eer, best_acer)
        print(f"  epoch {epoch:2d}  loss {history[-1]['train_loss']:.3f}  "
              f"val EER {val_eer:.1%}  ACER@0.5 {val_acer:.1%}{'  *' if better else ''}")
        if better:
            best_eer, best_acer = val_eer, val_acer
            torch.save(model.state_dict(), os.path.join(args.out, filename))

    return {"best_val_eer": best_eer, "best_val_acer": best_acer, "history": history}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", default=os.path.join(ROOT, "data", "antispoof"))
    ap.add_argument("--val-sessions", nargs="+", required=True, help="held-out sessions")
    ap.add_argument("--weights-dir", default=os.path.join(ROOT, "models", "antispoof"))
    ap.add_argument("--out", required=True)
    ap.add_argument("--epochs", type=int, default=12)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--freeze", action="store_true", help="train only the final layers")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    random.seed(args.seed); np.random.seed(args.seed); torch.manual_seed(args.seed)
    os.makedirs(args.out, exist_ok=True)

    samples, skipped = dataset.load(args.data)
    train_s, val_s = dataset.split_by_session(samples, set(args.val_sessions))
    for name, part in (("train", train_s), ("val", val_s)):
        labels = {l: sum(s.label == l for s in part) for l in dataset.LABELS}
        print(f"{name}: {labels}")
        if labels["real"] == 0 or labels["real"] == len(part):
            sys.exit(f"The {name} split needs both real and attack frames.")

    log = {"args": vars(args), "skipped": skipped}
    for spec in MODELS:
        print(f"\n== {spec.name} ==")
        log[spec.name] = train_one(spec, train_s, val_s, args)
    with open(os.path.join(args.out, "train_log.json"), "w", encoding="utf-8") as f:
        json.dump(log, f, indent=2)
    print(f"\nSaved best weights to {args.out}. Next: export_onnx.py --weights-dir {args.out} --out-dir {args.out}")


if __name__ == "__main__":
    main()
