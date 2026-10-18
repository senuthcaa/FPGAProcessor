`timescale 1ns / 1ps
/*

-Senuth 36180513
-Hoorad 36166804

*/
module top_level (
	input wire [9:0] SW,
	input wire [1:0] KEY,

	output wire [9:0] LEDR,
	output reg [6:0] HEX5
);

	//SW[8:0] processor din
	//~KEY[0] processor rst
	//~KEY[1] processor clk
	//processor enable 1'b1
	//bus[9:0] LEDR[9:0]
	//tick_FSM HEX5

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

	//display current tick on seven segment displays- are activelow
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