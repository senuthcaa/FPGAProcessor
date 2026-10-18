`timescale 1ns / 1ps
/*
-36166804 Hoorad
-36180513 Senuth

*/
module proc_extension_tb;

	//instruction opcodes, from the x72 instruction table
	localparam
		INSTR_DISP = 3'd0,
		INSTR_ADD = 3'd1,
		INSTR_ADDI = 3'd2,
		INSTR_SUB = 3'd3,
		INSTR_MUL = 3'd4,
		INSTR_SSI = 3'd5,
		INSTR_MOVI = 3'd7;

	//tick states, from components.v
	localparam
		DIN_READ = 4'b0001,
		BUS_WRITE_ONE = 4'b0010,
		OPERATE_ALU = 4'b0100,
		BUS_WRITE_TWO = 4'b1000;

	//clock
	reg clk = 1'b0;
	always #10 clk = ~clk; //50MHz

	//processor vars
	reg rst;
	reg enable;
	reg [8:0] din;
	wire [15:0] bus_DUT;
	wire [15:0] display_DUT;
	wire [3:0] tick_FSM_DUT;
	wire [15:0] R0_DUT, R1_DUT, R2_DUT, R3_DUT, R4_DUT, R5_DUT, R6_DUT, R7_DUT;

	//section completion flags, each test waits for the one before it, and the simulation ends once all are set
	reg reset_done = 1'b0;
	reg tick_done = 1'b0;
	reg movi_done = 1'b0;
	reg addi_done = 1'b0;
	reg mul_done = 1'b0;
	reg ssi_done = 1'b0;
	reg disp_done = 1'b0;

	//instantiate modules
	extended_proc proc_DUT (
		.clk(clk),
		.rst(rst),
		.enable(enable),
		.din(din),
		.bus(bus_DUT),
		.display(display_DUT),
		.tick_FSM(tick_FSM_DUT),
		.R0(R0_DUT),
		.R1(R1_DUT),
		.R2(R2_DUT),
		.R3(R3_DUT),
		.R4(R4_DUT),
		.R5(R5_DUT),
		.R6(R6_DUT),
		.R7(R7_DUT)
	);


	//initialise variables
	initial begin
		rst             = 1'b0;
		enable          = 1'b1;
		din             = 9'd0;
	end


	//everything between the two directives is simulation only, quartus skips it and modelsim still runs it
	// synthesis translate_off


	//SHARED TASKS

	//expected contents of R0 to R7
	reg [15:0] regs_TRUE [0:7];

	//the test that is running and the instruction it is on, printed with every failure
	reg [8*8-1:0] test_name;
	reg [8*16-1:0] instr_text;
	integer test_errors;

	//16-bit LFSR, x^16 + x^14 + x^13 + x^11 + 1, gives random values for din in the ticks where it should be ignored
	reg [15:0] lfsr = 16'hACE1;

	function [15:0] dut_reg;
		input [2:0] idx;
		begin
			case (idx)
				3'd0 : dut_reg = R0_DUT;
				3'd1 : dut_reg = R1_DUT;
				3'd2 : dut_reg = R2_DUT;
				3'd3 : dut_reg = R3_DUT;
				3'd4 : dut_reg = R4_DUT;
				3'd5 : dut_reg = R5_DUT;
				3'd6 : dut_reg = R6_DUT;
				default : dut_reg = R7_DUT;
			endcase
		end
	endfunction

	//waits for a rising edge, then 1ns, so the registers have updated
	task tick_edge;
		begin
			@(posedge clk);
			#1;
		end
	endtask

	//advances the LFSR by 16 steps so each value is unrelated to the last
	task next_rand;
		integer rand_counter;
		begin
			for (rand_counter = 0; rand_counter < 16; rand_counter = rand_counter + 1) lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
		end
	endtask

	//puts a random value on din, used in the ticks where the processor should ignore din
	task scramble_din;
		begin
			next_rand;
			din = lfsr[8:0];
			#1;
		end
	endtask

	//writes the instruction as text, e.g. movi r3, -1, for the failure messages
	task set_instr_text;
		input [8:0] instr;
		input [8:0] imm;
		begin
			case (instr[8:6])
				INSTR_DISP : $sformat(instr_text, "disp r%0d", instr[5:3]);
				INSTR_ADD : $sformat(instr_text, "add r%0d, r%0d", instr[5:3], instr[2:0]);
				INSTR_ADDI : $sformat(instr_text, "addi r%0d, %0d", instr[5:3], $signed(imm));
				INSTR_SUB : $sformat(instr_text, "sub r%0d, r%0d", instr[5:3], instr[2:0]);
				INSTR_MUL : $sformat(instr_text, "mul r%0d, r%0d", instr[5:3], instr[2:0]);
				INSTR_SSI : $sformat(instr_text, "ssi r%0d, %0d", instr[5:3], $signed(imm));
				default : $sformat(instr_text, "movi r%0d, %0d", instr[5:3], $signed(imm));
			endcase
		end
	endtask

	task check_value;
		input [8*24-1:0] label;
		input [15:0] got;
		input [15:0] expected;
		begin
			if (got !== expected) begin
				test_errors = test_errors + 1;
				$display("%0s FAIL at t=%0t during %0s: %0s got=%0d (%h) expected=%0d (%h)",test_name,$time,instr_text,label,$signed(got),got,$signed(expected),expected);
			end
		end
	endtask

	task check_tick;
		input [3:0] expected;
		begin
			if (tick_FSM_DUT !== expected) begin
				test_errors = test_errors + 1;
				$display("%0s FAIL at t=%0t during %0s: tick got=%b expected=%b",test_name,$time,instr_text,tick_FSM_DUT,expected);
			end
		end
	endtask

	//compares R0 to R7 with regs_TRUE
	task check_regs;
		input [8*24-1:0] label;
		integer reg_counter;
		begin
			for (reg_counter = 0; reg_counter < 8; reg_counter = reg_counter + 1) begin
				if (dut_reg(reg_counter) !== regs_TRUE[reg_counter]) begin
					test_errors = test_errors + 1;
					$display("%0s FAIL at t=%0t during %0s: R%0d %0s got=%0d (%h) expected=%0d (%h)",test_name,$time,instr_text,reg_counter,label,$signed(dut_reg(reg_counter)),dut_reg(reg_counter),$signed(regs_TRUE[reg_counter]),regs_TRUE[reg_counter]);
				end
			end
		end
	endtask

	//resets the processor at the start of each test, so no test depends on the ones before it
	task start_test;
		input [8*8-1:0] name;
		integer reg_counter;
		begin
			test_name = name;
			test_errors = 0;
			instr_text = "reset";
			rst = 1'b1;
			tick_edge;
			rst = 1'b0;
			for (reg_counter = 0; reg_counter < 8; reg_counter = reg_counter + 1) regs_TRUE[reg_counter] = 16'd0;
		end
	endtask

	//runs a type 2 instruction (movi or addi), checking the tick, the bus and every register in each tick
	task exec_type2;
		input [2:0] op;
		input [2:0] rx;
		input [8:0] imm;
		reg [15:0] imm_ext;
		reg [15:0] result;
		begin
			imm_ext = {{7{imm[8]}}, imm};
			if (op == INSTR_ADDI) result = regs_TRUE[rx] + imm_ext;
			else result = imm_ext;
			set_instr_text({op, rx, 3'd0}, imm);

			//tick 1, the instruction is on din, its unused low bits are random
			next_rand;
			din = {op, rx, lfsr[2:0]};
			#1;
			check_tick(DIN_READ);
			tick_edge;

			//tick 2, the immediate is on din and goes onto the bus
			din = imm;
			#1;
			check_tick(BUS_WRITE_ONE);
			check_value("bus in tick 2", bus_DUT, imm_ext);
			check_regs("in tick 2");
			tick_edge;

			//movi writes Rx at the end of tick 2
			if (op == INSTR_MOVI) regs_TRUE[rx] = result;

			//tick 3, addi puts Rx on the bus
			scramble_din;
			check_tick(OPERATE_ALU);
			if (op == INSTR_ADDI) check_value("bus in tick 3", bus_DUT, regs_TRUE[rx]);
			check_regs("in tick 3");
			tick_edge;

			//tick 4, addi puts the result on the bus
			scramble_din;
			check_tick(BUS_WRITE_TWO);
			if (op == INSTR_ADDI) check_value("bus in tick 4", bus_DUT, result);
			check_regs("in tick 4");
			tick_edge;

			//back to tick 1, Rx holds the result
			regs_TRUE[rx] = result;
			check_tick(DIN_READ);
			check_regs("after the instruction");
		end
	endtask

	//runs any instruction through its 4 ticks without checking them, imm is only read by addi, ssi and movi
	task run_instr;
		input [8:0] instr;
		input [8:0] imm;
		begin
			set_instr_text(instr, imm);
			din = instr;
			tick_edge;
			din = imm;
			tick_edge;
			tick_edge;
			tick_edge;
		end
	endtask


	//RESET TEST

	integer reset_errors;

	initial begin

		//waits for the initialise block to finish before overwriting the inputs
		#1;

		//every register starts unknown, one rst edge must clear them all
		start_test("reset");
		check_tick(DIN_READ);
		check_regs("after reset");
		check_value("bus after reset", bus_DUT, 16'd0);

		reset_errors = test_errors;
		if (reset_errors != 0) $display("reset: %0d checks failed", reset_errors);

		reset_done = 1'b1;

	end


	//TICK FSM TEST

	integer tick_counter;
	integer tick_errors;

	//expected tick order, starting from DIN_READ
	reg [3:0] tick_TRUE [0:3];

	initial begin

		tick_TRUE[0] = DIN_READ;
		tick_TRUE[1] = BUS_WRITE_ONE;
		tick_TRUE[2] = OPERATE_ALU;
		tick_TRUE[3] = BUS_WRITE_TWO;

		wait (reset_done);
		start_test("tick FSM");

		//3 runs of add r0, r0, which leaves every register at 0, the tick must cycle through all 4 states in order
		din = {INSTR_ADD, 3'd0, 3'd0};
		set_instr_text(din, 9'd0);
		#1;
		for (tick_counter = 0; tick_counter < 12; tick_counter = tick_counter + 1) begin
			check_tick(tick_TRUE[tick_counter % 4]);
			tick_edge;
		end

		tick_errors = test_errors;
		if (tick_errors != 0) $display("tick FSM: %0d checks failed", tick_errors);

		tick_done = 1'b1;

	end


	//MOVI TEST

	integer movi_errors;

	initial begin

		wait (tick_done);
		start_test("movi");

		//every register, with the largest and smallest immediates
		exec_type2(INSTR_MOVI, 3'd0, 9'h000);
		check_value("R0", R0_DUT, 16'd0);
		exec_type2(INSTR_MOVI, 3'd1, 9'h001);
		check_value("R1", R1_DUT, 16'd1);
		exec_type2(INSTR_MOVI, 3'd2, 9'h0FF); //255, the largest immediate
		check_value("R2", R2_DUT, 16'd255);
		exec_type2(INSTR_MOVI, 3'd3, 9'h1FF); //-1
		check_value("R3", R3_DUT, 16'hFFFF);
		exec_type2(INSTR_MOVI, 3'd4, 9'h100); //-256, the smallest immediate
		check_value("R4", R4_DUT, 16'hFF00);
		exec_type2(INSTR_MOVI, 3'd5, 9'h07F); //127
		check_value("R5", R5_DUT, 16'd127);
		exec_type2(INSTR_MOVI, 3'd6, 9'h181); //-127
		check_value("R6", R6_DUT, 16'hFF81);
		exec_type2(INSTR_MOVI, 3'd7, 9'h0AA); //170
		check_value("R7", R7_DUT, 16'd170);

		//overwrite a register that is not 0
		exec_type2(INSTR_MOVI, 3'd3, 9'h055); //85
		check_value("R3", R3_DUT, 16'd85);

		movi_errors = test_errors;
		if (movi_errors != 0) $display("movi: %0d checks failed", movi_errors);

		movi_done = 1'b1;

	end


	//ADDI TEST

	integer addi_counter;
	integer addi_errors;

	//R0 to R7 are loaded with 5, -9, 100, -100, 255, -256, 77, 33 before the addi instructions
	reg [8:0] addi_seed [0:7];

	initial begin

		addi_seed[0] = 9'h005;
		addi_seed[1] = 9'h1F7;
		addi_seed[2] = 9'h064;
		addi_seed[3] = 9'h19C;
		addi_seed[4] = 9'h0FF;
		addi_seed[5] = 9'h100;
		addi_seed[6] = 9'h04D;
		addi_seed[7] = 9'h021;

		wait (movi_done);
		start_test("addi");

		for (addi_counter = 0; addi_counter < 8; addi_counter = addi_counter + 1) exec_type2(INSTR_MOVI, addi_counter, addi_seed[addi_counter]);

		//+0
		exec_type2(INSTR_ADDI, 3'd0, 9'h000); //5 + 0
		check_value("R0", R0_DUT, 16'd5);

		//result of 0
		exec_type2(INSTR_ADDI, 3'd1, 9'h009); //-9 + 9
		check_value("R1", R1_DUT, 16'd0);

		//pos+pos, the largest immediate
		exec_type2(INSTR_ADDI, 3'd2, 9'h0FF); //100 + 255
		check_value("R2", R2_DUT, 16'd355);

		//neg+neg, the smallest immediate
		exec_type2(INSTR_ADDI, 3'd3, 9'h100); //-100 + -256
		check_value("R3", R3_DUT, 16'hFE9C);

		//pos+neg
		exec_type2(INSTR_ADDI, 3'd4, 9'h1FF); //255 + -1
		check_value("R4", R4_DUT, 16'd254);

		//neg+pos
		exec_type2(INSTR_ADDI, 3'd5, 9'h0FF); //-256 + 255
		check_value("R5", R5_DUT, 16'hFFFF);

		//a+(-a)
		exec_type2(INSTR_ADDI, 3'd7, 9'h1DF); //33 + -33
		check_value("R7", R7_DUT, 16'd0);

		addi_errors = test_errors;
		if (addi_errors != 0) $display("addi: %0d checks failed", addi_errors);

		addi_done = 1'b1;

	end


	//MUL TEST

	integer mul_errors;

	initial begin

		wait (addi_done);
		start_test("mul");

		//pos*neg, 6 * -7 = -42
		run_instr({INSTR_MOVI, 3'd1, 3'd0}, 9'd6);
		run_instr({INSTR_MOVI, 3'd2, 3'd0}, 9'h1F9); //-7
		run_instr({INSTR_MUL, 3'd1, 3'd2}, 9'd0);
		check_value("R1", R1_DUT, 16'hFFD6);

		mul_errors = test_errors;
		if (mul_errors != 0) $display("mul: %0d checks failed", mul_errors);

		mul_done = 1'b1;

	end


	//SSI TEST

	integer ssi_errors;

	initial begin

		wait (mul_done);
		start_test("ssi");

		//shift left, 5 shifted left by 3 = 40
		run_instr({INSTR_MOVI, 3'd3, 3'd0}, 9'd5);
		run_instr({INSTR_SSI, 3'd3, 3'd0}, 9'd3);
		check_value("R3", R3_DUT, 16'd40);

		//shift right, 40 shifted right by 2 = 10
		run_instr({INSTR_SSI, 3'd3, 3'd0}, 9'h1FE); //-2
		check_value("R3", R3_DUT, 16'd10);

		ssi_errors = test_errors;
		if (ssi_errors != 0) $display("ssi: %0d checks failed", ssi_errors);

		ssi_done = 1'b1;

	end


	//DISP TEST

	integer disp_errors;

	initial begin

		wait (ssi_done);
		start_test("disp");

		//display shows R3
		run_instr({INSTR_MOVI, 3'd3, 3'd0}, 9'd10);
		run_instr({INSTR_DISP, 3'd3, 3'd0}, 9'd0);
		check_value("display", display_DUT, 16'd10);

		//display keeps its value after R3 changes, until the next disp
		run_instr({INSTR_ADDI, 3'd3, 3'd0}, 9'd1);
		check_value("display", display_DUT, 16'd10);

		disp_errors = test_errors;
		if (disp_errors != 0) $display("disp: %0d checks failed", disp_errors);

		disp_done = 1'b1;

	end


	//SIMULATION END

	initial begin

		wait (reset_done && tick_done && movi_done && addi_done && mul_done && ssi_done && disp_done);

		$display("==TEST SUMMARY==");
		$display("reset : %0d failed", reset_errors);
		$display("tick FSM : %0d failed", tick_errors);
		$display("movi : %0d failed", movi_errors);
		$display("addi : %0d failed", addi_errors);
		$display("mul : %0d failed", mul_errors);
		$display("ssi : %0d failed", ssi_errors);
		$display("disp : %0d failed", disp_errors);
		$stop;

	end

	// synthesis translate_on

endmodule
