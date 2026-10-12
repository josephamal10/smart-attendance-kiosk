# ML benchmarks

## Face verification: dlib vs YuNet + SFace
`python ml/face_benchmark.py`: LFW, 6,000 pairs (3,000 same person, 3,000 different), standard
10-fold protocol (each fold's threshold is tuned on the other 9). Raw numbers:
[reports/face_benchmark.json](../reports/face_benchmark.json).

| | dlib (face_recognition) | **YuNet + SFace** (used) |
|---|---|---|
| Accuracy | 98.52% ± 0.63 | **99.10% ± 0.40** |
| Genuine accepted when 1% of impostors pass (TAR@FAR 1%) | 98.03% | **98.93%** |
| Genuine accepted when 0.1% of impostors pass (TAR@FAR 0.1%) | 92.53% | **98.13%** |
| Images where no face was found | 33 | **0** |
| Detect + embed, one 1920×1080 webcam frame (CPU) | 1,102 ms | **35 ms (31× faster)** |
| Install | dlib C++ build | ships inside OpenCV |

The biggest gap is at strict settings (TAR@FAR 0.1%): that is the regime a security system
actually runs in.

### Choosing the match threshold
SFace cosine similarity on LFW pairs:

| threshold | genuine accepted | impostors accepted |
|---|---|---|
| 0.300 | 98.87% | 0.733% (22 / 3000) |
| 0.363 (OpenCV's suggested) | 98.00% | 0.100% (3 / 3000) |
| 0.400 | 97.03% | 0.033% (1 / 3000) |
| **0.450 (used)** | 95.17% | **0% (0 / 3000)**; highest impostor scored 0.412 |
| 0.500 | 91.90% | 0% |

Why 0.45: the kiosk compares a photo with the **best of ~30** registered images. That helps
genuine users (their scores at the same camera are far higher than LFW's cross-year pairs), but
it also gives an impostor 30 chances. So the threshold errs strict. Override with
`FACE_MATCH_THRESHOLD` if real employees are being rejected.

## Anti-spoofing
See [antispoof/README.md](antispoof/README.md).
