`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment
This file contains a Verilog test bench to test the correctness of the extended processor.
It tests the Task 3 processor (extended_proc), which supports disp, add, addi, sub, mul, ssi and movi,
    and the decoder that drives HEX4 to HEX0 (display_decoder).

Please enter your student ID:
-Hoorad: 36166804
-

*/
module proc_extension_tb;

	//configuration
	localparam CLK_PERIOD = 10;               //ns
	localparam N_RANDOM = 1000;               //number of random instructions in section 10
	localparam CHECK_UNDEFINED_AS_NOP = 1;    //1 for Task 3 processor (opcode 6 is bez), 0 for later tasks

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

	//dut signals
	reg clk = 1'b0;
	reg rst;
	reg enable;
	reg [8:0] din;

	wire [15:0] bus;
	wire [15:0] display;
	wire [3:0] tick_FSM;
	wire [15:0] R0;
	wire [15:0] R1;
	wire [15:0] R2;
	wire [15:0] R3;
	wire [15:0] R4;
	wire [15:0] R5;
	wire [15:0] R6;
	wire [15:0] R7;

	//FIXED instance renamed from dut to proc_DUT, to match proc_tb.v and components_tb.v
	extended_proc proc_DUT (
		.clk(clk),
		.rst(rst),
		.enable(enable),
		.din(din),
		.bus(bus),
		.display(display),
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

	//decoder signals
	reg [15:0] dec_value;
	wire [7:0] dec_hex0;
	wire [7:0] dec_hex1;
	wire [7:0] dec_hex2;
	wire [7:0] dec_hex3;
	wire [7:0] dec_hex4;

	//FIXED instance renamed from dec_dut to dec_DUT, to match proc_tb.v and components_tb.v
	display_decoder dec_DUT (
		.value(dec_value),
		.hex0(dec_hex0),
		.hex1(dec_hex1),
		.hex2(dec_hex2),
		.hex3(dec_hex3),
		.hex4(dec_hex4)
	);

	always #(CLK_PERIOD / 2) clk = ~clk;

	//everything below is simulation only, quartus skips it and modelsim still runs it
	// synthesis translate_off

	//reference model and bookkeeping
	reg [15:0] exp_r [0:7];        //expected register contents
	reg [15:0] exp_disp;           //expected display register contents
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
	reg cur_single;                //1 for disp, which has only Rx

	integer i;
	integer j;
	integer fact;

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
				INSTR_DISP : mnemonic = "disp";
				INSTR_ADD : mnemonic = "add";
				INSTR_ADDI : mnemonic = "addi";
				INSTR_SUB : mnemonic = "sub";
				INSTR_MUL : mnemonic = "mul";
				INSTR_SSI : mnemonic = "ssi";
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

	//reference for ssi, shifts one place at a time so it shares no logic with the alu
	//+ve immediate shifts left (zero fill), -ve shifts right (sign fill)
	function [15:0] ref_ssi;
		input [8:0] imm;
		input [15:0] val;
		integer amt;
		integer n;
		begin
			amt = $signed(imm);
			ref_ssi = val;
			if (amt > 0) begin
				for (n = 0; n < amt; n = n + 1) ref_ssi = {ref_ssi[14:0], 1'b0};
			end
			else begin
				for (n = 0; n < -amt; n = n + 1) ref_ssi = {ref_ssi[15], ref_ssi[15:1]};
			end
		end
	endfunction

	//reference for one hex display, active low, bit 7 is the decimal point
	function [7:0] hex_ref;
		input [3:0] digit;
		input dp_on;
		reg [6:0] seg;
		begin
			case (digit)
				4'd0 : seg = 7'b1000000;
				4'd1 : seg = 7'b1111001;
				4'd2 : seg = 7'b0100100;
				4'd3 : seg = 7'b0110000;
				4'd4 : seg = 7'b0011001;
				4'd5 : seg = 7'b0010010;
				4'd6 : seg = 7'b0000010;
				4'd7 : seg = 7'b1111000;
				4'd8 : seg = 7'b0000000;
				4'd9 : seg = 7'b0010000;
				default : seg = 7'b1111111;
			endcase
			hex_ref = {~dp_on, seg};
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
			else if (cur_single) $display("         while executing: %0s r%0d", cur_mnem, cur_rx);
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

	//compare all 8 registers and the display register to the reference model, counted as one check
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
			if (display !== exp_disp) begin
				ok = 1'b0;
				$display("  [FAIL] t=%0d ns | %0s | display expected %0d (0x%h), got %0d (0x%h)", $time, label, $signed(exp_disp), exp_disp, $signed(display), display);
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
				check_regs("paused: tick held, regs/display held");
			end
			enable = 1'b1;
			din = restore;
			#1;
		end
	endtask

	//instruction execution tasks
	//each one assumes the processor is at the start of tick 1 and leaves it at the start of tick 1

	//type 1: OPCODE Rx Ry (add, sub, mul)
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
			cur_single = 1'b0;
			before_x = exp_r[rx];
			case (op)
				INSTR_ADD : res = exp_r[rx] + exp_r[ry];
				INSTR_SUB : res = exp_r[rx] - exp_r[ry];
				default : res = exp_r[rx] * exp_r[ry];     //low 16 bits are the same signed or unsigned
			endcase

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
			check_regs("tick 2: regs and display unchanged");
			if (pause_at == 3'd2) begin
				do_pause(BUS_WRITE_ONE, din);
				check_value("tick 2 bus after pause (Rx)", bus, exp_r[rx]);
			end
			tick_edge;

			//tick 3: OPERATE_ALU, Ry on the bus, result into G
			maybe_scramble(scramble);
			check_tick(OPERATE_ALU);
			check_value("tick 3 bus should be Ry", bus, exp_r[ry]);
			check_regs("tick 3: regs and display unchanged");
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
			check_regs("after instruction: all regs and display");
			if (verbose) $display("    %0s r%0d, r%0d : R%0d %0d -> %0d (0x%h)", cur_mnem, rx, ry, rx, $signed(before_x), $signed(res), res);
		end
	endtask

	//type 2: OPCODE Rx xxx, then immediate on din in tick 2 (movi, addi, ssi)
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
			cur_single = 1'b0;
			before_x = exp_r[rx];
			case (op)
				INSTR_ADDI : res = exp_r[rx] + sext;
				INSTR_SSI : res = ref_ssi(imm, exp_r[rx]);
				default : res = sext;
			endcase

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
			check_regs("tick 2: regs and display unchanged");
			if (pause_at == 3'd2) begin
				do_pause(BUS_WRITE_ONE, imm);
				check_value("tick 2 bus after pause (imm)", bus, sext);
			end
			tick_edge;
			if (op == INSTR_MOVI) exp_r[rx] = sext;     //movi writes Rx at the end of tick 2

			//tick 3: OPERATE_ALU, Rx on the bus for addi and ssi
			maybe_scramble(scramble);
			check_tick(OPERATE_ALU);
			if (op != INSTR_MOVI) check_value("tick 3 bus should be Rx", bus, exp_r[rx]);
			check_regs("tick 3: regs and display");
			if (pause_at == 3'd3) begin
				do_pause(OPERATE_ALU, din);
				if (op != INSTR_MOVI) check_value("tick 3 bus after pause (Rx)", bus, exp_r[rx]);
			end
			tick_edge;

			//tick 4: BUS_WRITE_TWO, result on the bus for addi and ssi
			maybe_scramble(scramble);
			check_tick(BUS_WRITE_TWO);
			if (op != INSTR_MOVI) check_value("tick 4 bus should be the result", bus, res);
			check_regs("tick 4: regs and display");
			if (pause_at == 3'd4) begin
				do_pause(BUS_WRITE_TWO, din);
				if (op != INSTR_MOVI) check_value("tick 4 bus after pause (result)", bus, res);
			end
			tick_edge;

			//back to tick 1
			exp_r[rx] = res;
			check_tick(DIN_READ);
			check_regs("after instruction: all regs and display");
			if (verbose) $display("    %0s r%0d, %0d : R%0d %0d -> %0d (0x%h)", cur_mnem, rx, $signed(imm), rx, $signed(before_x), $signed(res), res);
		end
	endtask

	//disp Rx: Rx goes on the bus in tick 2 and into the display register, ticks 3 and 4 are idle
	task exec_disp;
		input [2:0] rx;
		input scramble;
		reg [8:0] instr;
		begin
			next_rand;
			instr = {INSTR_DISP, rx, lfsr[2:0]};     //unused low bits are don't cares
			cur_mnem = mnemonic(INSTR_DISP);
			cur_rx = rx;
			cur_ry = 3'd0;
			cur_has_imm = 1'b0;
			cur_single = 1'b1;

			//tick 1: DIN_READ, instruction on din
			din = instr;
			#1;
			check_tick(DIN_READ);
			if (pause_at == 3'd1) do_pause(DIN_READ, instr);
			tick_edge;

			//tick 2: BUS_WRITE_ONE, Rx on the bus and into the display register
			maybe_scramble(scramble);
			check_tick(BUS_WRITE_ONE);
			check_value("tick 2 bus should be Rx", bus, exp_r[rx]);
			check_regs("tick 2: regs and display unchanged");
			if (pause_at == 3'd2) begin
				do_pause(BUS_WRITE_ONE, din);
				check_value("tick 2 bus after pause (Rx)", bus, exp_r[rx]);
			end
			tick_edge;
			exp_disp = exp_r[rx];     //disp writes the display register at the end of tick 2

			//tick 3 and 4: idle, the display must hold Rx
			maybe_scramble(scramble);
			check_tick(OPERATE_ALU);
			check_regs("tick 3: display holds Rx");
			if (pause_at == 3'd3) do_pause(OPERATE_ALU, din);
			tick_edge;

			maybe_scramble(scramble);
			check_tick(BUS_WRITE_TWO);
			check_regs("tick 4: display holds Rx");
			if (pause_at == 3'd4) do_pause(BUS_WRITE_TWO, din);
			tick_edge;

			//back to tick 1
			check_tick(DIN_READ);
			check_regs("after instruction: all regs and display");
			if (verbose) $display("    disp r%0d : display = %0d (0x%h)", rx, $signed(exp_disp), exp_disp);
		end
	endtask

	//an opcode the Task 3 processor does not implement (bez): must not change any register or the display
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
			cur_single = 1'b0;
			#1;
			for (k = 4'd1; k <= 4'd4; k = k + 4'd1) begin
				check_tick(tick_of(k[2:0]));
				check_regs("undefined opcode: regs and display kept");
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

	//assert reset while the processor is in tick k of the given instruction, then check everything cleared
	task reset_at_tick;
		input [2:0] k;
		input [8:0] instr;
		reg [2:0] n;
		integer q;
		begin
			seed_regs;
			exec_disp(3'd1, 1'b1);     //display holds -9, reset must clear it too
			cur_mnem = mnemonic(instr[8:6]);
			cur_rx = instr[5:3];
			cur_ry = instr[2:0];
			cur_has_imm = 1'b0;
			cur_single = (instr[8:6] == INSTR_DISP);
			din = instr;
			#1;
			for (n = 3'd1; n < k; n = n + 3'd1) tick_edge;
			check_tick(tick_of(k));
			rst = 1'b1;
			tick_edge;
			rst = 1'b0;
			for (q = 0; q < 8; q = q + 1) exp_r[q] = 16'd0;
			exp_disp = 16'd0;
			check_tick(DIN_READ);
			check_regs("after reset: all regs and display are 0");
		end
	endtask

	//check the decoder against a divide and modulus reference (simulation only, never synthesised)
	task check_decoder;
		input [15:0] val;
		integer mag;
		reg neg;
		reg [7:0] e0;
		reg [7:0] e1;
		reg [7:0] e2;
		reg [7:0] e3;
		reg [7:0] e4;
		begin
			neg = val[15];
			mag = neg ? (65536 - val) : val;
			e0 = hex_ref(mag % 10, neg);
			e1 = hex_ref((mag / 10) % 10, neg);
			e2 = hex_ref((mag / 100) % 10, neg);
			e3 = hex_ref((mag / 1000) % 10, neg);
			e4 = hex_ref((mag / 10000) % 10, neg);
			if ((dec_hex0 === e0) && (dec_hex1 === e1) && (dec_hex2 === e2) && (dec_hex3 === e3) && (dec_hex4 === e4)) record(1'b1);
			else begin
				record(1'b0);
				if (sec_fails <= 10) $display("  [FAIL] t=%0d ns | decoder | value %0d (0x%h) | HEX4..HEX0 expected %b %b %b %b %b, got %b %b %b %b %b", $time, $signed(val), val, e4, e3, e2, e1, e0, dec_hex4, dec_hex3, dec_hex2, dec_hex1, dec_hex0);
			end
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
		cur_single = 1'b0;
		for (i = 0; i < 8; i = i + 1) exp_r[i] = 16'd0;
		exp_disp = 16'd0;
		rst = 1'b1;
		enable = 1'b1;
		din = 9'd0;

		$display("==================================================");
		$display(" ECE2072 extended_proc testbench (Task 3)");
		$display(" clock period = %0d ns, random instructions = %0d", CLK_PERIOD, N_RANDOM);
		$display("==================================================");

		//SECTION 1: RESET
		begin_section("Reset");
		tick_edge;
		tick_edge;
		check_tick(DIN_READ);
		check_regs("reset: all regs and display are 0");
		check_value("reset: bus (R0 selected by default)", bus, 16'd0);
		rst = 1'b0;
		end_section;

		//SECTION 2: disp, EVERY REGISTER, HOLDING, AND EXTREME VALUES
		begin_section("disp");
		seed_regs;
		verbose = 1'b1;
		exec_disp(3'd0, 1'b1);
		check_value("disp: R0 = 5", display, 16'd5);
		exec_disp(3'd1, 1'b1);
		check_value("disp: R1 = -9 (0xFFF7)", display, 16'hFFF7);
		exec_disp(3'd2, 1'b1);
		check_value("disp: R2 = 100", display, 16'd100);
		exec_disp(3'd3, 1'b1);
		check_value("disp: R3 = -100 (0xFF9C)", display, 16'hFF9C);
		exec_disp(3'd4, 1'b1);
		check_value("disp: R4 = 255", display, 16'd255);
		exec_disp(3'd5, 1'b1);
		check_value("disp: R5 = -256 (0xFF00)", display, 16'hFF00);
		exec_disp(3'd6, 1'b1);
		check_value("disp: R6 = 77", display, 16'd77);
		exec_disp(3'd7, 1'b1);
		check_value("disp: R7 = 33", display, 16'd33);
		//the display must hold its value through every other instruction
		exec_type1(INSTR_ADD, 3'd0, 3'd1, 1'b1);
		exec_type1(INSTR_SUB, 3'd2, 3'd3, 1'b1);
		exec_type1(INSTR_MUL, 3'd4, 3'd5, 1'b1);
		exec_type2(INSTR_MOVI, 3'd6, 9'h0AA, 1'b1);
		exec_type2(INSTR_ADDI, 3'd0, 9'h00A, 1'b1);
		exec_type2(INSTR_SSI, 3'd2, 9'h002, 1'b1);
		check_value("disp: display holds through all ops", display, 16'd33);
		//the display holds a copy, so changing the register it came from must not change it
		exec_type2(INSTR_ADDI, 3'd7, 9'h001, 1'b1);     //R7 = 34
		check_value("disp: display keeps old R7 (33)", display, 16'd33);
		check_value("disp: R7 = 34", R7, 16'd34);
		exec_disp(3'd7, 1'b1);
		check_value("disp: display updates to R7 (34)", display, 16'd34);
		//extreme values
		exec_type2(INSTR_MOVI, 3'd0, 9'h001, 1'b1);
		exec_type2(INSTR_SSI, 3'd0, 9'h00F, 1'b1);      //1 << 15 = 0x8000
		exec_disp(3'd0, 1'b1);
		check_value("disp: R0 = -32768 (0x8000)", display, 16'h8000);
		exec_type2(INSTR_ADDI, 3'd0, 9'h1FF, 1'b1);     //0x8000 + -1 = 0x7FFF
		exec_disp(3'd0, 1'b1);
		check_value("disp: R0 = 32767 (0x7FFF)", display, 16'h7FFF);
		exec_type2(INSTR_MOVI, 3'd0, 9'h000, 1'b1);
		exec_disp(3'd0, 1'b1);
		check_value("disp: R0 = 0", display, 16'd0);
		verbose = 1'b0;
		end_section;

		//SECTION 3: mul
		begin_section("mul");
		seed_regs;
		verbose = 1'b1;
		exec_type1(INSTR_MUL, 3'd0, 3'd1, 1'b1);     //5 * -9 = -45
		check_value("mul: R0 = -45 (0xFFD3)", R0, 16'hFFD3);
		exec_type1(INSTR_MUL, 3'd2, 3'd3, 1'b1);     //100 * -100 = -10000
		check_value("mul: R2 = -10000 (0xD8F0)", R2, 16'hD8F0);
		exec_type1(INSTR_MUL, 3'd4, 3'd6, 1'b1);     //255 * 77 = 19635
		check_value("mul: R4 = 19635", R4, 16'd19635);
		exec_type1(INSTR_MUL, 3'd5, 3'd5, 1'b1);     //-256 * -256 = 65536, wraps to 0 (Rx = Ry)
		check_value("mul: R5 = 0 (wraps)", R5, 16'd0);
		exec_type1(INSTR_MUL, 3'd7, 3'd7, 1'b1);     //33 * 33 = 1089 (Rx = Ry)
		check_value("mul: R7 = 1089", R7, 16'd1089);
		exec_type1(INSTR_MUL, 3'd1, 3'd3, 1'b1);     //-9 * -100 = 900 (neg * neg)
		check_value("mul: R1 = 900", R1, 16'd900);
		exec_type2(INSTR_MOVI, 3'd6, 9'h000, 1'b1);
		exec_type1(INSTR_MUL, 3'd4, 3'd6, 1'b1);     //19635 * 0 = 0
		check_value("mul: R4 = 0 (x * 0)", R4, 16'd0);
		exec_type2(INSTR_MOVI, 3'd6, 9'h001, 1'b1);
		exec_type1(INSTR_MUL, 3'd2, 3'd6, 1'b1);     //-10000 * 1 = -10000
		check_value("mul: R2 = -10000 (x * 1)", R2, 16'hD8F0);
		exec_type2(INSTR_MOVI, 3'd6, 9'h1FF, 1'b1);
		exec_type1(INSTR_MUL, 3'd2, 3'd6, 1'b1);     //-10000 * -1 = 10000
		check_value("mul: R2 = 10000 (x * -1)", R2, 16'd10000);
		exec_type2(INSTR_MOVI, 3'd0, 9'h0FF, 1'b1);
		exec_type2(INSTR_MOVI, 3'd1, 9'h0FF, 1'b1);
		exec_type1(INSTR_MUL, 3'd0, 3'd1, 1'b1);     //255 * 255 = 65025, wraps to -511
		check_value("mul: R0 = 65025 (0xFE01)", R0, 16'hFE01);
		verbose = 1'b0;
		end_section;

		//SECTION 4: ssi
		begin_section("ssi");
		seed_regs;
		verbose = 1'b1;
		exec_type2(INSTR_SSI, 3'd0, 9'h003, 1'b1);     //5 << 3 = 40
		check_value("ssi: R0 = 40", R0, 16'd40);
		exec_type2(INSTR_SSI, 3'd0, 9'h1FE, 1'b1);     //40 >> 2 = 10
		check_value("ssi: R0 = 10 (right)", R0, 16'd10);
		exec_type2(INSTR_SSI, 3'd1, 9'h1FF, 1'b1);     //-9 >> 1 = -5, arithmetic shift rounds down
		check_value("ssi: R1 = -5 (0xFFFB)", R1, 16'hFFFB);
		exec_type2(INSTR_SSI, 3'd2, 9'h000, 1'b1);     //100 << 0 = 100
		check_value("ssi: R2 = 100 (shift by 0)", R2, 16'd100);
		exec_type2(INSTR_SSI, 3'd7, 9'h00F, 1'b1);     //33 << 15 = 0x8000, upper bits fall off
		check_value("ssi: R7 = 0x8000 (left by 15)", R7, 16'h8000);
		exec_type2(INSTR_SSI, 3'd3, 9'h1F0, 1'b1);     //-100 >> 16 = -1, saturates to the sign
		check_value("ssi: R3 = -1 (right by 16)", R3, 16'hFFFF);
		exec_type2(INSTR_SSI, 3'd4, 9'h010, 1'b1);     //255 << 16 = 0, saturates
		check_value("ssi: R4 = 0 (left by 16)", R4, 16'd0);
		exec_type2(INSTR_SSI, 3'd5, 9'h100, 1'b1);     //-256 >> 256 = -1, most negative immediate
		check_value("ssi: R5 = -1 (right by 256)", R5, 16'hFFFF);
		exec_type2(INSTR_SSI, 3'd6, 9'h0FF, 1'b1);     //77 << 255 = 0, largest positive immediate
		check_value("ssi: R6 = 0 (left by 255)", R6, 16'd0);
		exec_type2(INSTR_MOVI, 3'd0, 9'h0FF, 1'b1);
		exec_type2(INSTR_SSI, 3'd0, 9'h008, 1'b1);     //255 << 8 = 0xFF00
		check_value("ssi: R0 = 0xFF00 (255 << 8)", R0, 16'hFF00);
		exec_type2(INSTR_SSI, 3'd0, 9'h1F8, 1'b1);     //0xFF00 >> 8 = 0xFFFF, sign is kept
		check_value("ssi: R0 = 0xFFFF (0xFF00 >> 8, signed)", R0, 16'hFFFF);
		//sweep every possible immediate on one value, checked against the one-place-at-a-time reference
		exec_type2(INSTR_MOVI, 3'd0, 9'h0A5, 1'b1);
		exec_type2(INSTR_SSI, 3'd0, 9'h008, 1'b1);
		exec_type2(INSTR_ADDI, 3'd0, 9'h0C3, 1'b1);
		check_value("ssi: R0 = 0xA5C3 (sweep value)", R0, 16'hA5C3);
		verbose = 1'b0;
		for (i = 0; i < 512; i = i + 1) begin
			exec_type1(INSTR_SUB, 3'd1, 3'd1, 1'b1);     //R1 = 0
			exec_type1(INSTR_ADD, 3'd1, 3'd0, 1'b1);     //R1 = R0
			exec_type2(INSTR_SSI, 3'd1, i[8:0], 1'b1);
		end
		end_section;

		//SECTION 5: A SMALL PROGRAM, n! WITH movi, mul AND disp (WRAPS AFTER 8!, SHOWING A NEGATIVE NUMBER)
		begin_section("Program: factorials (movi, mul, disp)");
		fact = 1;
		exec_type2(INSTR_MOVI, 3'd0, 9'd1, 1'b1);
		for (i = 2; i <= 9; i = i + 1) begin
			fact = fact * i;
			exec_type2(INSTR_MOVI, 3'd1, i[8:0], 1'b1);
			exec_type1(INSTR_MUL, 3'd0, 3'd1, 1'b1);
			exec_disp(3'd0, 1'b1);
			check_value("factorial: display = n!", display, fact[15:0]);
		end
		end_section;

		//SECTION 6: EXHAUSTIVE REGISTER ADDRESSING FOR THE NEW INSTRUCTIONS (EVERY Rx, EVERY Ry)
		begin_section("Exhaustive Rx / Ry addressing");
		for (i = 0; i < 8; i = i + 1) begin
			for (j = 0; j < 8; j = j + 1) begin
				seed_regs;
				exec_type1(INSTR_MUL, i[2:0], j[2:0], 1'b1);
			end
			seed_regs;
			exec_type2(INSTR_SSI, i[2:0], 9'h1FD, 1'b1);     //-3
			seed_regs;
			exec_disp(i[2:0], 1'b1);
		end
		end_section;

		//SECTION 7: enable GATING, PAUSE IN EVERY TICK OF EVERY INSTRUCTION
		begin_section("enable gating (pause in every tick)");
		for (i = 1; i <= 4; i = i + 1) begin
			pause_at = i[2:0];
			seed_regs;
			exec_type1(INSTR_ADD, 3'd1, 3'd2, 1'b1);
			exec_type1(INSTR_SUB, 3'd3, 3'd4, 1'b1);
			exec_type1(INSTR_MUL, 3'd0, 3'd6, 1'b1);
			exec_type2(INSTR_MOVI, 3'd5, 9'h13B, 1'b1);
			exec_type2(INSTR_ADDI, 3'd6, 9'h021, 1'b1);
			exec_type2(INSTR_SSI, 3'd7, 9'h1FE, 1'b1);
			exec_disp(3'd3, 1'b1);
		end
		pause_at = 3'd0;
		end_section;

		//SECTION 8: RESET IN THE MIDDLE OF AN INSTRUCTION, INCLUDING THE TICK WHERE disp AND movi WRITE
		begin_section("Reset mid-instruction");
		for (i = 1; i <= 4; i = i + 1) begin
			reset_at_tick(i[2:0], {INSTR_ADD, 3'd1, 3'd2});
			reset_at_tick(i[2:0], {INSTR_DISP, 3'd1, 3'd0});
			reset_at_tick(i[2:0], {INSTR_MOVI, 3'd3, 3'd0});
		end
		//the processor must run normally again after a reset
		exec_type2(INSTR_MOVI, 3'd2, 9'h007, 1'b1);
		exec_type2(INSTR_ADDI, 3'd2, 9'h003, 1'b1);
		exec_type1(INSTR_MUL, 3'd2, 3'd2, 1'b1);
		exec_disp(3'd2, 1'b1);
		check_value("post-reset: display = 100", display, 16'd100);
		end_section;

		//SECTION 9: UNDEFINED OPCODE (6, bez) IS A NOP (TASK 3 SPECIFIC DESIGN DECISION)
		if (CHECK_UNDEFINED_AS_NOP) begin
			begin_section("Undefined opcode is a NOP");
			seed_regs;
			exec_disp(3'd4, 1'b1);     //non-zero display that must survive
			for (j = 0; j < 6; j = j + 1) exec_undefined(3'd6, j[0]);
			//a valid instruction must still work straight afterwards
			exec_type1(INSTR_ADD, 3'd0, 3'd1, 1'b1);
			end_section;
		end

		//SECTION 10: CONSTRAINED RANDOM REGRESSION USING AN LFSR
		//random opcode, registers, immediate, din scrambling and pauses, checked against the model
		//the registers are re-seeded every 100 instructions so repeated mul and ssi cannot collapse them all to 0
		begin_section("Random regression (LFSR)");
		seed_regs;
		for (i = 0; i < N_RANDOM; i = i + 1) begin
			if (i % 100 == 99) begin
				pause_at = 3'd0;
				seed_regs;
			end
			next_rand;
			if (lfsr[2:0] == 3'd0) begin
				next_rand;
				pause_at = {1'b0, lfsr[1:0]} + 3'd1;
			end
			else pause_at = 3'd0;
			next_rand;
			case (lfsr[2:0])
				3'd0 : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type1(INSTR_ADD, j[2:0], lfsr[2:0], lfsr[8]);
				end
				3'd1 : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type2(INSTR_ADDI, j[2:0], lfsr[8:0], lfsr[12]);
				end
				3'd2 : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type1(INSTR_SUB, j[2:0], lfsr[2:0], lfsr[8]);
				end
				3'd3 : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type2(INSTR_MOVI, j[2:0], lfsr[8:0], lfsr[12]);
				end
				3'd4 : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type1(INSTR_MUL, j[2:0], lfsr[2:0], lfsr[8]);
				end
				3'd6 : begin
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_disp(j[2:0], lfsr[8]);
				end
				default : begin
					//ssi, half the time with a small shift (-16 to 15) so shifts below the saturation point get tested
					next_rand;
					j = lfsr[2:0];
					next_rand;
					exec_type2(INSTR_SSI, j[2:0], lfsr[9] ? lfsr[8:0] : {{5{lfsr[3]}}, lfsr[3:0]}, lfsr[12]);
				end
			endcase
		end
		pause_at = 3'd0;
		end_section;

		//SECTION 11: DECIMAL DECODER FOR HEX4 TO HEX0, EVERY 16-BIT VALUE
		begin_section("Signed decimal decoder (HEX4-HEX0)");
		dec_value = 16'hFFFF;     //an always @(*) block only runs on a change, so value 0 must not be the first input
		#1;
		for (i = 0; i < 65536; i = i + 1) begin
			dec_value = i[15:0];
			#1;
			check_decoder(i[15:0]);
		end
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