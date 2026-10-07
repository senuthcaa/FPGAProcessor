`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment
This file contains a Verilog test bench to test the correctness of the processor.
It tests the Task 2 processor (simple_proc), which supports movi, add, addi and sub.

Please enter your student ID:
-36180513
-

*/
module proc_tb;

	//configuration
	localparam CLK_PERIOD = 10;               //ns
	localparam N_RANDOM = 500;                //number of random instructions in section 13
	localparam CHECK_UNDEFINED_AS_NOP = 1;    //1 for Task 2 processor, 0 for later tasks

	//instruction opcodes, from the x72 instruction table
	localparam
		INSTR_ADD = 3'd1,
		INSTR_ADDI = 3'd2,
		INSTR_SUB = 3'd3,
		INSTR_MOVI = 3'd7;

	//tick states, from components.v
	localparam
		DIN_READ = 4'b0001,
		BUS_WRITE_ONE = 4'b0010,
		OPERATE_ALU = 4'b0100,
		BUS_WRITE_TWO = 4'b1000;

	//dut signals
	reg clk = 1'b0;
	reg rst;
	reg enable;
	reg [8:0] din;

	wire [15:0] bus;
	wire [3:0] tick_FSM;
	wire [15:0] R0;
	wire [15:0] R1;
	wire [15:0] R2;
	wire [15:0] R3;
	wire [15:0] R4;
	wire [15:0] R5;
	wire [15:0] R6;
	wire [15:0] R7;

	simple_proc proc_DUT (
		.clk(clk),
		.rst(rst),
		.enable(enable),
		.din(din),
		.bus(bus),
		.tick_FSM(tick_FSM),
		.R0(R0),
		.R1(R1),
		.R2(R2),
		.R3(R3),
		.R4(R4),
		.R5(R5),
		.R6(R6),
		.R7(R7)
	);

	always #(CLK_PERIOD / 2) clk = ~clk;

	//everything below is simulation only, quartus skips it and modelsim still runs it
	// synthesis translate_off

	//reference model and bookkeeping
	reg [15:0] exp_r [0:7];        //expected register contents
	reg [15:0] lfsr;               //16-bit LFSR, x^16 + x^14 + x^13 + x^11 + 1

	integer total_checks;
	integer total_fails;
	integer sec_checks;
	integer sec_fails;
	integer n_sections;

	reg [8*40-1:0] sec_name;
	reg [8*40-1:0] res_name [0:15];
	integer res_checks [0:15];
	integer res_fails [0:15];

	reg verbose;                   //print one line per instruction
	reg [2:0] pause_at;            //0 = no pause, 1 to 4 = hold enable low for 3 clocks in that tick

	//context of the instruction under test, printed with every failure to aid debugging
	reg [8*5-1:0] cur_mnem;
	reg [2:0] cur_rx;
	reg [2:0] cur_ry;
	reg [8:0] cur_imm;
	reg cur_has_imm;

	integer i;
	integer j;

	//helper functions

	function [15:0] dut_reg;
		input [2:0] idx;
		begin
			case (idx)
				3'd0 : dut_reg = R0;
				3'd1 : dut_reg = R1;
				3'd2 : dut_reg = R2;
				3'd3 : dut_reg = R3;
				3'd4 : dut_reg = R4;
				3'd5 : dut_reg = R5;
				3'd6 : dut_reg = R6;
				default : dut_reg = R7;
			endcase
		end
	endfunction

	function [3:0] tick_of;
		input [2:0] k;
		begin
			case (k)
				3'd1 : tick_of = DIN_READ;
				3'd2 : tick_of = BUS_WRITE_ONE;
				3'd3 : tick_of = OPERATE_ALU;
				default : tick_of = BUS_WRITE_TWO;
			endcase
		end
	endfunction

	function [8*5-1:0] mnemonic;
		input [2:0] op;
		begin
			case (op)
				INSTR_ADD : mnemonic = "add";
				INSTR_ADDI : mnemonic = "addi";
				INSTR_SUB : mnemonic = "sub";
				INSTR_MOVI : mnemonic = "movi";
				default : mnemonic = "undef";
			endcase
		end
	endfunction

	//immediates used to seed the registers: 5, -9, 100, -100, 255, -256, 77, 33
	function [8:0] seed_imm;
		input [2:0] idx;
		begin
			case (idx)
				3'd0 : seed_imm = 9'h005;
				3'd1 : seed_imm = 9'h1F7;
				3'd2 : seed_imm = 9'h064;
				3'd3 : seed_imm = 9'h19C;
				3'd4 : seed_imm = 9'h0FF;
				3'd5 : seed_imm = 9'h100;
				3'd6 : seed_imm = 9'h04D;
				default : seed_imm = 9'h021;
			endcase
		end
	endfunction

	//basic tasks

	//wait for a rising edge, then 1ns, so registered outputs have updated
	task tick_edge;
		begin
			@(posedge clk);
			#1;
		end
	endtask

	//advance the LFSR by 16 steps so successive values are uncorrelated
	task next_rand;
		integer s;
		begin
			for (s = 0; s < 16; s = s + 1) lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
		end
	endtask

	task record;
		input pass;
		begin
			total_checks = total_checks + 1;
			sec_checks = sec_checks + 1;
			if (!pass) begin
				total_fails = total_fails + 1;
				sec_fails = sec_fails + 1;
			end
		end
	endtask

	task print_ctx;
		begin
			if (cur_has_imm) $display("         while executing: %0s r%0d, %0d   (immediate word = 9'b%b)", cur_mnem, cur_rx, $signed(cur_imm), cur_imm);
			else $display("         while executing: %0s r%0d, r%0d", cur_mnem, cur_rx, cur_ry);
		end
	endtask

	task check_value;
		input [8*40-1:0] label;
		input [15:0] got;
		input [15:0] expd;
		begin
			if (got === expd) record(1'b1);
			else begin
				record(1'b0);
				$display("  [FAIL] t=%0d ns | %0s | expected %0d (0x%h), got %0d (0x%h)", $time, label, $signed(expd), expd, $signed(got), got);
				print_ctx;
			end
		end
	endtask

	task check_tick;
		input [3:0] expd;
		begin
			if (tick_FSM === expd) record(1'b1);
			else begin
				record(1'b0);
				$display("  [FAIL] t=%0d ns | tick_FSM | expected 4'b%b, got 4'b%b", $time, expd, tick_FSM);
				print_ctx;
			end
		end
	endtask

	//compare all 8 registers to the reference model, counted as one check
	task check_regs;
		input [8*40-1:0] label;
		reg ok;
		reg [3:0] ri;
		begin
			ok = 1'b1;
			for (ri = 4'd0; ri < 4'd8; ri = ri + 4'd1) begin
				if (dut_reg(ri[2:0]) !== exp_r[ri[2:0]]) begin
					ok = 1'b0;
					$display("  [FAIL] t=%0d ns | %0s | R%0d expected %0d (0x%h), got %0d (0x%h)", $time, label, ri[2:0], $signed(exp_r[ri[2:0]]), exp_r[ri[2:0]], $signed(dut_reg(ri[2:0])), dut_reg(ri[2:0]));
				end
			end
			record(ok);
			if (!ok) print_ctx;
		end
	endtask

	task begin_section;
		input [8*40-1:0] name;
		begin
			sec_name = name;
			sec_checks = 0;
			sec_fails = 0;
			n_sections = n_sections + 1;
			$display("--- Section %0d: %0s", n_sections, name);
		end
	endtask

	task end_section;
		begin
			res_name[n_sections - 1] = sec_name;
			res_checks[n_sections - 1] = sec_checks;
			res_fails[n_sections - 1] = sec_fails;
			if (sec_fails == 0) $display("    [PASS] %0d checks passed", sec_checks);
			else $display("    [FAIL] %0d of %0d checks failed", sec_fails, sec_checks);
		end
	endtask

	//drive random values onto din (used in ticks where din must not matter)
	task maybe_scramble;
		input scramble;
		begin
			if (scramble) begin
				next_rand;
				din = lfsr[8:0];
				#1;
			end
		end
	endtask

	//hold enable low for 3 clocks in the current tick, with din scrambled. Nothing may change.
	task do_pause;
		input [3:0] tk;
		input [8:0] restore;
		integer p;
		begin
			enable = 1'b0;
			for (p = 0; p < 3; p = p + 1) begin
				next_rand;
				din = lfsr[8:0];
				tick_edge;
				check_tick(tk);
				check_regs("paused: tick held, regs unchanged");
			end
			enable = 1'b1;
			din = restore;
			#1;
		end
	endtask

	//instruction execution tasks
	//each one assumes the processor is at the start of tick 1 and leaves it at the start of tick 1

	//type 1: OPCODE Rx Ry (add, sub)
	task exec_type1;
		input [2:0] op;
		input [2:0] rx;
		input [2:0] ry;
		input scramble;
		reg [15:0] res;
		reg [8:0] instr;
		reg [15:0] before_x;
		begin
			instr = {op, rx, ry};
			cur_mnem = mnemonic(op);
			cur_rx = rx;
			cur_ry = ry;
			cur_has_imm = 1'b0;
			before_x = exp_r[rx];
			if (op == INSTR_ADD) res = exp_r[rx] + exp_r[ry];
			else res = exp_r[rx] - exp_r[ry];

			//tick 1: DIN_READ, instruction on din
			din = instr;
			#1;
			check_tick(DIN_READ);
			if (pause_at == 3'd1) do_pause(DIN_READ, instr);
			tick_edge;

			//tick 2: BUS_WRITE_ONE, Rx on the bus and into A
			maybe_scramble(scramble);
			check_tick(BUS_WRITE_ONE);
			check_value("tick 2 bus should be Rx", bus, exp_r[rx]);
			check_regs("tick 2: regs unchanged");
			if (pause_at == 3'd2) begin
				do_pause(BUS_WRITE_ONE, din);
				check_value("tick 2 bus after pause (Rx)", bus, exp_r[rx]);
			end
			tick_edge;

			//tick 3: OPERATE_ALU, Ry on the bus, result into G
			maybe_scramble(scramble);
			check_tick(OPERATE_ALU);
			check_value("tick 3 bus should be Ry", bus, exp_r[ry]);
			check_regs("tick 3: regs unchanged");
			if (pause_at == 3'd3) begin
				do_pause(OPERATE_ALU, din);
				check_value("tick 3 bus after pause (Ry)", bus, exp_r[ry]);
			end
			tick_edge;

			//tick 4: BUS_WRITE_TWO, G on the bus and into Rx
			maybe_scramble(scramble);
			check_tick(BUS_WRITE_TWO);
			check_value("tick 4 bus should be the result", bus, res);
			check_regs("tick 4: regs unchanged until edge");
			if (pause_at == 3'd4) begin
				do_pause(BUS_WRITE_TWO, din);
				check_value("tick 4 bus after pause (result)", bus, res);
			end
			tick_edge;

			//back to tick 1, Rx must now hold the result
			exp_r[rx] = res;
			check_tick(DIN_READ);
			check_regs("after instruction: all regs");
			if (verbose) $display("    %0s r%0d, r%0d : R%0d %0d -> %0d (0x%h)", cur_mnem, rx, ry, rx, $signed(before_x), $signed(res), res);
		end
	endtask

	//type 2: OPCODE Rx xxx, then immediate on din in tick 2 (movi, addi)
	task exec_type2;
		input [2:0] op;
		input [2:0] rx;
		input [8:0] imm;
		input scramble;
		reg [15:0] sext;
		reg [15:0] res;
		reg [8:0] instr;
		reg [15:0] before_x;
		begin
			sext = {{7{imm[8]}}, imm};
			next_rand;
			instr = {op, rx, lfsr[2:0]};     //unused low bits are don't cares
			cur_mnem = mnemonic(op);
			cur_rx = rx;
			cur_ry = 3'd0;
			cur_imm = imm;
			cur_has_imm = 1'b1;
			before_x = exp_r[rx];
			if (op == INSTR_ADDI) res = exp_r[rx] + sext;
			else res = sext;

			//tick 1: DIN_READ, instruction on din
			din = instr;
			#1;
			check_tick(DIN_READ);
			if (pause_at == 3'd1) do_pause(DIN_READ, instr);
			tick_edge;

			//tick 2: BUS_WRITE_ONE, immediate on din
			din = imm;
			#1;
			check_tick(BUS_WRITE_ONE);
			check_value("tick 2 bus should be sign-ext imm", bus, sext);
			check_regs("tick 2: regs unchanged");
			if (pause_at == 3'd2) begin
				do_pause(BUS_WRITE_ONE, imm);
				check_value("tick 2 bus after pause (imm)", bus, sext);
			end
			tick_edge;
			if (op == INSTR_MOVI) exp_r[rx] = sext;     //movi writes Rx at the end of tick 2

			//tick 3: OPERATE_ALU
			maybe_scramble(scramble);
			check_tick(OPERATE_ALU);
			if (op == INSTR_ADDI) check_value("tick 3 bus should be Rx", bus, exp_r[rx]);
			check_regs("tick 3: regs");
			if (pause_at == 3'd3) begin
				do_pause(OPERATE_ALU, din);
				if (op == INSTR_ADDI) check_value("tick 3 bus after pause (Rx)", bus, exp_r[rx]);
			end
			tick_edge;

			//tick 4: BUS_WRITE_TWO
			maybe_scramble(scramble);
			check_tick(BUS_WRITE_TWO);
			if (op == INSTR_ADDI) check_value("tick 4 bus should be the result", bus, res);
			check_regs("tick 4: regs");
			if (pause_at == 3'd4) begin
				do_pause(BUS_WRITE_TWO, din);
				if (op == INSTR_ADDI) check_value("tick 4 bus after pause (result)", bus, res);
			end
			tick_edge;

			//back to tick 1
			exp_r[rx] = res;
			check_tick(DIN_READ);
			check_regs("after instruction: all regs");
			if (verbose) $display("    %0s r%0d, %0d : R%0d %0d -> %0d (0x%h)", cur_mnem, rx, $signed(imm), rx, $signed(before_x), $signed(res), res);
		end
	endtask

	//an opcode the Task 2 processor does not implement: must not change any register
	task exec_undefined;
		input [2:0] op;
		input scramble;
		reg [3:0] k;
		begin
			next_rand;
			din = {op, lfsr[5:0]};
			cur_mnem = "undef";
			cur_rx = din[5:3];
			cur_ry = din[2:0];
			cur_has_imm = 1'b0;
			#1;
			for (k = 4'd1; k <= 4'd4; k = k + 4'd1) begin
				check_tick(tick_of(k[2:0]));
				check_regs("undefined opcode: regs unchanged");
				tick_edge;
				maybe_scramble(scramble);
			end
			check_tick(DIN_READ);
		end
	endtask

	//load all 8 registers with known, distinct values: 5, -9, 100, -100, 255, -256, 77, 33
	task seed_regs;
		reg [3:0] sr;
		begin
			for (sr = 4'd0; sr < 4'd8; sr = sr + 4'd1) exec_type2(INSTR_MOVI, sr[2:0], seed_imm(sr[2:0]), 1'b1);
		end
	endtask

	//assert reset while the processor is in tick k of an add instruction, then check everything cleared
	task reset_at_tick;
		input [2:0] k;
		reg [2:0] n;
		begin
			seed_regs;
			cur_mnem = "add";
			cur_rx = 3'd1;
			cur_ry = 3'd2;
			cur_has_imm = 1'b0;
			din = {INSTR_ADD, 3'd1, 3'd2};
			#1;
			for (n = 3'd1; n < k; n = n + 3'd1) tick_edge;
			check_tick(tick_of(k));
			rst = 1'b1;
			tick_edge;
			rst = 1'b0;
			for (n = 3'd0; n < 3'd7; n = n + 3'd1) exp_r[n] = 16'd0;
			exp_r[7] = 16'd0;
			check_tick(DIN_READ);
			check_regs("after reset: all regs are 0");
		end
	endtask

	//main test sequence
	initial begin

		//initialise
		lfsr = 16'hACE1;
		total_checks = 0;
		total_fails = 0;
		n_sections = 0;
		verbose = 1'b0;
		pause_at = 3'd0;
		cur_mnem = "none";
		cur_rx = 3'd0;
		cur_ry = 3'd0;
		cur_imm = 9'd0;
		cur_has_imm = 1'b0;
		for (i = 0; i < 8; i = i + 1) exp_r[i] = 16'd0;
		rst = 1'b1;
		enable = 1'b1;
		din = 9'd0;

		$display("==================================================");
		$display(" ECE2072 simple_proc testbench (Task 2)");
		$display(" clock period = %0d ns, random instructions = %0d", CLK_PERIOD, N_RANDOM);
		$display("==================================================");

		//SECTION 1: RESET
		begin_section("Reset");
		tick_edge;
		tick_edge;
		check_tick(DIN_READ);
		check_regs("reset: all regs are 0");
		check_value("reset: bus (R0 selected by default)", bus, 16'd0);
		rst = 1'b0;
		end_section;

		//SECTION 2: TICK FSM SEQUENCE, ONE-HOT AND CYCLIC, WHILE EXECUTING A HARMLESS add r0, r0
		begin_section("tick_FSM sequence");
		din = {INSTR_ADD, 3'd0, 3'd0};
		#1;
		for (i = 0; i < 12; i = i + 1) begin
			check_tick(tick_of((i % 4) + 1));
			if ((^tick_FSM === 1'bx) || (tick_FSM & (tick_FSM - 4'd1)) != 4'd0 || tick_FSM == 4'd0) begin
				record(1'b0);
				$display("  [FAIL] t=%0d ns | tick_FSM is not one-hot: 4'b%b", $time, tick_FSM);
			end
			else record(1'b1);
			tick_edge;
		end
		end_section;

		//SECTION 3: movi, every register, a spread of immediates
		begin_section("movi");
		verbose = 1'b1;
		exec_type2(INSTR_MOVI, 3'd0, 9'h000, 1'b1);     //0
		exec_type2(INSTR_MOVI, 3'd1, 9'h001, 1'b1);     //1
		exec_type2(INSTR_MOVI, 3'd2, 9'h0FF, 1'b1);     //255, largest positive
		exec_type2(INSTR_MOVI, 3'd3, 9'h1FF, 1'b1);     //-1
		exec_type2(INSTR_MOVI, 3'd4, 9'h100, 1'b1);     //-256, most negative
		exec_type2(INSTR_MOVI, 3'd5, 9'h07F, 1'b1);     //127
		exec_type2(INSTR_MOVI, 3'd6, 9'h181, 1'b1);     //-127
		exec_type2(INSTR_MOVI, 3'd7, 9'h0AA, 1'b1);     //170
		verbose = 1'b0;
		check_value("movi: R0 = 0", R0, 16'd0);
		check_value("movi: R1 = 1", R1, 16'd1);
		check_value("movi: R2 = 255", R2, 16'd255);
		check_value("movi: R3 = -1 (0xFFFF)", R3, 16'hFFFF);
		check_value("movi: R4 = -256 (0xFF00)", R4, 16'hFF00);
		check_value("movi: R5 = 127", R5, 16'd127);
		check_value("movi: R6 = -127 (0xFF81)", R6, 16'hFF81);
		check_value("movi: R7 = 170", R7, 16'd170);
		exec_type2(INSTR_MOVI, 3'd3, 9'h055, 1'b1);     //overwrite a non-zero register
		check_value("movi: overwrite R3 = 85", R3, 16'd85);
		end_section;

		//SECTION 4: add
		begin_section("add");
		seed_regs;
		verbose = 1'b1;
		exec_type1(INSTR_ADD, 3'd0, 3'd1, 1'b1);     //5 + -9 = -4
		check_value("add: R0 = -4 (0xFFFC)", R0, 16'hFFFC);
		exec_type1(INSTR_ADD, 3'd2, 3'd3, 1'b1);     //100 + -100 = 0
		check_value("add: R2 = 0", R2, 16'd0);
		exec_type1(INSTR_ADD, 3'd4, 3'd6, 1'b1);     //255 + 77 = 332
		check_value("add: R4 = 332", R4, 16'd332);
		exec_type1(INSTR_ADD, 3'd5, 3'd5, 1'b1);     //-256 + -256 = -512 (Rx = Ry)
		check_value("add: R5 = -512 (0xFE00)", R5, 16'hFE00);
		exec_type1(INSTR_ADD, 3'd7, 3'd7, 1'b1);     //33 + 33 = 66 (Rx = Ry)
		check_value("add: R7 = 66", R7, 16'd66);
		exec_type1(INSTR_ADD, 3'd7, 3'd0, 1'b1);     //66 + -4 = 62
		check_value("add: R7 = 62", R7, 16'd62);
		verbose = 1'b0;
		end_section;

		//SECTION 5: addi
		begin_section("addi");
		seed_regs;
		verbose = 1'b1;
		exec_type2(INSTR_ADDI, 3'd0, 9'h000, 1'b1);     //5 + 0 = 5
		check_value("addi: R0 = 5", R0, 16'd5);
		exec_type2(INSTR_ADDI, 3'd1, 9'h009, 1'b1);     //-9 + 9 = 0
		check_value("addi: R1 = 0", R1, 16'd0);
		exec_type2(INSTR_ADDI, 3'd2, 9'h0FF, 1'b1);     //100 + 255 = 355
		check_value("addi: R2 = 355", R2, 16'd355);
		exec_type2(INSTR_ADDI, 3'd3, 9'h100, 1'b1);     //-100 + -256 = -356
		check_value("addi: R3 = -356 (0xFE9C)", R3, 16'hFE9C);
		exec_type2(INSTR_ADDI, 3'd4, 9'h1FF, 1'b1);     //255 + -1 = 254
		check_value("addi: R4 = 254", R4, 16'd254);
		exec_type2(INSTR_ADDI, 3'd5, 9'h0FF, 1'b1);     //-256 + 255 = -1
		check_value("addi: R5 = -1 (0xFFFF)", R5, 16'hFFFF);
		exec_type2(INSTR_ADDI, 3'd7, 9'h1DF, 1'b1);     //33 + -33 = 0
		check_value("addi: R7 = 0", R7, 16'd0);
		verbose = 1'b0;
		end_section;

		//SECTION 6: sub
		begin_section("sub");
		seed_regs;
		verbose = 1'b1;
		exec_type1(INSTR_SUB, 3'd0, 3'd1, 1'b1);     //5 - -9 = 14
		check_value("sub: R0 = 14", R0, 16'd14);
		exec_type1(INSTR_SUB, 3'd2, 3'd3, 1'b1);     //100 - -100 = 200
		check_value("sub: R2 = 200", R2, 16'd200);
		exec_type1(INSTR_SUB, 3'd4, 3'd4, 1'b1);     //255 - 255 = 0 (Rx = Ry)
		check_value("sub: R4 = 0", R4, 16'd0);
		exec_type1(INSTR_SUB, 3'd5, 3'd6, 1'b1);     //-256 - 77 = -333
		check_value("sub: R5 = -333 (0xFEB3)", R5, 16'hFEB3);
		exec_type1(INSTR_SUB, 3'd7, 3'd0, 1'b1);     //33 - 14 = 19
		check_value("sub: R7 = 19", R7, 16'd19);
		exec_type1(INSTR_SUB, 3'd1, 3'd7, 1'b1);     //-9 - 19 = -28 (operand order matters)
		check_value("sub: R1 = -28 (0xFFE4)", R1, 16'hFFE4);
		verbose = 1'b0;
		end_section;

		//SECTION 7: OVERFLOW AND UNDERFLOW WRAP-AROUND
		begin_section("Overflow / underflow wrap");
		verbose = 1'b1;
		exec_type2(INSTR_MOVI, 3'd0, 9'h0FF, 1'b1);     //255
		for (i = 0; i < 7; i = i + 1) exec_type1(INSTR_ADD, 3'd0, 3'd0, 1'b1);     //255 * 128 = 32640
		check_value("wrap: R0 = 32640 (0x7F80)", R0, 16'h7F80);
		exec_type2(INSTR_ADDI, 3'd0, 9'h07F, 1'b1);     //+127 = 32767
		check_value("wrap: R0 = 32767 (0x7FFF)", R0, 16'h7FFF);
		exec_type2(INSTR_MOVI, 3'd1, 9'h001, 1'b1);
		exec_type1(INSTR_ADD, 3'd0, 3'd1, 1'b1);        //32767 + 1 wraps to -32768
		check_value("wrap: add 32767 + 1 = 0x8000", R0, 16'h8000);
		exec_type2(INSTR_ADDI, 3'd0, 9'h1FF, 1'b1);     //-32768 + -1 wraps to 32767
		check_value("wrap: addi 0x8000 + -1 = 0x7FFF", R0, 16'h7FFF);
		exec_type2(INSTR_ADDI, 3'd0, 9'h0FF, 1'b1);     //32767 + 255 wraps to -32514
		check_value("wrap: addi 0x7FFF + 255 = 0x80FE", R0, 16'h80FE);
		exec_type2(INSTR_MOVI, 3'd2, 9'h000, 1'b1);
		exec_type1(INSTR_SUB, 3'd2, 3'd1, 1'b1);        //0 - 1 = -1
		check_value("wrap: sub 0 - 1 = 0xFFFF", R2, 16'hFFFF);
		exec_type1(INSTR_SUB, 3'd0, 3'd2, 1'b1);        //0x80FE - (-1) = 0x80FF
		check_value("wrap: sub 0x80FE - -1 = 0x80FF", R0, 16'h80FF);
		exec_type2(INSTR_MOVI, 3'd3, 9'h100, 1'b1);     //-256
		exec_type1(INSTR_SUB, 3'd4, 3'd4, 1'b1);        //x - x = 0
		exec_type1(INSTR_SUB, 3'd4, 3'd1, 1'b1);        //0 - 1 = -1
		exec_type1(INSTR_ADD, 3'd3, 3'd3, 1'b1);        //-512
		check_value("wrap: add -256 + -256 = 0xFE00", R3, 16'hFE00);
		verbose = 1'b0;
		end_section;

		//SECTION 8: din HELD (NOT SCRAMBLED), THE OTHER OPERATING MODE
		begin_section("din held (no scrambling)");
		seed_regs;
		exec_type2(INSTR_MOVI, 3'd1, 9'h12C, 1'b0);     //-212
		check_value("held: movi R1 = -212 (0xFF2C)", R1, 16'hFF2C);
		exec_type2(INSTR_ADDI, 3'd2, 9'h02A, 1'b0);     //100 + 42 = 142
		check_value("held: addi R2 = 142", R2, 16'd142);
		exec_type1(INSTR_ADD, 3'd3, 3'd4, 1'b0);        //-100 + 255 = 155
		check_value("held: add R3 = 155", R3, 16'd155);
		exec_type1(INSTR_SUB, 3'd5, 3'd6, 1'b0);        //-256 - 77 = -333
		check_value("held: sub R5 = -333 (0xFEB3)", R5, 16'hFEB3);
		end_section;

		//SECTION 9: EXHAUSTIVE REGISTER ADDRESSING (EVERY Rx, EVERY Ry)
		begin_section("Exhaustive Rx / Ry addressing");
		for (i = 0; i < 8; i = i + 1) begin
			for (j = 0; j < 8; j = j + 1) begin
				seed_regs;
				exec_type1(INSTR_ADD, i[2:0], j[2:0], 1'b1);
				seed_regs;
				exec_type1(INSTR_SUB, i[2:0], j[2:0], 1'b1);
			end
			seed_regs;
			exec_type2(INSTR_MOVI, i[2:0], 9'h1A5, 1'b1);     //-91
			seed_regs;
			exec_type2(INSTR_ADDI, i[2:0], 9'h05A, 1'b1);     //+90
		end
		end_section;

		//SECTION 10: enable GATING, PAUSE IN EVERY TICK OF EVERY INSTRUCTION
		begin_section("enable gating (pause in every tick)");
		for (i = 1; i <= 4; i = i + 1) begin
			pause_at = i[2:0];
			seed_regs;
			exec_type1(INSTR_ADD, 3'd1, 3'd2, 1'b1);
			exec_type1(INSTR_SUB, 3'd3, 3'd4, 1'b1);
			exec_type2(INSTR_MOVI, 3'd5, 9'h13B, 1'b1);
			exec_type2(INSTR_ADDI, 3'd6, 9'h021, 1'b1);
		end
		pause_at = 3'd0;
		end_section;

		//SECTION 11: RESET IN THE MIDDLE OF AN INSTRUCTION
		begin_section("Reset mid-instruction");
		for (i = 1; i <= 4; i = i + 1) reset_at_tick(i[2:0]);
		//the processor must run normally again after a reset
		exec_type2(INSTR_MOVI, 3'd2, 9'h007, 1'b1);
		exec_type2(INSTR_ADDI, 3'd2, 9'h003, 1'b1);
		check_value("post-reset: R2 = 10", R2, 16'd10);
		exec_type1(INSTR_ADD, 3'd3, 3'd2, 1'b1);
		check_value("post-reset: R3 = 10", R3, 16'd10);
		exec_type1(INSTR_SUB, 3'd3, 3'd2, 1'b1);
		check_value("post-reset: R3 = 0", R3, 16'd0);
		end_section;

		//SECTION 12: UNDEFINED OPCODES ARE NOPs (TASK 2 SPECIFIC DESIGN DECISION)
		if (CHECK_UNDEFINED_AS_NOP) begin
			begin_section("Undefined opcodes are NOPs");
			seed_regs;
			for (i = 0; i < 4; i = i + 1) begin
				for (j = 0; j < 3; j = j + 1) begin
					case (i)
						0 : exec_undefined(3'd0, 1'b1);
						1 : exec_undefined(3'd4, 1'b1);
						2 : exec_undefined(3'd5, 1'b0);
						default : exec_undefined(3'd6, 1'b1);
					endcase
				end
			end
			//a valid instruction must still work straight afterwards
			exec_type1(INSTR_ADD, 3'd0, 3'd1, 1'b1);
			end_section;
		end

		//SECTION 13: CONSTRAINED RANDOM REGRESSION USING AN LFSR
		//random opcode, registers, immediate, din scrambling and pauses, checked against the model
		begin_section("Random regression (LFSR)");
		seed_regs;
		for (i = 0; i < N_RANDOM; i = i + 1) begin
			next_rand;
			if (lfsr[2:0] == 3'd0) begin
				next_rand;
				pause_at = {1'b0, lfsr[1:0]} + 3'd1;
			end
			else pause_at = 3'd0;
			next_rand;
			case (lfsr[1:0])
				2'd0 : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type1(INSTR_ADD, j[2:0], lfsr[2:0], lfsr[8]);
				end
				2'd1 : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type2(INSTR_ADDI, j[2:0], lfsr[8:0], lfsr[12]);
				end
				2'd2 : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type1(INSTR_SUB, j[2:0], lfsr[2:0], lfsr[8]);
				end
				default : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type2(INSTR_MOVI, j[2:0], lfsr[8:0], lfsr[12]);
				end
			endcase
		end
		pause_at = 3'd0;
		end_section;

		//SUMMARY
		$display("");
		$display("==================================================");
		$display(" TEST SUMMARY");
		$display("==================================================");
		for (i = 0; i < n_sections; i = i + 1) begin
			if (res_fails[i] == 0) $display("  PASS  %0s (%0d checks)", res_name[i], res_checks[i]);
			else $display("  FAIL  %0s (%0d of %0d checks failed)", res_name[i], res_fails[i], res_checks[i]);
		end
		$display("--------------------------------------------------");
		if (total_fails == 0) $display(" ALL %0d CHECKS PASSED", total_checks);
		else $display(" %0d OF %0d CHECKS FAILED, see the [FAIL] lines above", total_fails, total_checks);
		$display("==================================================");
		$stop;     //use $finish instead when running outside modelsim

	end

	//watchdog, stops the simulation if the testbench ever stalls
	initial begin
		#(CLK_PERIOD * 2000000);
		$display("[FAIL] watchdog timeout, testbench did not finish");
		$stop;
	end

	// synthesis translate_on

endmodule