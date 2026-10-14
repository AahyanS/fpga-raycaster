# Convenience targets. Simulation needs iverilog/verilator + python3 (Pillow);
# hardware targets need Vivado on your PATH.
BOARD ?= basys3

.PHONY: test sim demo lut bitstream program play clean

test:            ## self-checking tests (divider, USB stream vs VGA)
	bash sim/run_sim.sh test

sim:             ## render one frame to sim/out/frame_0000.png
	bash sim/run_sim.sh

demo:            ## render the walkthrough GIF
	bash sim/run_sim.sh demo

lut:             ## regenerate rtl/trig_lut.v
	python3 scripts/gen_trig_lut.py

bitstream:       ## build build/$(BOARD)/raycaster_$(BOARD).bit
	vivado -mode batch -nojournal -nolog -source scripts/build.tcl -tclargs $(BOARD)

program:         ## load the bitstream onto the board
	vivado -mode batch -nojournal -nolog -source scripts/program.tcl -tclargs $(BOARD)

play: program    ## program the board and open the laptop viewer
	python3 viewer/viewer.py

clean:
	rm -rf build sim/out .Xil *.jou *.log
