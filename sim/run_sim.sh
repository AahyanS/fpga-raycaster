#!/usr/bin/env bash
# Simulate the full design.
#   ./sim/run_sim.sh          one still frame -> sim/out/frame_0000.png
#   ./sim/run_sim.sh demo     152-frame walkthrough -> sim/out/walkthrough.gif (~5 min)
#   ./sim/run_sim.sh test     self-checking tests (divider + USB stream vs VGA)
# Needs: verilator 5+ (fast) or iverilog, and python3 with Pillow.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out

build() {
    if command -v verilator >/dev/null; then
        verilator --binary --timing -O3 -Wno-fatal -Wno-WIDTH -Wno-UNUSED \
            --top-module tb_raycaster -Mdir out/obj tb_raycaster.v ../rtl/*.v >/dev/null
        SIM="./obj/Vtb_raycaster"
    else
        iverilog -g2005 -o out/tb.vvp tb_raycaster.v ../rtl/*.v
        SIM="vvp -n tb.vvp"
    fi
}

case "${1:-still}" in
  test)
    iverilog -g2005 -o out/tb_udiv tb_udiv.v ../rtl/udiv.v
    vvp -n out/tb_udiv | grep -q "PASS" && echo "udiv: PASS"
    build
    printf "12 0 0\n1 0 1\n" > out/stream.txt
    (cd out && rm -f frame_*.hex uart_*.hex && $SIM +script=stream.txt >/dev/null)
    python3 check_stream.py out && echo "stream: PASS"
    ;;
  demo)
    build
    (cd out && rm -f frame_* && $SIM +script=../demo_script.txt +sprint)
    python3 hex_to_png.py out out/walkthrough.gif
    ;;
  *)
    build
    echo "1 0 1" > out/still.txt
    (cd out && rm -f frame_* && $SIM +script=still.txt)
    python3 hex_to_png.py out
    ;;
esac
