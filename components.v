/*
Monash University ECE2072: Assignment 
This file contains Verilog code to implement individual components to be used in 
    the CPU.

Please enter your name and student ID:

*/
module sign_extend(in, ext);
	/* 
	 * This module sign extends the 9-bit Din to a 16-bit output.
	 */
	
	input wire [8:0] in;
   output wire [15:0] ext;
	
	assign ext = {{7{in[8]}}, in};
 
endmodule



module tick_FSM(rst, clk, enable, tick);
	/* 
	 * This module implements a tick FSM that will be used to
	 * control the actions of the control unit
	 */

	// TODO: Declare inputs and outputs
	
    // TODO: implement FSM
endmodule



module multiplexer(SignExtDin, R0, R1, R2, R3, R4, R5, R6, R7, G, sel, Bus);
	/* 
	 * This module takes 10 inputs and places the correct input onto the bus.
	 */
	input wire [3:0] sel;
	
	always @(*) begin
		case (sel)
			4'd0
			4'd1
			4'd2
			4'd3
			4'd4
			4'd5
			4'd6
			4'd7
		endcase
	end


endmodule



module ALU (
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

   //bit-shifting
   wire shift_right = input_b[15];
   wire [15:0] shift_distance = shift_right ? -input_b : input_b;
   wire saturate = |shift_distance[15:4]; //saturate is the boolean: true if shift_distance >= 16
	
	wire signed [15:0] shift_right_arithmetic = input_a >>> true_shift_distance;
	wire signed [15:0] shift_left_logical = input_a << true_shift_distance;

   wire [3:0] true_shift_distance = shift_distance[3:0];
   wire [15:0] shifted = shift_right
		/* shift right -> */? (saturate ? {16{input_a[15]}} : shift_right_arithmetic)
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

	/* 
	 * This module implements registers that will be used in the processor.
	 */
	// TODO: Declare inputs, outputs, and parameter:
	
	// TODO: Implement register logic:
endmodule

