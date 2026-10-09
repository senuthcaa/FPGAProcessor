# Timing constraints for the Task 4 top level (top_level_memory)

# 50 MHz board clock (MAX10_CLK1_50 on PIN_P11)
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# 10 Hz processor clock: the clk_10hz register in top_level_memory toggles every 2500000 CLOCK_50 cycles
create_generated_clock -name clk_10hz -source [get_ports {CLOCK_50}] -divide_by 5000000 [get_registers {clk_10hz}]

derive_clock_uncertainty

# The PC (10 Hz) addresses the instruction ROM (50 MHz), and the ROM output goes back into the processor (10 Hz).
# The PC only changes on a 10 Hz edge and the ROM output is not used until the next one, 100 ms later,
# so neither crossing needs a 20 ns check
set_false_path -from [get_clocks {clk_10hz}] -to [get_clocks {CLOCK_50}]
set_false_path -from [get_clocks {CLOCK_50}] -to [get_clocks {clk_10hz}]

# The switches and keys are read by synchronising registers, and the LEDs and displays are only looked at by people
set_false_path -from [get_ports {SW[*] KEY[*]}]
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
