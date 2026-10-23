"""
Turn the README screenshots into a short animated tour (docs/demo.gif) with crossfades.

    python scripts/screenshots.py      # first, to refresh docs/screenshots
    python scripts/make_demo_gif.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "docs", "screenshots")
OUT = os.path.join(ROOT, "docs", "demo.gif")

# (screenshot, seconds on screen) — the story: walk up, check in, see your dashboard, admin side
TOUR = [("lock", 2.6), ("lock-tamil", 2.0), ("kiosk", 2.6), ("my-attendance", 3.2), ("overview", 2.4),
        ("register", 2.4), ("analytics", 2.4), ("requests", 2.2), ("notices", 2.0), ("settings-dark", 2.2)]
WIDTH, HEIGHT = 960, 600   # 16:10 like the screenshots
FADE_FRAMES, FADE_MS = 4, 60


def load(name: str) -> Image.Image:
    img = Image.open(os.path.join(SHOTS, f"{name}.png")).convert("RGB")
    # Tall pages (My dashboard): keep the top 16:10 part
    want_h = round(img.width * HEIGHT / WIDTH)
    if img.height > want_h:
        img = img.crop((0, 0, img.width, want_h))
    return img.resize((WIDTH, HEIGHT), Image.LANCZOS)


def main() -> None:
    slides = [(load(n), secs) for n, secs in TOUR]
    frames, durations = [], []
    for i, (img, secs) in enumerate(slides):
        frames.append(img)
        durations.append(int(secs * 1000))
        nxt = slides[(i + 1) % len(slides)][0]
        for k in range(1, FADE_FRAMES + 1):
            frames.append(Image.blend(img, nxt, k / (FADE_FRAMES + 1)))
            durations.append(FADE_MS)
    # Each frame gets its own palette: the dark lock screen and the light admin pages share
    # almost no colours, so one palette for all would wash the admin pages out
    gif = [f.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for f in frames]
    gif[0].save(OUT, save_all=True, append_images=gif[1:], duration=durations, loop=0, optimize=True)
    print(f"{OUT}: {len(gif)} frames, {os.path.getsize(OUT) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
