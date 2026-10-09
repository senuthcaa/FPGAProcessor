`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment
This file contains Verilog code to implement individual components to be used in
    the CPU.

Please enter your name and student ID:
-Senuth 36180513
-

*/
module sign_extend(in, ext);
	
	input wire [8:0] in;
   output wire [15:0] ext;
	
	assign ext = {{7{in[8]}}, in};
 
endmodule



module tick_FSM(rst, clk, enable, tick);

	input wire rst;
	input wire clk;
	input wire enable;
	
	output reg [3:0] tick;
	reg [3:0] next_tick;
	
	localparam
		DIN_READ = 4'b0001,
		BUS_WRITE_ONE = 4'b0010,
		OPERATE_ALU = 4'b0100,
		BUS_WRITE_TWO = 4'b1000;
	
	//state
	always @(posedge clk) begin
		if (rst) tick <= DIN_READ;
		else begin
			if (enable) tick <= next_tick;
			else tick <= tick;
		end
	end
	
	//next-state
	always @(*) begin
		next_tick = tick;
		case (tick)
			DIN_READ : next_tick = BUS_WRITE_ONE;
			BUS_WRITE_ONE : next_tick = OPERATE_ALU;
			OPERATE_ALU : next_tick = BUS_WRITE_TWO;
			BUS_WRITE_TWO : next_tick = DIN_READ;
			default : next_tick = DIN_READ;
		endcase
	end
	
endmodule



module multiplexer(SignExtDin, R0, R1, R2, R3, R4, R5, R6, R7, G, sel, Bus);

	input wire [3:0] sel;
	input wire [15:0] R0;
	input wire [15:0] R1;
	input wire [15:0] R2;
	input wire [15:0] R3;
	input wire [15:0] R4;
	input wire [15:0] R5;
	input wire [15:0] R6;
	input wire [15:0] R7;
	input wire [15:0] G;
	input wire [15:0] SignExtDin;
	output reg [15:0] Bus;
	
	
	always @(*) begin
		case (sel)
			4'd0 : Bus = R0;
			4'd1 : Bus = R1;
			4'd2 : Bus = R2;
			4'd3 : Bus = R3;
			4'd4 : Bus = R4;
			4'd5 : Bus = R5;
			4'd6 : Bus = R6;
			4'd7 : Bus = R7;
			4'd8 : Bus = G;
			4'd9 : Bus = SignExtDin;
			default : Bus = SignExtDin;
		endcase
	end


endmodule



module alu (
   input wire signed [15:0] input_a,
   input wire signed [15:0] input_b,
   input wire [2:0] alu_op,
   output reg signed [15:0] result
);

   localparam
		OP_MUL = 3'b000,
		OP_ADD = 3'b001,
		OP_SUB = 3'b010,
		OP_SHF = 3'b011;

	//+ or -
   wire do_sub = (alu_op == OP_SUB);
   wire [15:0] addsub = input_a + (do_sub ? ~input_b : input_b) + do_sub;

   //bit-shifting, input_b is shifted by the signed amount in input_a (spec table 3)
   //+ve input_a shifts input_b left (logical), -ve input_a shifts input_b right (arithmetic)
   wire shift_right = input_a[15];
   wire [15:0] shift_distance = shift_right ? -input_a : input_a;
   wire saturate = |shift_distance[15:4]; //saturate is the boolean: true if shift_distance >= 16
	wire [3:0] true_shift_distance = shift_distance[3:0];

	wire signed [15:0] shift_right_arithmetic = input_b >>> true_shift_distance;
	wire signed [15:0] shift_left_logical = input_b << true_shift_distance;

   wire [15:0] shifted = shift_right
		/* shift right -> */? (saturate ? {16{input_b[15]}} : shift_right_arithmetic)
		/* shift left -> */: (saturate ? 16'd0 : shift_left_logical);

   always @(*) begin
      case (alu_op)
			OP_MUL : result = input_a * input_b;
         OP_ADD, OP_SUB : result = addsub;
         OP_SHF : result = shifted;
			default : result = 16'd0;
		endcase
   end

endmodule



module register_n(data_in, r_in, clk, Q, rst);


	// To set parameter N during instantiation, you can use:
	// register_n #(.N(num_bits)) reg_IR(.....), 
	// where num_bits is how many bits you want to set N to
	// and "..." is your usual input/output signals

	parameter N = 16;

	input wire [N-1:0] data_in;
	input wire r_in;
	input wire rst;
	input wire clk;
	output reg [N-1:0] Q;
	
	always @(posedge clk) begin
		if (rst) Q <= {N{1'b0}};
		else begin
			if (r_in) Q <= data_in;
			else Q <= Q;
		end
	end
	
endmodule
