`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment
This file contains Verilog code to implement the DE10-Lite top level for Task 2,
    which connects the simple x72 processor to the switches, keys, LEDs and HEX5.

Please enter your name and student ID:
-Senuth 36180513
-

*/
module top_level (
	input wire [9:0] SW,
	input wire [1:0] KEY,

	output wire [9:0] LEDR,
	output reg [6:0] HEX5
);

	//SW[8:0] -> processor din
	//~KEY[0] -> synchronous processor rst
	//~KEY[1] -> processor clk
	//processor enable -> 1'b1
	//bus[9:0] -> LEDR[9:0]
	//tick_FSM -> HEX5

	//tick states, from components.v
	localparam
		DIN_READ = 4'b0001,
		BUS_WRITE_ONE = 4'b0010,
		OPERATE_ALU = 4'b0100,
		BUS_WRITE_TWO = 4'b1000;

	wire [15:0] bus;
	wire [3:0] tick;

	//instantiate task 2 processor
	simple_proc proc_inst (
		.clk(~KEY[1]),
		.rst(~KEY[0]),
		.enable(1'b1),
		.din(SW[8:0]),
		.bus(bus),
		.tick_FSM(tick),

		//testbench outputs are not required on hardware
		.R0(),
		.R1(),
		.R2(),
		.R3(),
		.R4(),
		.R5(),
		.R6(),
		.R7()
	);

	//display bottom 10 bits of processor bus on LEDs
	assign LEDR = bus[9:0];

	//display current tick on HEX5, de10-lite seven-segment displays are active-low
	always @(*) begin
		case (tick)
			DIN_READ : HEX5 = 7'b1111001; //1
			BUS_WRITE_ONE : HEX5 = 7'b0100100; //2
			OPERATE_ALU : HEX5 = 7'b0110000; //3
			BUS_WRITE_TWO : HEX5 = 7'b0011001; //4
			default : HEX5 = 7'b1111111; //blank
		endcase
	end

endmodule
/*
Info: Running Quartus Prime Analysis & Synthesis
	Info: Version 18.1.0 Build 625 09/12/2018 SJ Lite Edition
	Info: Processing started: Fri Oct 09 13:10:28 2026
Info: Command: quartus_map --read_settings_files=on --write_settings_files=off ECE2072_project -c ECE2072_project
Warning (18236): Number of processors has not been specified which may cause overloading on shared machines.  Set the global assignment NUM_PARALLEL_PROCESSORS in your QSF to an appropriate value for best performance.
Info (20030): Parallel compilation is enabled and will use 8 of the 8 processors detected
Info (12021): Found 1 design units, including 1 entities, in source file top_level.v
	Info (12023): Found entity 1: top_level
Info (12021): Found 1 design units, including 1 entities, in source file proc_tb.v
	Info (12023): Found entity 1: proc_tb
Info (12021): Found 1 design units, including 1 entities, in source file proc_extension_tb.v
	Info (12023): Found entity 1: proc_extension_tb
Info (12021): Found 1 design units, including 1 entities, in source file proc_extension.v
	Info (12023): Found entity 1: extended_proc
Info (12021): Found 1 design units, including 1 entities, in source file proc.v
	Info (12023): Found entity 1: simple_proc
Info (12021): Found 1 design units, including 1 entities, in source file components_tb.v
	Info (12023): Found entity 1: components_tb
Info (12021): Found 5 design units, including 5 entities, in source file components.v
	Info (12023): Found entity 1: sign_extend
	Info (12023): Found entity 2: tick_FSM
	Info (12023): Found entity 3: multiplexer
	Info (12023): Found entity 4: ALU
	Info (12023): Found entity 5: register_n
Info (12021): Found 1 design units, including 1 entities, in source file top_level_extension.v
	Info (12023): Found entity 1: top_level_extension
Info (12021): Found 3 design units, including 3 entities, in source file bcd_decoder.v
	Info (12023): Found entity 1: signed_bcd
	Info (12023): Found entity 2: hex_digit
	Info (12023): Found entity 3: display_decoder
Info (12021): Found 1 design units, including 1 entities, in source file proc_memory.v
	Info (12023): Found entity 1: memory_proc
Info (12021): Found 1 design units, including 1 entities, in source file top_level_memory.v
	Info (12023): Found entity 1: top_level_memory
Info (12021): Found 0 design units, including 0 entities, in source file proc_memory_tb.v
Info (12021): Found 1 design units, including 1 entities, in source file instruction_rom.v
	Info (12023): Found entity 1: instruction_ROM
Info (12127): Elaborating entity "top_level_memory" for the top level hierarchy
Info (10264): Verilog HDL Case Statement information at top_level_memory.v(96): all case item expressions in this case statement are onehot
Info (12128): Elaborating entity "instruction_ROM" for hierarchy "instruction_ROM:rom_inst"
Info (12128): Elaborating entity "altsyncram" for hierarchy "instruction_ROM:rom_inst|altsyncram:altsyncram_component"
Info (12130): Elaborated megafunction instantiation "instruction_ROM:rom_inst|altsyncram:altsyncram_component"
Info (12133): Instantiated megafunction "instruction_ROM:rom_inst|altsyncram:altsyncram_component" with the following parameter:
	Info (12134): Parameter "address_aclr_a" = "NONE"
	Info (12134): Parameter "clock_enable_input_a" = "BYPASS"
	Info (12134): Parameter "clock_enable_output_a" = "BYPASS"
	Info (12134): Parameter "init_file" = "memory.mif"
	Info (12134): Parameter "intended_device_family" = "MAX 10"
	Info (12134): Parameter "lpm_hint" = "ENABLE_RUNTIME_MOD=NO"
	Info (12134): Parameter "lpm_type" = "altsyncram"
	Info (12134): Parameter "numwords_a" = "65536"
	Info (12134): Parameter "operation_mode" = "ROM"
	Info (12134): Parameter "outdata_aclr_a" = "NONE"
	Info (12134): Parameter "outdata_reg_a" = "UNREGISTERED"
	Info (12134): Parameter "widthad_a" = "16"
	Info (12134): Parameter "width_a" = "9"
	Info (12134): Parameter "width_byteena_a" = "1"
Info (12021): Found 1 design units, including 1 entities, in source file db/altsyncram_0f91.tdf
	Info (12023): Found entity 1: altsyncram_0f91
Info (12128): Elaborating entity "altsyncram_0f91" for hierarchy "instruction_ROM:rom_inst|altsyncram:altsyncram_component|altsyncram_0f91:auto_generated"
Warning (113028): 65504 out of 65536 addresses are uninitialized. The Quartus Prime software will initialize them to "0". There are 1 warnings found, and 1 warnings are reported.
	Warning (113027): Addresses ranging from 32 to 65535 are not initialized
Info (12021): Found 1 design units, including 1 entities, in source file db/decode_aj9.tdf
	Info (12023): Found entity 1: decode_aj9
Info (12128): Elaborating entity "decode_aj9" for hierarchy "instruction_ROM:rom_inst|altsyncram:altsyncram_component|altsyncram_0f91:auto_generated|decode_aj9:rden_decode"
Info (12021): Found 1 design units, including 1 entities, in source file db/mux_22b.tdf
	Info (12023): Found entity 1: mux_22b
Info (12128): Elaborating entity "mux_22b" for hierarchy "instruction_ROM:rom_inst|altsyncram:altsyncram_component|altsyncram_0f91:auto_generated|mux_22b:mux2"
Info (12128): Elaborating entity "memory_proc" for hierarchy "memory_proc:proc_inst"
Info (10264): Verilog HDL Case Statement information at proc_memory.v(293): all case item expressions in this case statement are onehot
Info (12128): Elaborating entity "sign_extend" for hierarchy "memory_proc:proc_inst|sign_extend:sign_ext_inst"
Info (12128): Elaborating entity "tick_FSM" for hierarchy "memory_proc:proc_inst|tick_FSM:tick_inst"
Info (10264): Verilog HDL Case Statement information at components.v(50): all case item expressions in this case statement are onehot
Info (12128): Elaborating entity "multiplexer" for hierarchy "memory_proc:proc_inst|multiplexer:mux_inst"
Info (12128): Elaborating entity "ALU" for hierarchy "memory_proc:proc_inst|ALU:alu_inst"
Info (12128): Elaborating entity "register_n" for hierarchy "memory_proc:proc_inst|register_n:reg_IR"
Info (12128): Elaborating entity "register_n" for hierarchy "memory_proc:proc_inst|register_n:reg_A"
Info (12128): Elaborating entity "display_decoder" for hierarchy "display_decoder:decoder_inst"
Info (12128): Elaborating entity "signed_bcd" for hierarchy "display_decoder:decoder_inst|signed_bcd:bcd_inst"
Info (12128): Elaborating entity "hex_digit" for hierarchy "display_decoder:decoder_inst|hex_digit:digit0_inst"
Info (278001): Inferred 1 megafunctions from design logic
	Info (278003): Inferred multiplier megafunction ("lpm_mult") from the following logic: "memory_proc:proc_inst|ALU:alu_inst|Mult0"
Info (12130): Elaborated megafunction instantiation "memory_proc:proc_inst|ALU:alu_inst|lpm_mult:Mult0"
Info (12133): Instantiated megafunction "memory_proc:proc_inst|ALU:alu_inst|lpm_mult:Mult0" with the following parameter:
	Info (12134): Parameter "LPM_WIDTHA" = "16"
	Info (12134): Parameter "LPM_WIDTHB" = "16"
	Info (12134): Parameter "LPM_WIDTHP" = "32"
	Info (12134): Parameter "LPM_WIDTHR" = "32"
	Info (12134): Parameter "LPM_WIDTHS" = "1"
	Info (12134): Parameter "LPM_REPRESENTATION" = "SIGNED"
	Info (12134): Parameter "INPUT_A_IS_CONSTANT" = "NO"
	Info (12134): Parameter "INPUT_B_IS_CONSTANT" = "NO"
	Info (12134): Parameter "MAXIMIZE_SPEED" = "5"
Info (12021): Found 1 design units, including 1 entities, in source file db/mult_pgs.tdf
	Info (12023): Found entity 1: mult_pgs
Info (286030): Timing-Driven Synthesis is running
Info (16010): Generating hard_block partition "hard_block:auto_generated_inst"
	Info (16011): Adding 0 node(s), including 0 DDIO, 0 PLL, 0 transceiver and 0 LCELL
Error (16031): Current Internal Configuration mode does not support memory initialization or ROM. Select Internal Configuration mode with ERAM.
Error (16031): Current Internal Configuration mode does not support memory initialization or ROM. Select Internal Configuration mode with ERAM.
Error (16031): Current Internal Configuration mode does not support memory initialization or ROM. Select Internal Configuration mode with ERAM.
Error (16031): Current Internal Configuration mode does not support memory initialization or ROM. Select Internal Configuration mode with ERAM.
Error (16031): Current Internal Configuration mode does not support memory initialization or ROM. Select Internal Configuration mode with ERAM.
Error (16031): Current Internal Configuration mode does not support memory initialization or ROM. Select Internal Configuration mode with ERAM.
Error (16031): Current Internal Configuration mode does not support memory initialization or ROM. Select Internal Configuration mode with ERAM.
Error (16031): Current Internal Configuration mode does not support memory initialization or ROM. Select Internal Configuration mode with ERAM.
Error (16031): Current Internal Configuration mode does not support memory initialization or ROM. Select Internal Configuration mode with ERAM.
Error: Quartus Prime Analysis & Synthesis was unsuccessful. 9 errors, 3 warnings
	Error: Peak virtual memory: 4829 megabytes
	Error: Processing ended: Fri Oct 09 13:10:40 2026
	Error: Elapsed time: 00:00:12
	Error: Total CPU time (on all processors): 00:00:15
Error (293001): Quartus Prime Full Compilation was unsuccessful. 11 errors, 3 warnings
/*