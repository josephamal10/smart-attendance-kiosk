# Face anti-spoofing

The kiosk's blink check stops a printed photo, but not a phone replaying a video of
someone blinking. This adds a **presentation attack detection (PAD)** model in front of
face matching: if the camera is looking at a print or a screen, check-in and face
registration are refused.

## Model
Two small CNNs from Minivision's
[Silent-Face-Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing)
(Apache 2.0), averaged:

| model | input | sees | params |
|---|---|---|---|
| MiniFASNetV2 | 80×80 BGR | face ×2.7 — skin texture, print grain, moiré | ~0.4 M |
| MiniFASNetV1SE | 80×80 BGR | face ×4.0 — phone bezels, hands, screen edges | ~0.4 M |

Output: 3 classes (print, **real**, replay); the server uses P(real).

## Pipeline
```
capture.py   webcam → data/antispoof/{real,print,replay}/<session>_<n>.jpg
evaluate.py  APCER / BPCER / ACER / EER / AUC + score histogram + tuned threshold
finetune.py  domain adaptation on your own captures (session-disjoint split,
             weighted sampling, detector-jitter + lighting + JPEG augmentation)
export_onnx.py  PyTorch → ONNX fp32 → ONNX int8 (static, calibrated) + parity check
services/antispoof_service.py   onnxruntime inference in the API (no PyTorch at runtime)
```

## Results so far
**Conversion** (`export_onnx.py`, 100 real faces):

| | max \|ΔP\| vs PyTorch | size | CPU latency / face |
|---|---|---|---|
| ONNX fp32 | 1.6e-6 | 1.74 MB | ~4 ms |
| ONNX int8 (QDQ, per-channel) | 0.143 | 0.66 MB | ~5 ms |
| ONNX int8 (QOperator) | 0.209 | — | ~4 ms |

Int8 made the files 2.6× smaller, but it wasn't faster on CPU for these tiny depthwise CNNs and
it moved scores noticeably, **so the server runs fp32**. Measuring before deciding mattered here.

**Face-box calibration.** The models were trained on loose RetinaFace boxes; dlib's
box is tight. On 126 real webcam captures (dlib era), the lowest P(real) was:

| box | min P(real) | mean |
|---|---|---|
| raw dlib box | 0.685 | 0.972 |
| +10% width, +25% height (mostly upward) ← used | **0.859** | 0.971 |
| +20% / +30% | 0.697 | 0.958 |

When face detection moved from dlib to YuNet, that framing was carried over by measuring
where the tuned box sits relative to YuNet's box on 1,743 LFW faces both detectors found
(`calibrate_box.py`): offset (-0.141, -0.050) and scale (1.223, 1.039) of the YuNet box, with an
interquartile range of only ~0.1, so the mapping is stable.

**Bona fide error (BPCER).** On 126 real captures at threshold 0.5: **0.0%**
([report](../../reports/antispoof/pretrained-real-only/), dlib-era boxes; those captures were
deleted when faces were reset, so re-run `evaluate.py` on the new registrations).
Anti-spoofing adds **~7 ms** per check-in.

**Attack error (APCER): not measured yet.** That needs real attack recordings, step 1 below.
Until then, the honest claim is "doesn't reject real users", not "stops attacks".

## Next steps
```bash
# 1. Record ~3 sessions in different places/lighting: you live (r), a printed photo (p),
#    a phone/laptop screen showing a face (v). Use other people's photos too.
python ml/antispoof/capture.py --session amal-office-day

# 2. Measure the pretrained model and pick a threshold that rejects ≤5% of real users
python ml/antispoof/evaluate.py --name pretrained --max-bpcer 0.05

# 3. Fine-tune on all but one session, evaluate on the held-out one
python ml/antispoof/finetune.py --val-sessions amal-lab-night --out runs/ft1 --freeze
python ml/antispoof/export_onnx.py --weights-dir runs/ft1 --out-dir runs/ft1
python ml/antispoof/evaluate.py --model-dir runs/ft1 --name ft1 --test-sessions amal-lab-night

# 4. If it's better, ship it: copy runs/ft1/*.fp32.onnx into models/antispoof/,
#    then save its threshold for the server
python ml/antispoof/evaluate.py --name ft1-final --save-threshold
```

Metric definitions (ISO/IEC 30107-3) are in [metrics.py](metrics.py). APCER is reported for
the **worst** attack type, because a kiosk is only as strong as its weakest attack.

## Settings (`.env`)
`ANTISPOOF_ENABLED` (true), `ANTISPOOF_THRESHOLD` (overrides `models/antispoof/threshold.json`,
default 0.5), `ANTISPOOF_VARIANT` (fp32 | int8).
