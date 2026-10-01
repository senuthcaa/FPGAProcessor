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

	//clock
	reg clk = 1'b0;
	always #10 clk = ~clk; //50MHz

	//sign_extend vars
	reg [8:0] se_in;
	wire [15:0] se_ext_DUT;

	//tick_fsm vars
	reg tick_rst;
	reg tick_enable;
	wire [3:0] tick_out_DUT;

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

	//section completion flags, used to end the simulation
	reg se_done = 1'b0;
	reg tick_done = 1'b0;
	reg mux_done = 1'b0;
	reg reg_done = 1'b0;

	//instantiate modules
	sign_extend sign_ext_DUT (
		.in(se_in),
		.ext(se_ext_DUT)
	);

	tick_FSM tick_DUT (
		.rst(tick_rst),
		.clk(clk),
		.enable(tick_enable),
		.tick(tick_out_DUT)
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


	//initialise variables
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
	integer se_done;

	reg [15:0] se_ext_TRUE [0:511];

	initial begin

		//creates a huge array of all the possible combinations (brute force method)
		$readmemh("se_ext_TRUE.dat", se_ext_TRUE);
		if (se_ext_TRUE[0] === 16'hxxxx) $display("ERROR: se_ext_TRUE.dat not loaded");

		se_errors = 0;

		for (se_counter = 0; se_counter < 512; se_counter = se_counter + 1) begin
			se_in = se_counter;
			#1;
			if (se_ext_DUT !== se_ext_TRUE[se_counter]) begin
				se_errors = se_errors + 1;
				$display("sign extender FAIL: in=%0d  got=%b  expected=%b", se_counter, se_ext_DUT, se_ext_TRUE[se_counter]);
			end
		end

		if (se_errors != 0) $display("sign extender: %0d/512 failed", se_errors);

		se_done = 1'b1;

	end


	//TICK FSM TESTBENCH

	integer tick_errors;
	integer tick_done;

	localparam
		DIN_READ = 4'b0001,
		BUS_WRITE_ONE = 4'b0010,
		OPERATE_ALU = 4'b0100,
		BUS_WRITE_TWO = 4'b1000;

	task check_tick;
		input [3:0] expected;
		begin
			if (tick_out_DUT !== expected) begin
				tick_errors = tick_errors + 1;
				$display("tick FSM FAIL at t=%0t: rst=%b enable=%b got=%b expected=%b",$time,tick_rst,tick_enable,tick_out_DUT,expected);
			end
		end
	endtask

	initial begin

		tick_errors = 0;

		//test rst
		@(negedge clk);
		tick_rst = 1'b1;
		tick_enable = 1'b0;
		@(posedge clk);
		#1;
		check_tick(DIN_READ);

		//test full sequence, enable = 1
		@(negedge clk);
		tick_rst = 1'b0;
		tick_enable = 1'b1;
		@(posedge clk);
		#1;
		check_tick(BUS_WRITE_ONE);
		@(posedge clk);
		#1;
		check_tick(OPERATE_ALU);
		@(posedge clk);
		#1;
		check_tick(BUS_WRITE_TWO);
		@(posedge clk);
		#1;
		check_tick(DIN_READ);

		//advance mid-sequence to OPERATE_ALU
		@(posedge clk);
		#1;
		check_tick(BUS_WRITE_ONE);
		@(posedge clk);
		#1;
		check_tick(OPERATE_ALU);

		//test hold mid-sequence, enable = 0
		@(negedge clk);
		tick_enable = 1'b0;
		@(posedge clk);
		#1;
		check_tick(OPERATE_ALU);
		@(posedge clk);
		#1;
		check_tick(OPERATE_ALU);
		@(posedge clk);
		#1;
		check_tick(OPERATE_ALU);

		//test resume from held state, enable = 1
		@(negedge clk);
		tick_enable = 1'b1;
		@(posedge clk);
		#1;
		check_tick(BUS_WRITE_TWO);

		//test rst mid-sequence, overriding enable = 1
		@(negedge clk);
		tick_rst = 1'b1;
		@(posedge clk);
		#1;
		check_tick(DIN_READ);

		//release rst
		@(negedge clk);
		tick_rst = 1'b0;
		tick_enable = 1'b0;

		if (tick_errors != 0) $display("tick FSM: %0d checks failed", tick_errors);

		tick_done = 1'b1;

	end


	//MULTIPLEXER TESTBENCH

	integer mux_counter;
	integer mux_errors;
	integer mux_done;

	//expected Bus for every value of sel, including the default range
	reg [15:0] mux_TRUE [0:15];

	task check_mux;
		input [3:0] sel;
		begin
			if (mux_Bus_DUT !== mux_TRUE[sel]) begin
				mux_errors = mux_errors + 1;
				$display("mux FAIL: sel=%0d  got=%h  expected=%h", sel, mux_Bus_DUT, mux_TRUE[sel]);
			end
		end
	endtask

	//keeps mux_TRUE in step with the current input values
	task load_mux_TRUE;
		begin
			mux_TRUE[0] = mux_R0;
			mux_TRUE[1] = mux_R1;
			mux_TRUE[2] = mux_R2;
			mux_TRUE[3] = mux_R3;
			mux_TRUE[4] = mux_R4;
			mux_TRUE[5] = mux_R5;
			mux_TRUE[6] = mux_R6;
			mux_TRUE[7] = mux_R7;
			mux_TRUE[8] = mux_G;
			//sel 9 selects SignExtDin, and 10 to 15 fall through to the same default
			for (mux_counter = 9; mux_counter < 16; mux_counter = mux_counter + 1) mux_TRUE[mux_counter] = mux_SignExtDin;
		end
	endtask

	initial begin

		//waits for the initialise block to finish before overwriting the inputs
		#1;

		mux_errors = 0;

		//every input gets a distinct value, so a wrong selection cannot coincidentally match
		mux_R0          = 16'h1111;
		mux_R1          = 16'h2222;
		mux_R2          = 16'h3333;
		mux_R3          = 16'h4444;
		mux_R4          = 16'h5555;
		mux_R5          = 16'h6666;
		mux_R6          = 16'h7777;
		mux_R7          = 16'h8888;
		mux_G           = 16'h9999;
		mux_SignExtDin  = 16'hAAAA;
		load_mux_TRUE;

		//test every value of sel, 0 to 8 select a register, 9 selects SignExtDin, 10 to 15 are the default
		for (mux_counter = 0; mux_counter < 16; mux_counter = mux_counter + 1) begin
			mux_sel = mux_counter;
			#1;
			check_mux(mux_counter);
		end

		//test the default range again with a new SignExtDin, to confirm Bus follows it and is not latched
		mux_SignExtDin = 16'hBBBB;
		load_mux_TRUE;
		for (mux_counter = 9; mux_counter < 16; mux_counter = mux_counter + 1) begin
			mux_sel = mux_counter;
			#1;
			check_mux(mux_counter);
		end

		//test that Bus tracks a live change on the already selected input
		mux_sel = 4'd3;
		#1;
		mux_R3 = 16'hDEAD;
		load_mux_TRUE;
		#1;
		check_mux(4'd3);

		//release
		mux_sel = 4'd0;

		if (mux_errors != 0) $display("mux: %0d checks failed", mux_errors);

		mux_done = 1'b1;

	end


	//REGISTER_N TESTBENCH

	integer reg_errors;
	integer reg_done;

	task check_reg;
		input [REG_N-1:0] expected;
		begin
			if (reg_out_DUT !== expected) begin
				reg_errors = reg_errors + 1;
				$display("register_n FAIL at t=%0t: rst=%b r_in=%b data_in=%h got=%h expected=%h",$time,reg_rst,reg_rin,reg_din,reg_out_DUT,expected);
			end
		end
	endtask

	initial begin

		reg_errors = 0;

		//test rst, with non-zero data_in so a pass cannot come from data_in being 0
		@(negedge clk);
		reg_rst = 1'b1;
		reg_rin = 1'b0;
		reg_din = {REG_N{1'b1}};
		@(posedge clk);
		#1;
		check_reg({REG_N{1'b0}});

		//test load, r_in = 1
		@(negedge clk);
		reg_rst = 1'b0;
		reg_rin = 1'b1;
		reg_din = 16'hA5A5;
		@(posedge clk);
		#1;
		check_reg(16'hA5A5);

		//test a second load, to confirm Q is overwritten and not just set once
		@(negedge clk);
		reg_din = 16'h5A5A;
		@(posedge clk);
		#1;
		check_reg(16'h5A5A);

		//test hold, r_in = 0 while data_in changes
		@(negedge clk);
		reg_rin = 1'b0;
		reg_din = 16'hFFFF;
		@(posedge clk);
		#1;
		check_reg(16'h5A5A);
		@(posedge clk);
		#1;
		check_reg(16'h5A5A);
		@(posedge clk);
		#1;
		check_reg(16'h5A5A);

		//test rst overriding r_in = 1
		@(negedge clk);
		reg_rst = 1'b1;
		reg_rin = 1'b1;
		reg_din = 16'hFFFF;
		@(posedge clk);
		#1;
		check_reg({REG_N{1'b0}});

		//test every bit can be driven high
		@(negedge clk);
		reg_rst = 1'b0;
		reg_rin = 1'b1;
		reg_din = {REG_N{1'b1}};
		@(posedge clk);
		#1;
		check_reg({REG_N{1'b1}});

		//test Q only changes on the clock edge, not combinationally
		@(negedge clk);
		reg_din = 16'h0F0F;
		#1;
		check_reg({REG_N{1'b1}});
		@(posedge clk);
		#1;
		check_reg(16'h0F0F);

		//release
		@(negedge clk);
		reg_rin = 1'b0;
		reg_din = {REG_N{1'b0}};

		if (reg_errors != 0) $display("register_n: %0d checks failed", reg_errors);

		reg_done = 1'b1;

	end


	//ALU TESTBENCH

	integer alu_errors;
	integer alu_done;
	
	task check_alu;
		input [15:0] expected;
		begin
			if (alu_result_DUT !== expected) begin
				alu_errors = alu_errors + 1;
				$display("alu FAIL: alu_op=%b alu_a=%0d alu_b=%0d got=%0d expected=%0d",alu_op,alu_a,alu_b,alu_result_DUT,expected)
			end
		end
	endtask
	
	localparam
		OP_MUL = 3'b000,
		OP_ADD = 3'b001,
		OP_SUB = 3'b010,
		OP_SHF = 3'b011;
	
	task check_alu;
		input signed [15:0] expected;
		begin
			if (alu_result_DUT !== expected) begin
				alu_errors = alu_errors + 1;
				$display("ALU FAIL: op=%b a=%0d b=%0d got=%0d (%h) expected=%0d (%h)",alu_op,alu_a,alu_b,alu_result_DUT,alu_result_DUT,expected,expected);
			end
		end
	endtask
	
	initial begin
		
		//waits for the initialise block to finish before overwriting the inputs
		#1;
		
		alu_errors = 0;
		
		alu_op = OP_MUL;
	
		//pos*pos
		alu_a = 16'sd13;
		alu_b = 16'sd845;
		#1;
		check_alu(16'sd10985);
		
		//pos*neg
		alu_b = -16'sd151;
		#1;
		check_alu(-16'sd1963);
		
		//neg*neg
		alu_a = -16'sd77;
		#1;
		check_alu(16'sd11627);
		
		//*0
		alu_a = 16'sd29876;
		alu_b = 16'sd0;
		#1;
		check_alu(16'sd0);
		
		//overflow
		alu_a = 16'sd31452;
		alu_b = 16'sd24759;
		#1;
		check_alu(16'sd21316);
		
		alu_op = OP_ADD;
		
		//pos+pos
		alu_a = 16'sd16345;
		alu_b = 16'sd8946;
		#1;
		check_alu(16'sd25291);
		
		//pos+neg
		alu_b = -16'sd31222;
		#1;
		check_alu(-16'sd14877);
		
		//neg+neg
		alu_a = -16'sd203;
		#1;
		check_alu(-16'sd31425);
		
		//overflow, two pos wrap to neg
		alu_a = 16'sd32000;
		alu_b = 16'sd2000;
		#1;
		check_alu(-16'sd31536);
		
		//overflow, largest pos + 1
		alu_a = 16'sh7FFF;
		alu_b = 16'sd1;
		#1;
		check_alu(16'sh8000);
		
		//underflow, two neg to pos
		alu_a = -16'sd32000;
		alu_b = -16'sd2000;
		#1;
		check_alu(16'sd31536);
		
		//underflow, smallest neg - 1
		alu_a = 16'sh8000;
		alu_b = -16'sd1;
		#1;
		check_alu(16'sh7FFF);
		
		//+0
		alu_a = -16'sd12345;
		alu_b = 16'sd0;
		#1;
		check_alu(-16'sd12345);
		
		//a+(-a)
		alu_a = 16'sd21845;
		alu_b = -16'sd21845;
		#1;
		check_alu(16'sd0);
		
		alu_op = OP_SUB;
		
		//a > b, both pos
		alu_a = 16'sd9000;
		alu_b = 16'sd3000;
		#1;
		check_alu(16'sd6000);
		
		//a < b, both pos
		alu_a = 16'sd3000;
		alu_b = 16'sd9000;
		#1;
		check_alu(-16'sd6000);
		
		//a == b
		alu_a = 16'sd7777;
		alu_b = 16'sd7777;
		#1;
		check_alu(16'sd0);
		
		//- a neg
		alu_a = 16'sd500;
		alu_b = -16'sd1500;
		#1;
		check_alu(16'sd2000);
		
		//neg-pos
		alu_a = -16'sd500;
		alu_b = 16'sd1500;
		#1;
		check_alu(-16'sd2000);
		
		//neg-neg
		alu_a = -16'sd500;
		alu_b = -16'sd1500;
		#1;
		check_alu(16'sd1000);
		
		//-0
		alu_a = -16'sd12345;
		alu_b = 16'sd0;
		#1;
		check_alu(-16'sd12345);
		
		//0-
		alu_a = 16'sd0;
		alu_b = 16'sd12345;
		#1;
		check_alu(-16'sd12345);
		
		//overflow, largest pos - (-1)
		alu_a = 16'sh7FFF;
		alu_b = -16'sd1;
		#1;
		check_alu(16'sh8000);
		
		//underflow, smallest neg - 1
		alu_a = 16'sh8000;
		alu_b = 16'sd1;
		#1;
		check_alu(16'sh7FFF);
		
		//0-smallest neg
		alu_a = 16'sd0;
		alu_b = 16'sh8000;
		#1;
		check_alu(16'sh8000);
		
		//large difference wrapping
		alu_a = 16'sd30000;
		alu_b = -16'sd30000;
		#1;
		check_alu(-16'sd5536);
		
		//TODO
		//SHF (011): b > 0 (shift left), b < 0 (arithmetic shift right)
		//SHF (011): b = 0, b = 15, b = -15
		//SHF (011): saturation, b >= 16 (expect 0), b <= -16 (expect sign fill)
		//SHF (011): negative input_a with right shift (check sign preserved)
		//unused ops (100 to 111): expect result = 0
		
		if (alu_errors != 0) $display("ALU: %0d checks failed", alu_errors);
		
		alu_done = 1'b1;
		
	end
		
	
		
	
	end


	//SIMULATION END

	initial begin

		wait (alu_done && se_done && tick_done && mux_done && reg_done);

		$display("==TEST SUMMARY==");
		$display("sign extender : %0d failed", se_errors);
		$display("tick FSM : %0d failed", tick_errors);
		$display("mux : %0d failed", mux_errors);
		$display("register_n : %0d failed", reg_errors);1
		$stop;

	end

endmodule