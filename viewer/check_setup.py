"""Quick check that this PC can run the viewer."""
import sys
ok = True
for mod in ("serial", "PIL", "tkinter"):
    try:
        __import__(mod)
    except ImportError:
        ok = False
        print("MISSING", mod)
if ok:
    from serial.tools import list_ports
    ports = [(p.device, hex(p.vid or 0), p.description) for p in list_ports.comports()]
    print("DEPS OK", sys.version.split()[0], ports)
