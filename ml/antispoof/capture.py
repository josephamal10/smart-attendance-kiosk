"""
Record a small anti-spoofing dataset with your own webcam.

    python ml/antispoof/capture.py --session amal-office-day

Keys:  r = record REAL (you, live)       p = record PRINT attack (printed photo)
       v = record REPLAY attack (phone / laptop screen showing a face)
       space = stop recording            q = quit

Every 5th frame is saved while recording, to data/antispoof/<label>/<session>_<n>.jpg.
Tips for a useful set:
  * Several sessions: different rooms, lighting (window, lamp, dark), distances, glasses.
  * Attacks should be *good* attacks: bright phone screen, full-screen video, the print
    held still and flat — that's what a real cheater would do.
  * Use other people's photos for attacks too, not only your own.
  * Aim for 200+ frames per label across 3+ sessions.
"""
import argparse
import os
import re
import sys

import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KEYS = {ord("r"): "real", ord("p"): "print", ord("v"): "replay"}
SAVE_EVERY = 5


def next_index(folder: str, session: str) -> int:
    pat = re.compile(rf"^{re.escape(session)}_(\d+)\.jpg$")
    nums = [int(m.group(1)) for f in os.listdir(folder) if (m := pat.match(f))]
    return max(nums, default=-1) + 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--session", required=True, help="e.g. amal-office-day (no underscores)")
    ap.add_argument("--out", default=os.path.join(ROOT, "data", "antispoof"))
    ap.add_argument("--camera", type=int, default=0)
    args = ap.parse_args()
    if "_" in args.session:
        sys.exit("Use dashes, not underscores, in --session (underscore separates the frame number).")

    for label in KEYS.values():
        os.makedirs(os.path.join(args.out, label), exist_ok=True)

    cap = cv2.VideoCapture(args.camera, cv2.CAP_DSHOW if os.name == "nt" else cv2.CAP_ANY)
    if not cap.isOpened():
        sys.exit("Could not open the camera.")

    recording, frame_no = None, 0
    counts = {label: 0 for label in KEYS.values()}
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_no += 1

        if recording and frame_no % SAVE_EVERY == 0:
            folder = os.path.join(args.out, recording)
            n = next_index(folder, args.session)
            cv2.imwrite(os.path.join(folder, f"{args.session}_{n:04d}.jpg"), frame)
            counts[recording] += 1

        view = frame.copy()
        status = f"REC {recording.upper()}" if recording else "paused  (r/p/v to record, q to quit)"
        color = (0, 0, 255) if recording else (200, 200, 200)
        cv2.putText(view, status, (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.0, color, 2)
        cv2.putText(view, "  ".join(f"{k}:{v}" for k, v in counts.items()), (20, 80),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
        cv2.imshow("anti-spoof capture", view)

        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        if key == ord(" "):
            recording = None
        elif key in KEYS:
            recording = KEYS[key]

    cap.release()
    cv2.destroyAllWindows()
    print("Saved this run:", counts)


if __name__ == "__main__":
    main()
