# program.tcl -- flash the bitstream over USB (volatile; lost on power-off).
#   vivado -mode batch -source scripts/program.tcl [-tclargs nexys]
set board [expr {[llength $argv] > 0 ? [lindex $argv 0] : "basys3"}]
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a*] 0]
current_hw_device $dev
set_property PROGRAM.FILE build/$board/raycaster_$board.bit $dev
program_hw_devices $dev
puts "Programmed $dev"
