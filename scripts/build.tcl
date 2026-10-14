# build.tcl -- one-command Vivado build (non-project mode).
#   vivado -mode batch -source scripts/build.tcl                 (Basys 3)
#   vivado -mode batch -source scripts/build.tcl -tclargs nexys  (Nexys A7-100T)
# Run from the repository root. Output goes to build/<board>/.
set board [expr {[llength $argv] > 0 ? [lindex $argv 0] : "basys3"}]

switch $board {
    basys3 { set part xc7a35tcpg236-1;  set top top_basys3;   set xdc constraints/basys3.xdc }
    nexys  { set part xc7a100tcsg324-1; set top top_nexys_a7; set xdc constraints/nexys_a7.xdc }
    default { puts "unknown board '$board' (use basys3 or nexys)"; exit 1 }
}

set out build/$board
file mkdir $out

read_verilog [glob rtl/*.v]
read_xdc $xdc

synth_design -top $top -part $part
opt_design
place_design
phys_opt_design
route_design

report_utilization    -file $out/utilization.rpt
report_timing_summary -file $out/timing.rpt
write_bitstream -force $out/raycaster_$board.bit

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "\n=== Done: $out/raycaster_$board.bit   worst setup slack = $wns ns ==="
if {$wns < 0} { puts "WARNING: timing not met, see $out/timing.rpt" }
