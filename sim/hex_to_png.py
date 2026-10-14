#!/usr/bin/env python3
"""Turn simulator frame dumps (one 12-bit RGB hex pixel per line) into PNGs / a GIF."""
import sys, pathlib
from PIL import Image

def load(path, w=640, h=480):
    vals = [int(l, 16) for l in open(path) if l.strip() and 'x' not in l.lower()]
    assert len(vals) == w * h, f"{path}: {len(vals)} pixels"
    img = Image.new("RGB", (w, h))
    img.putdata([(((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17) for v in vals])
    return img

if __name__ == "__main__":
    files = sorted(pathlib.Path(sys.argv[1]).glob("frame_*.hex"))
    frames = [load(f) for f in files]
    for f, im in zip(files, frames):
        im.save(f.with_suffix(".png"))
    if len(frames) > 1 and len(sys.argv) > 2:
        frames[0].save(sys.argv[2], save_all=True, append_images=frames[1:], duration=50, loop=0)
    print(f"converted {len(frames)} frames")
