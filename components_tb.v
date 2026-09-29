`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment 
This file contains a Verilog test bench to test the correctness of the individual 
    components used in the processor.

Please enter your student ID:
-36180513

*/
module components_tb;

	//parameters
	localparam REG_N = 16;              // width of register_n under test (change to test other N)

	//sign_extend vars
	reg [8:0] se_in;
	wire [15:0] se_ext_DUT;

	//tick_fsm vars
	reg tick_rst;
	reg tick_enable;
	wire [3:0] tick_DUT_out;

	//mux vars
	reg [15:0] mux_SignExtDin;
	reg [15:0] mux_R0, mux_R1, mux_R2, mux_R3, mux_R4, mux_R5, mux_R6, mux_R7;
	reg [15:0] mux_G;
	reg [3:0] mux_sel;
	wire [15:0] mux_Bus_DUT;

	//alu vars
	reg signed [15:0] alu_a;
	reg signed [15:0] alu_b;
	reg [2:0] alu_op;
	wire signed [15:0] alu_result_DUT;

	//regn vars
	reg [REG_N-1:0] reg_din;
	reg reg_rin;
	wire [REG_N-1:0] reg_out_DUT;
	reg reg_rst;

	//instantiate modules
	sign_extend sign_ext_DUT (
		.in(se_in),
		.ext(se_ext_DUT)
	);

	tick_FSM tick_DUT (
		.rst(tick_rst),
		.clk(clk),
		.enable(tick_enable),
		.tick(tick_DUT_out)
	);

	multiplexer mux_DUT (
		.SignExtDin(mux_SignExtDin),
		.R0(mux_R0),
		.R1(mux_R1),
		.R2(mux_R2),
		.R3(mux_R3),
		.R4(mux_R4),
		.R5(mux_R5),
		.R6(mux_R6),
		.R7(mux_R7),
		.G(mux_G),
		.sel(mux_sel),
		.Bus(mux_Bus_DUT)
	);

	ALU alu_DUT (
		.input_a(alu_a),
		.input_b(alu_b),
		.alu_op(alu_op),
		.result(alu_result_DUT)
	);

	register_n #(.N(REG_N)) reg_DUT (
		.data_in(reg_din),
		.r_in(reg_rin),
		.clk(clk),
		.Q(reg_out_DUT),
		.rst(reg_rst)
	);

	//==========================================================
	// Clock generation
	//==========================================================
	// TODO: initialise clk and toggle it every CLK_PERIOD/2
	reg clk = 1'b0;
	always #10 clk = ~clk; //50MHz
	

	//==========================================================
	// Optional: error counter / check task
	//==========================================================
	// TODO: integer to count failures
	// TODO: (optional) a task that compares a DUT output to an expected value
	//       and prints a PASS/FAIL message with $display
	integer errors, counter;

	//==========================================================
	// Stimulus
	//==========================================================
	// initial begin
	//
	//     // ---- Initialise all inputs to known values ----
	//     // TODO: set every reg above to 0 (avoid X on inputs)
	initial begin
		se_in           = 9'd0;

		tick_rst        = 1'b0;
		tick_enable     = 1'b0;

		mux_SignExtDin  = 16'd0;
		mux_R0          = 16'd0;
		mux_R1          = 16'd0;
		mux_R2          = 16'd0;
		mux_R3          = 16'd0;
		mux_R4          = 16'd0;
		mux_R5          = 16'd0;
		mux_R6          = 16'd0;
		mux_R7          = 16'd0;
		mux_G           = 16'd0;
		mux_sel         = 4'd0;

		alu_a           = 16'sd0;
		alu_b           = 16'sd0;
		alu_op          = 3'b000;

		reg_din         = {REG_N{1'b0}};
		reg_rin         = 1'b0;
		reg_rst         = 1'b0;
	end
	
	
	//SIGN EXTENDER TESTBENCH
	
	integer se_counter;
	integer se_errors;
	
	reg [15:0] se_ext_TRUE [0:511];
	
	initial begin
	
		$readmemh("se_ext_TRUE.dat", se_ext_TRUE);
		if (se_ext_TRUE[0] === 16'hxxxx) $display("ERROR: se_ext_TRUE.dat not loaded");
		
		se_errors = 0;
		
		for (se_counter = 0; se_counter < 512; se_counter = se_counter + 1) begin
			se_in = se_counter;
			#1
			if (se_ext_DUT !== se_ext_TRUE[se_counter]) begin
				se_errors = se_errors + 1;
				$display("sign_extend FAIL: in=%0d  got=%h  expected=%h", se_counter, se_ext_DUT, se_ext_TRUE[se_counter]);
			end
		end
		
		if (se_errors != 0) $display("sign_extend: %0d/512 failed", se_errors);
		
	end
	
	//
	//     // ---- 2. tick_FSM ---
	//     // TODO: assert tick_rst for a clock edge    -> expect DIN_READ (0001)
	//     // TODO: release reset, enable = 1           -> step through 0001 -> 0010 -> 0100 -> 1000 -> 0001
	//     // TODO: enable = 0 mid-sequence             -> tick should hold
	//     // TODO: reset mid-sequence                  -> back to 0001
	//
	//     // ---- 3. multiplexer ----
	//     // TODO: load R0..R7, G, SignExtDin with distinct values
	//     // TODO: sweep sel 0..9                      -> Bus matches the selected input
	//     // TODO: sel 10..15                          -> default (SignExtDin)
	//
	//     // ---- 4. ALU ----
	//     // MUL (000):
	//     // TODO: pos*pos, pos*neg, neg*neg, *0, overflow case
	//     // ADD (001):
	//     // TODO: pos+pos, pos+neg, neg+neg, overflow/wrap-around
	//     // SUB (010):
	//     // TODO: a-b with a>b, a<b, a==b, subtracting a negative
	//     // SHF (011):
	//     // TODO: b > 0 (shift left), b < 0 (arithmetic shift right)
	//     // TODO: b = 0, b = 15, b = -15
	//     // TODO: saturation: b >= 16 (expect 0), b <= -16 (expect sign fill)
	//     // TODO: negative input_a with right shift (check sign preserved)
	//     // Unused ops (100-111):
	//     // TODO: expect result = 0
	//
	//     // ---- 5. register_n ----
	//     // TODO: assert reg_rst                      -> Q = 0
	//     // TODO: r_in = 1 with data                  -> Q updates on next posedge
	//     // TODO: r_in = 0, change data               -> Q holds
	//     // TODO: rst and r_in both high              -> reset should win
	//
	//     // ---- Summary ----
	//     // TODO: print total failures
	//     // TODO: $stop / $finish
	//
	// end

endmodule