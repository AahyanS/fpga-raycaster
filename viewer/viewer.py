#!/usr/bin/env python3
"""Live viewer for the FPGA raycaster -- no VGA monitor needed.

The Basys 3 streams its rendered picture over the same USB cable used for
programming (160x120, 8-bit color, ~12 fps). This window shows it, and your
laptop keyboard drives the game:

    Arrow keys / WASD   move and turn
    Shift               sprint
    Esc                 quit

The board's own buttons keep working at the same time.
Needs: Python 3 with pyserial and Pillow (both ship with Anaconda).
"""
import sys
import threading
import time
import tkinter as tk

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("pyserial is missing. Install it with:  pip install pyserial")
from PIL import Image, ImageTk

W, H = 160, 120
SCALE = 5                      # window is 800x600
BAUD = 3_000_000

# RRRGGGBB -> (r, g, b) lookup table
LUT = []
for v in range(256):
    LUT += [((v >> 5) & 7) * 255 // 7, ((v >> 2) & 7) * 255 // 7, (v & 3) * 85]
LUT = bytes(LUT)


def find_port():
    if len(sys.argv) > 1:
        return sys.argv[1]
    ports = list(list_ports.comports())
    # The Basys 3 / Nexys A7 use an FTDI chip (USB vendor id 0x0403).
    ftdi = [p for p in ports if p.vid == 0x0403]
    if ftdi:
        return sorted(ftdi, key=lambda p: p.device)[-1].device
    names = ", ".join(p.device for p in ports) or "none"
    sys.exit(f"Could not find the board's serial port (ports seen: {names}).\n"
             "Is the board plugged in and programmed? You can also pass the port, "
             "e.g.  python viewer.py COM4")


class Viewer:
    def __init__(self, port):
        self.ser = serial.Serial(port, BAUD, timeout=0.5)
        self.ser.reset_input_buffer()
        self.frame = None
        self.frames = 0
        self.lock = threading.Lock()
        self.running = True
        self.keys = set()

        self.root = tk.Tk()
        self.root.title(f"FPGA Raycaster  ({port})")
        self.root.configure(bg="black")
        self.label = tk.Label(self.root, bg="black")
        self.label.pack()
        self.status = tk.Label(self.root, text="waiting for the board...", fg="#aaa",
                               bg="black", font=("Consolas", 10))
        self.status.pack(fill="x")
        self.root.bind("<KeyPress>", lambda e: self.keys.add(e.keysym.lower()))
        self.root.bind("<KeyRelease>", lambda e: self.keys.discard(e.keysym.lower()))
        self.root.bind("<Escape>", lambda e: self.close())
        self.root.bind("<FocusOut>", lambda e: self.keys.clear())
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        threading.Thread(target=self.reader, daemon=True).start()
        self.last_fps_t, self.last_fps_n, self.fps = time.time(), 0, 0.0
        self.tick()

    def reader(self):
        """Find the 0xFF marker, then read one 19,200-byte frame, forever."""
        n = W * H
        while self.running:
            try:
                b = self.ser.read(1)
                if b != b"\xff":
                    continue
                data = self.ser.read(n)
            except serial.SerialException:
                break
            if len(data) == n and b"\xff" not in data:
                img = Image.frombytes("P", (W, H), data)
                img.putpalette(LUT)
                with self.lock:
                    self.frame = img
                    self.frames += 1

    def key_byte(self):
        k = self.keys
        up = bool(k & {"up", "w"})
        down = bool(k & {"down", "s"})
        left = bool(k & {"left", "a"})
        right = bool(k & {"right", "d"})
        sprint = bool(k & {"shift_l", "shift_r"})
        return 0xA0 | (sprint << 4) | (up << 3) | (down << 2) | (left << 1) | right

    def tick(self):
        if not self.running:
            return
        try:
            self.ser.write(bytes([self.key_byte()]))
        except serial.SerialException:
            self.status.config(text="board disconnected")
        with self.lock:
            img, count = self.frame, self.frames
            self.frame = None
        if img is not None:
            big = img.convert("RGB").resize((W * SCALE, H * SCALE), Image.NEAREST)
            self.photo = ImageTk.PhotoImage(big)
            self.label.config(image=self.photo)
        now = time.time()
        if now - self.last_fps_t >= 1.0:
            self.fps = (count - self.last_fps_n) / (now - self.last_fps_t)
            self.last_fps_t, self.last_fps_n = now, count
            if count:
                self.status.config(text=f"{self.fps:4.1f} fps   frames {count}   "
                                        "arrows/WASD move, Shift sprint, Esc quit")
        self.root.after(30, self.tick)

    def close(self):
        self.running = False
        try:
            self.ser.close()
        except Exception:
            pass
        self.root.destroy()


if __name__ == "__main__":
    Viewer(find_port()).root.mainloop()
