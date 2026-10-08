`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment
This file contains Verilog code to implement the DE10-Lite top level for Task 4,
    which connects the x72 processor to the instruction memory (ROM), the switches, keys, LEDs and HEX5 to HEX0.

Please enter your name and student ID:
-Senuth 36180513
-

*/
module top_level_memory (
	input wire [9:0] SW,
	input wire [1:0] KEY,

	output wire [9:0] LEDR,
	output wire [7:0] HEX0,
	output wire [7:0] HEX1,
	output wire [7:0] HEX2,
	output wire [7:0] HEX3,
	output wire [7:0] HEX4,
	output reg [6:0] HEX5
);

	//SW[9] -> processor enable
	//processor PC -> instruction memory address
	//instruction memory q -> processor din
	//~KEY[0] -> synchronous processor rst
	//~KEY[1] -> processor clk
	//bus[9:0] -> LEDR[9:0]
	//display -> HEX4 to HEX0 as a signed decimal, all five decimal points light when it is negative
	//tick_FSM -> HEX5

	//tick states, from components.v
	localparam
		DIN_READ = 4'b0001,
		BUS_WRITE_ONE = 4'b0010,
		OPERATE_ALU = 4'b0100,
		BUS_WRITE_TWO = 4'b1000;

	wire clk;
	wire [8:0] din;
	wire [15:0] PC;

	wire [15:0] bus;
	wire [15:0] display;
	wire [3:0] tick;

	assign clk = ~KEY[1];

	//instruction memory, clocked on the falling edge so the word at PC arrives in the same tick
	instruction_ROM rom_inst (
		.address(PC),
		.clock(~clk),
		.q(din)
	);

	//instantiate task 4 processor
	memory_proc proc_inst (
		.clk(clk),
		.rst(~KEY[0]),
		.enable(SW[9]),
		.din(din),
		.bus(bus),
		.display(display),
		.tick_FSM(tick),

		//testbench outputs not required on hardware
		.R0(),
		.R1(),
		.R2(),
		.R3(),
		.R4(),
		.R5(),
		.R6(),
		.R7(),

		.PC(PC)
	);

	//display bottom 10 bits of processor bus on LEDs
	assign LEDR = bus[9:0];

	//decode the display register as a signed decimal number onto HEX4 to HEX0
	display_decoder decoder_inst (
		.value(display),
		.hex0(HEX0),
		.hex1(HEX1),
		.hex2(HEX2),
		.hex3(HEX3),
		.hex4(HEX4)
	);

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
