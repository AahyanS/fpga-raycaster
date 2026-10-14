#!/usr/bin/env python3
"""Check that the USB video stream matches the VGA picture.

Usage: check_stream.py <dir>   (dir holds frame_0000.hex and uart_*.hex)
Downsamples the VGA frame the same way the hardware does (every 4th pixel,
RRRGGGBB, 0xFF reserved) and compares it with the last streamed frame.
"""
import glob
import sys

d = sys.argv[1]
vga = [int(l, 16) for l in open(f"{d}/frame_0000.hex")]
assert len(vga) == 640 * 480, f"VGA frame has {len(vga)} pixels"

expected = []
for y in range(0, 480, 4):
    for x in range(0, 640, 4):
        p = vga[y * 640 + x]
        r, g, b = p >> 8, (p >> 4) & 15, p & 15
        v = ((r >> 1) << 5) | ((g >> 1) << 2) | (b >> 2)
        expected.append(0xFE if v == 0xFF else v)

streams = sorted(glob.glob(f"{d}/uart_*.hex"))
assert len(streams) >= 2, "expected at least two streamed frames"
got = [int(l, 16) for l in open(streams[-1])]
bad = sum(a != b for a, b in zip(got, expected))
print(f"{streams[-1]}: {len(got)} bytes, {bad} mismatches")
sys.exit(0 if len(got) == 160 * 120 and bad == 0 else 1)
