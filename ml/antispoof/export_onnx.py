"""
PyTorch → ONNX (fp32) → ONNX (int8), then check the converted models agree.

    python ml/antispoof/export_onnx.py                      # pretrained weights
    python ml/antispoof/export_onnx.py --weights-dir runs/x # fine-tuned weights

Measured on this project: fp32 ONNX matches PyTorch to ~1e-6; int8 is 2.6x smaller
but no faster on CPU for these 80x80 depthwise CNNs and shifts P(real) by up to ~0.14,
so the server uses fp32. Int8 is still exported for size-constrained devices.

Int8 uses *static* quantization: we feed real face crops through the model to
measure each layer's value range (calibration), so convolutions run in int8 too.
(Dynamic quantization only covers MatMul/Linear layers — almost nothing in a CNN.)
"""
import argparse
import glob
import os
import sys
import time
from collections import OrderedDict

import cv2
import numpy as np
import torch

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)

from ml.antispoof.minifasnet import MiniFASNetV2, MiniFASNetV1SE  # noqa: E402
from services.antispoof_service import MODELS, crop_face, to_input, _softmax  # noqa: E402

WEIGHT_FILES = {
    "MiniFASNetV2":   ("2.7_80x80_MiniFASNetV2.pth",   MiniFASNetV2),
    "MiniFASNetV1SE": ("4_0_0_80x80_MiniFASNetV1SE.pth", MiniFASNetV1SE),
}


WEIGHTS_URL = ("https://github.com/minivision-ai/Silent-Face-Anti-Spoofing/raw/master/"
               "resources/anti_spoof_models/{}")


def load_torch(name: str, weights_dir: str) -> torch.nn.Module:
    filename, ctor = WEIGHT_FILES[name]
    path = os.path.join(weights_dir, filename)
    if not os.path.exists(path):
        import urllib.request
        print(f"Downloading pretrained {filename} (Apache 2.0, minivision-ai)...")
        os.makedirs(weights_dir, exist_ok=True)
        urllib.request.urlretrieve(WEIGHTS_URL.format(filename), path)
    model = ctor(conv6_kernel=(5, 5))
    state = torch.load(path, map_location="cpu", weights_only=True)
    # Weights saved from nn.DataParallel have every key prefixed with "module."
    state = OrderedDict((k.removeprefix("module."), v) for k, v in state.items())
    model.load_state_dict(state)
    return model.eval()


def calibration_crops(image_glob: str, scale: float, limit: int) -> list[np.ndarray]:
    """Face crops for int8 calibration and parity checks, located with YuNet."""
    from services.antispoof_service import box_from_yunet
    from services.face_engine import get_engine

    crops = []
    for path in sorted(glob.glob(image_glob))[:limit]:
        img = cv2.imread(path, cv2.IMREAD_COLOR)
        faces = get_engine().detect(img) if img is not None else []
        if len(faces) == 1:
            crops.append(crop_face(img, box_from_yunet(faces[0].box), scale))
    return crops


class _Reader:
    """Feeds calibration batches to onnxruntime's quantizer."""
    def __init__(self, input_name: str, crops: list[np.ndarray]):
        self._it = iter([{input_name: to_input([c])} for c in crops])

    def get_next(self):
        return next(self._it, None)


def bench(sess, x: np.ndarray, runs: int = 200) -> float:
    name = sess.get_inputs()[0].name
    for _ in range(10):
        sess.run(None, {name: x})
    t = time.perf_counter()
    for _ in range(runs):
        sess.run(None, {name: x})
    return (time.perf_counter() - t) / runs * 1000


def main():
    import onnxruntime as ort
    from onnxruntime.quantization import (
        CalibrationMethod, QuantFormat, QuantType, quantize_static, quant_pre_process)

    ap = argparse.ArgumentParser()
    ap.add_argument("--weights-dir", default=os.path.join(ROOT, "models", "antispoof"))
    ap.add_argument("--out-dir", default=os.path.join(ROOT, "models", "antispoof"))
    ap.add_argument("--calib-glob", default=os.path.join(ROOT, "face_images", "*.jpg"),
                    help="real face photos used to calibrate int8 ranges")
    ap.add_argument("--calib-limit", type=int, default=100)
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    for spec in MODELS:
        print(f"\n== {spec.name} (crop scale {spec.scale}) ==")
        model = load_torch(spec.name, args.weights_dir)
        fp32 = os.path.join(args.out_dir, f"{spec.name}.fp32.onnx")
        int8 = os.path.join(args.out_dir, f"{spec.name}.int8.onnx")

        torch.onnx.export(
            model, torch.zeros(1, 3, 80, 80), fp32,
            input_names=["input"], output_names=["logits"],
            dynamic_axes={"input": {0: "batch"}, "logits": {0: "batch"}},
            opset_version=17, dynamo=False,
        )

        crops = calibration_crops(args.calib_glob, spec.scale, args.calib_limit)
        if len(crops) < 10:
            sys.exit(f"Need at least 10 calibration faces, found {len(crops)} in {args.calib_glob}")
        print(f"calibration faces: {len(crops)}")

        prepped = fp32.replace(".fp32.", ".prep.")
        quant_pre_process(fp32, prepped)  # fold BatchNorm, infer shapes
        quantize_static(
            prepped, int8, _Reader("input", crops),
            quant_format=QuantFormat.QDQ,
            activation_type=QuantType.QUInt8, weight_type=QuantType.QInt8,
            per_channel=True, calibrate_method=CalibrationMethod.Percentile,
        )
        os.remove(prepped)

        # ── Parity: does each converted model agree with PyTorch? ──
        x = to_input(crops)
        with torch.no_grad():
            p_torch = torch.softmax(model(torch.from_numpy(x)), dim=1).numpy()
        s32 = ort.InferenceSession(fp32, providers=["CPUExecutionProvider"])
        s8  = ort.InferenceSession(int8, providers=["CPUExecutionProvider"])
        p32 = _softmax(s32.run(None, {"input": x})[0])
        p8  = _softmax(s8.run(None, {"input": x})[0])

        print(f"fp32 vs torch: max |diff p| = {np.abs(p32 - p_torch).max():.2e}")
        print(f"int8 vs torch: max |diff p(real)| = {np.abs(p8[:, 1] - p_torch[:, 1]).max():.3f}, "
              f"same top class {np.mean(p8.argmax(1) == p_torch.argmax(1)) * 100:.1f}%")
        one = x[:1]
        print(f"size: fp32 {os.path.getsize(fp32) / 1e6:.2f} MB -> int8 {os.path.getsize(int8) / 1e6:.2f} MB")
        print(f"latency (1 face, CPU): fp32 {bench(s32, one):.2f} ms -> int8 {bench(s8, one):.2f} ms")


if __name__ == "__main__":
    main()
