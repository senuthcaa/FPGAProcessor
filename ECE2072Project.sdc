# Timing constraints for all three top levels: Task 2 (top_level), Task 3 (top_level_extension) and Task 4 (top_level_memory)
# Each block only runs when the ports it constrains exist in the current top level, so changing TOP_LEVEL_ENTITY
# does not leave unmatched filters (332174) or constraints on empty collections (332049)

if {[get_collection_size [get_ports -nowarn {CLOCK_50}]] > 0} {
	# Task 4: 50 MHz board clock (MAX10_CLK1_50 on PIN_P11)
	create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

	# 10 Hz processor clock: the clk_10hz register toggles every 2500000 CLOCK_50 cycles, so its real period is 100 ms
	# The Timing Analyzer ignores any clock with a period over 2147483 ns (332007), so it is constrained as a 1 ms clock
	# (divide by 50000) instead, which is stricter than the real clock
	create_generated_clock -name clk_10hz -source [get_ports {CLOCK_50}] -divide_by 50000 [get_registers {clk_10hz}]

	# The PC (10 Hz) addresses the instruction ROM (50 MHz), and the ROM output goes back into the processor (10 Hz)
	# The PC only changes on a 10 Hz edge and the ROM output is not used until the next one, 100 ms later,
	# so neither crossing needs a 20 ns check
	set_false_path -from [get_clocks {clk_10hz}] -to [get_clocks {CLOCK_50}]
	set_false_path -from [get_clocks {CLOCK_50}] -to [get_clocks {clk_10hz}]
} elseif {[get_collection_size [get_ports -nowarn {KEY[1]}]] > 0} {
	# Task 2 and Task 3: the processor is clocked by the KEY[1] push button, through ~KEY[1]
	# 1 us is far faster than the button can be pressed, so the constraint is stricter than the real clock
	create_clock -name KEY1 -period 1000.000 [get_ports {KEY[1]}]
}

derive_clock_uncertainty

# The switches and the reset key are read by registers, and the LEDs and displays are only looked at by people
# (-nowarn because Task 2 has no HEX0 to HEX4)
set_false_path -from [get_ports -nowarn {SW[*] KEY[0]}]
set_false_path -to [get_ports -nowarn {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
