`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment
This file contains a Verilog test bench to test the correctness of the Task 4 processor (memory_proc)
    running programs from an instruction memory, including the bez instruction and the program counter.
The instruction memory is a stand-in for the instruction_ROM IP block that behaves the same way
    (address registered on the falling clock edge, unregistered output), so ModelSim does not need altera_mf.

Please enter your student ID:
-36180513
-

*/
module proc_memory_tb;

	//configuration
	localparam CLK_PERIOD = 10;               //ns
	localparam MAX_CYCLES = 4000;             //clock limit for the memory.mif program in section 7

	//instruction opcodes, from the x72 instruction table
	localparam
		INSTR_DISP = 3'd0,
		INSTR_ADD = 3'd1,
		INSTR_ADDI = 3'd2,
		INSTR_SUB = 3'd3,
		INSTR_MUL = 3'd4,
		INSTR_SSI = 3'd5,
		INSTR_BEZ = 3'd6,
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

	wire [8:0] din;
	wire [15:0] PC;

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

	memory_proc proc_DUT (
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
		.R7(R7),
		.PC(PC)
	);

	//instruction memory stand-in, behaves like instruction_ROM with .clock(~clk)
	reg [8:0] rom [0:65535];
	reg [15:0] rom_addr;

	always @(negedge clk) rom_addr <= PC;
	assign din = rom[rom_addr];

	always #(CLK_PERIOD / 2) clk = ~clk;

	//everything below is simulation only, quartus skips it and modelsim still runs it
	// synthesis translate_off

	integer total_checks;
	integer total_fails;
	integer sec_checks;
	integer sec_fails;
	integer n_sections;

	reg [8*40-1:0] sec_name;
	reg [8*40-1:0] res_name [0:15];
	integer res_checks [0:15];
	integer res_fails [0:15];

	integer i;
	integer k;
	integer n_disp;
	reg [15:0] fib_a;
	reg [15:0] fib_b;
	reg [15:0] fib_next;
	reg [15:0] last_display;

	//helper functions

	//type 1 instruction word, OPCODE Rx Ry
	function [8:0] type1;
		input [2:0] op;
		input [2:0] rx;
		input [2:0] ry;
		begin
			type1 = {op, rx, ry};
		end
	endfunction

	//type 2 instruction word, OPCODE Rx xxx (the immediate is the next word)
	function [8:0] type2;
		input [2:0] op;
		input [2:0] rx;
		begin
			type2 = {op, rx, 3'b000};
		end
	endfunction

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
		input [2:0] t;
		begin
			case (t)
				3'd1 : tick_of = DIN_READ;
				3'd2 : tick_of = BUS_WRITE_ONE;
				3'd3 : tick_of = OPERATE_ALU;
				default : tick_of = BUS_WRITE_TWO;
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

	task check_value;
		input [8*40-1:0] label;
		input [15:0] got;
		input [15:0] expd;
		begin
			if (got === expd) record(1'b1);
			else begin
				record(1'b0);
				$display("  [FAIL] t=%0d ns | %0s | expected %0d (0x%h), got %0d (0x%h)", $time, label, $signed(expd), expd, $signed(got), got);
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
			end
		end
	endtask

	//the stand-in latches the PC on the falling edge, so from then until the next falling edge
	//    din must be the word at the address the PC should hold in this tick
	task check_fetch;
		input [15:0] addr;
		begin
			@(negedge clk);
			#1;
			check_value("din is the word at the expected PC", {7'd0, din}, {7'd0, rom[addr]});
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

	//fill every word with 9'h1FF, which runs as movi r7 (with -1 as its immediate when the next word is filler too),
	//    so running off the end of a program changes R7 as well as failing the PC checks
	task clear_rom;
		integer a;
		begin
			for (a = 0; a < 65536; a = a + 1) rom[a] = 9'h1FF;
		end
	endtask

	//program used by the enable and reset sections
	task load_pause_prog;
		begin
			clear_rom;
			rom[0] = type2(INSTR_MOVI, 3'd1);   rom[1] = 9'd9;           //movi r1, 9
			rom[2] = type1(INSTR_ADD, 3'd1, 3'd1);   rom[3] = 9'h1FF;    //add r1, r1      r1 = 18
			rom[4] = type2(INSTR_DISP, 3'd1);   rom[5] = 9'h1FF;         //disp r1
			rom[6] = type2(INSTR_BEZ, 3'd0);    rom[7] = 9'h1FC;         //bez r0, -4      8 - 8 = 0
		end
	endtask

	//synchronous reset for one clock, leaves the processor at the start of tick 1 with PC = 0
	task do_reset;
		begin
			rst = 1'b1;
			tick_edge;
			rst = 1'b0;
			check_tick(DIN_READ);
			check_value("after reset: PC = 0", PC, 16'd0);
		end
	endtask

	//run one instruction, starting at the start of tick 1 and ending at the start of the next tick 1
	//the PC must step to the immediate word in tick 1 and to the next instruction in tick 2,
	//    and must end at pc_end (pc_start + 2, or the bez target)
	//in every tick the bus must hold what the control unit should select for the opcode
	task run_instr;
		input [15:0] pc_start;
		input [15:0] pc_end;
		reg [8:0] instr;
		reg [8:0] imm;
		reg [2:0] op;
		reg [2:0] rx;
		reg [2:0] ry;
		reg [15:0] sext_imm;
		reg [15:0] result;
		begin
			instr = rom[pc_start];
			imm = rom[pc_start + 16'd1];
			op = instr[8:6];
			rx = instr[5:3];
			ry = instr[2:0];
			sext_imm = {{7{imm[8]}}, imm};

			//tick 1: DIN_READ, nothing is selected so the bus shows R0
			check_tick(DIN_READ);
			check_value("tick 1: PC = instruction address", PC, pc_start);
			check_fetch(pc_start);
			check_value("tick 1: bus = R0 (default)", bus, R0);
			tick_edge;

			//tick 2: BUS_WRITE_ONE, Rx for disp, add, sub and mul, the immediate for the rest
			check_tick(BUS_WRITE_ONE);
			check_value("tick 2: PC = immediate address", PC, pc_start + 16'd1);
			check_fetch(pc_start + 16'd1);
			case (op)
				INSTR_DISP, INSTR_ADD, INSTR_SUB, INSTR_MUL : check_value("tick 2: bus = Rx", bus, dut_reg(rx));
				default : check_value("tick 2: bus = sign-extended immediate", bus, sext_imm);
			endcase
			tick_edge;

			//tick 3: OPERATE_ALU, Ry for add, sub and mul, Rx for addi and ssi, nothing for disp, movi and bez
			check_tick(OPERATE_ALU);
			check_value("tick 3: PC = next instruction", PC, pc_start + 16'd2);
			check_fetch(pc_start + 16'd2);
			case (op)
				INSTR_ADD, INSTR_SUB, INSTR_MUL : check_value("tick 3: bus = Ry", bus, dut_reg(ry));
				INSTR_ADDI, INSTR_SSI : check_value("tick 3: bus = Rx", bus, dut_reg(rx));
				default : check_value("tick 3: bus = R0 (default)", bus, R0);
			endcase
			tick_edge;

			//tick 4: BUS_WRITE_TWO, Rx for bez, nothing for disp and movi, and G (the result) for the alu instructions,
			//    which is saved here and must end up in Rx (the result itself is checked by each section)
			check_tick(BUS_WRITE_TWO);
			check_value("tick 4: PC = next instruction", PC, pc_start + 16'd2);
			check_fetch(pc_start + 16'd2);
			result = bus;
			case (op)
				INSTR_BEZ : check_value("tick 4: bus = Rx", bus, dut_reg(rx));
				INSTR_DISP, INSTR_MOVI : check_value("tick 4: bus = R0 (default)", bus, R0);
				default : ;
			endcase
			tick_edge;

			//back to tick 1, an alu instruction must have written the result on the bus into Rx
			check_tick(DIN_READ);
			check_value("after instruction: PC", PC, pc_end);
			case (op)
				INSTR_ADD, INSTR_ADDI, INSTR_SUB, INSTR_MUL, INSTR_SSI : check_value("after instruction: Rx = tick 4 bus", dut_reg(rx), result);
				default : ;
			endcase
		end
	endtask

	//hold enable low for 3 clocks in tick pause_tick of the instruction at pc_start, nothing may change
	task run_instr_paused;
		input [15:0] pc_start;
		input [15:0] pc_end;
		input [2:0] pause_tick;
		reg [2:0] n;
		reg [15:0] pause_pc;
		reg [15:0] held_display;
		integer p;
		begin
			//the PC is at the instruction in tick 1, the immediate in tick 2 and the next instruction in ticks 3 and 4
			case (pause_tick)
				3'd1 : pause_pc = pc_start;
				3'd2 : pause_pc = pc_start + 16'd1;
				default : pause_pc = pc_start + 16'd2;
			endcase
			for (n = 3'd1; n < pause_tick; n = n + 3'd1) tick_edge;
			check_tick(tick_of(pause_tick));
			check_value("before pause: PC", PC, pause_pc);
			check_fetch(pause_pc);
			held_display = display;
			enable = 1'b0;
			for (p = 0; p < 3; p = p + 1) begin
				tick_edge;
				check_tick(tick_of(pause_tick));
				check_value("paused: PC held", PC, pause_pc);
				check_fetch(pause_pc);
				check_value("paused: display held", display, held_display);
			end
			enable = 1'b1;
			for (n = pause_tick; n <= 3'd4; n = n + 3'd1) tick_edge;
			check_tick(DIN_READ);
			check_value("after paused instruction: PC", PC, pc_end);
		end
	endtask

	//main test sequence
	initial begin

		//initialise
		total_checks = 0;
		total_fails = 0;
		n_sections = 0;
		rst = 1'b1;
		enable = 1'b1;
		clear_rom;

		$display("==================================================");
		$display(" ECE2072 memory_proc testbench (Task 4)");
		$display(" clock period = %0d ns", CLK_PERIOD);
		$display("==================================================");

		//SECTION 1: RESET
		begin_section("Reset");
		tick_edge;
		tick_edge;
		check_tick(DIN_READ);
		check_value("reset: PC = 0", PC, 16'd0);
		check_value("reset: display = 0", display, 16'd0);
		check_value("reset: R0 = 0", R0, 16'd0);
		check_value("reset: R7 = 0", R7, 16'd0);
		rst = 1'b0;
		end_section;

		//SECTION 2: EVERY INSTRUCTION, PC CHECKED ON EVERY TICK
		//the unused word after a type 1 instruction or disp is filled with 9'h1FF (movi r7) to prove it is never run
		begin_section("Every instruction, PC on every tick");
		clear_rom;
		rom[0] = type2(INSTR_MOVI, 3'd1);   rom[1] = 9'd5;           //movi r1, 5
		rom[2] = type2(INSTR_MOVI, 3'd2);   rom[3] = 9'h1FD;         //movi r2, -3
		rom[4] = type1(INSTR_ADD, 3'd1, 3'd2);   rom[5] = 9'h1FF;    //add r1, r2      r1 = 2
		rom[6] = type1(INSTR_SUB, 3'd1, 3'd2);   rom[7] = 9'h1FF;    //sub r1, r2      r1 = 5
		rom[8] = type2(INSTR_ADDI, 3'd1);   rom[9] = 9'd10;          //addi r1, 10     r1 = 15
		rom[10] = type1(INSTR_MUL, 3'd1, 3'd2);  rom[11] = 9'h1FF;   //mul r1, r2      r1 = -45
		rom[12] = type2(INSTR_SSI, 3'd1);   rom[13] = 9'h1FE;        //ssi r1, -2      r1 = -12
		rom[14] = type2(INSTR_SSI, 3'd2);   rom[15] = 9'd3;          //ssi r2, 3       r2 = -24
		rom[16] = type2(INSTR_DISP, 3'd1);  rom[17] = 9'h1FF;        //disp r1         display = -12
		rom[18] = type2(INSTR_MOVI, 3'd3);  rom[19] = 9'd0;          //movi r3, 0
		rom[20] = type2(INSTR_BEZ, 3'd1);   rom[21] = 9'd5;          //bez r1, 5       not taken, r1 = -12
		rom[22] = type2(INSTR_BEZ, 3'd3);   rom[23] = 9'd2;          //bez r3, 2       taken, 24 + 2 * 2 = 28
		rom[24] = type2(INSTR_MOVI, 3'd4);  rom[25] = 9'd1;          //movi r4, 1      skipped
		rom[26] = type2(INSTR_MOVI, 3'd4);  rom[27] = 9'd2;          //movi r4, 2      skipped
		rom[28] = type2(INSTR_BEZ, 3'd3);   rom[29] = 9'd0;          //bez r3, 0       taken, 30 + 0 = 30
		rom[30] = type2(INSTR_MOVI, 3'd5);  rom[31] = 9'd3;          //movi r5, 3      loop counter
		rom[32] = type2(INSTR_MOVI, 3'd6);  rom[33] = 9'd0;          //movi r6, 0
		rom[34] = type2(INSTR_ADDI, 3'd6);  rom[35] = 9'd2;          //addi r6, 2      loop body
		rom[36] = type2(INSTR_ADDI, 3'd5);  rom[37] = 9'h1FF;        //addi r5, -1
		rom[38] = type2(INSTR_BEZ, 3'd5);   rom[39] = 9'd1;          //bez r5, 1       exit to 40 + 2 = 42
		rom[40] = type2(INSTR_BEZ, 3'd3);   rom[41] = 9'h1FC;        //bez r3, -4      back to 42 - 8 = 34
		rom[42] = type2(INSTR_DISP, 3'd6);  rom[43] = 9'h1FF;        //disp r6         display = 6
		rom[44] = type2(INSTR_BEZ, 3'd3);   rom[45] = 9'h1FF;        //bez r3, -1      halt, 46 - 2 = 44
		do_reset;
		run_instr(16'd0, 16'd2);
		check_value("movi r1, 5", R1, 16'd5);
		run_instr(16'd2, 16'd4);
		check_value("movi r2, -3", R2, 16'hFFFD);
		run_instr(16'd4, 16'd6);
		check_value("add r1, r2 = 2", R1, 16'd2);
		run_instr(16'd6, 16'd8);
		check_value("sub r1, r2 = 5", R1, 16'd5);
		run_instr(16'd8, 16'd10);
		check_value("addi r1, 10 = 15", R1, 16'd15);
		run_instr(16'd10, 16'd12);
		check_value("mul r1, r2 = -45", R1, 16'hFFD3);
		run_instr(16'd12, 16'd14);
		check_value("ssi r1, -2 = -12", R1, 16'hFFF4);
		run_instr(16'd14, 16'd16);
		check_value("ssi r2, 3 = -24", R2, 16'hFFE8);
		run_instr(16'd16, 16'd18);
		check_value("disp r1 = -12", display, 16'hFFF4);
		run_instr(16'd18, 16'd20);
		check_value("movi r3, 0", R3, 16'd0);
		run_instr(16'd20, 16'd22);
		check_value("bez not taken: r1 unchanged", R1, 16'hFFF4);
		run_instr(16'd22, 16'd28);
		run_instr(16'd28, 16'd30);
		check_value("bez skipped the movi r4s", R4, 16'd0);
		run_instr(16'd30, 16'd32);
		run_instr(16'd32, 16'd34);
		for (i = 3; i > 0; i = i - 1) begin
			run_instr(16'd34, 16'd36);
			run_instr(16'd36, 16'd38);
			if (i > 1) begin
				run_instr(16'd38, 16'd40);
				run_instr(16'd40, 16'd34);
			end
			else run_instr(16'd38, 16'd42);
		end
		check_value("loop: r5 counted down to 0", R5, 16'd0);
		check_value("loop: r6 = 3 * 2", R6, 16'd6);
		run_instr(16'd42, 16'd44);
		check_value("disp r6 = 6", display, 16'd6);
		for (i = 0; i < 3; i = i + 1) run_instr(16'd44, 16'd44);
		check_value("halted: display still 6", display, 16'd6);
		check_value("halted: r7 never written", R7, 16'd0);
		end_section;

		//SECTION 3: bez ONLY BRANCHES WHEN ALL 16 BITS OF Rx ARE 0
		begin_section("bez tests all 16 bits");
		clear_rom;
		rom[0] = type2(INSTR_MOVI, 3'd1);   rom[1] = 9'h0FF;         //movi r1, 255
		rom[2] = type2(INSTR_ADDI, 3'd1);   rom[3] = 9'd1;           //addi r1, 1      r1 = 0x0100
		rom[4] = type2(INSTR_BEZ, 3'd1);    rom[5] = 9'd10;          //bez r1, 10      not taken
		rom[6] = type2(INSTR_MOVI, 3'd2);   rom[7] = 9'd1;           //movi r2, 1
		rom[8] = type2(INSTR_SSI, 3'd2);    rom[9] = 9'd15;          //ssi r2, 15      r2 = 0x8000
		rom[10] = type2(INSTR_BEZ, 3'd2);   rom[11] = 9'd10;         //bez r2, 10      not taken
		rom[12] = type2(INSTR_MOVI, 3'd3);  rom[13] = 9'h1FF;        //movi r3, -1
		rom[14] = type2(INSTR_BEZ, 3'd3);   rom[15] = 9'd10;         //bez r3, 10      not taken
		rom[16] = type2(INSTR_ADDI, 3'd3);  rom[17] = 9'd1;          //addi r3, 1      r3 = 0
		rom[18] = type2(INSTR_BEZ, 3'd3);   rom[19] = 9'd10;         //bez r3, 10      taken, 20 + 20 = 40
		do_reset;
		run_instr(16'd0, 16'd2);
		run_instr(16'd2, 16'd4);
		check_value("r1 = 0x0100", R1, 16'h0100);
		run_instr(16'd4, 16'd6);
		run_instr(16'd6, 16'd8);
		run_instr(16'd8, 16'd10);
		check_value("r2 = 0x8000", R2, 16'h8000);
		run_instr(16'd10, 16'd12);
		run_instr(16'd12, 16'd14);
		run_instr(16'd14, 16'd16);
		run_instr(16'd16, 16'd18);
		run_instr(16'd18, 16'd40);
		check_value("filler never ran: r7 = 0", R7, 16'd0);
		end_section;

		//SECTION 4: bez OFFSET LIMITS AND PC WRAP-AROUND (r0 is 0 after reset, so bez r0 always branches)
		begin_section("bez offset limits and wrap");
		clear_rom;
		rom[0] = type2(INSTR_BEZ, 3'd0);    rom[1] = 9'h0FF;         //bez r0, 255     2 + 510 = 512
		rom[512] = type2(INSTR_BEZ, 3'd0);  rom[513] = 9'h100;       //bez r0, -256    514 - 512 = 2
		rom[2] = type2(INSTR_BEZ, 3'd0);    rom[3] = 9'h1FE;         //bez r0, -2      4 - 4 = 0
		do_reset;
		run_instr(16'd0, 16'd512);
		run_instr(16'd512, 16'd2);
		run_instr(16'd2, 16'd0);
		clear_rom;
		rom[0] = type2(INSTR_BEZ, 3'd0);    rom[1] = 9'h1FE;         //bez r0, -2      2 - 4 wraps to 65534
		rom[65534] = type2(INSTR_BEZ, 3'd0); rom[65535] = 9'd1;      //bez r0, 1       65536 wraps to 0, + 2 = 2
		rom[2] = type2(INSTR_MOVI, 3'd1);   rom[3] = 9'd7;           //movi r1, 7
		do_reset;
		run_instr(16'd0, 16'd65534);
		run_instr(16'd65534, 16'd2);
		run_instr(16'd2, 16'd4);
		check_value("after wrap: movi r1, 7", R1, 16'd7);
		check_value("filler never ran: r7 = 0", R7, 16'd0);
		end_section;

		//SECTION 5: enable GATING, PAUSE IN EVERY TICK, INCLUDING A TAKEN bez
		begin_section("enable gating (pause in every tick)");
		load_pause_prog;
		for (k = 1; k <= 4; k = k + 1) begin
			do_reset;
			run_instr_paused(16'd0, 16'd2, k[2:0]);
			check_value("paused movi r1, 9", R1, 16'd9);
			run_instr_paused(16'd2, 16'd4, k[2:0]);
			check_value("paused add r1, r1", R1, 16'd18);
			run_instr_paused(16'd4, 16'd6, k[2:0]);
			check_value("paused disp r1", display, 16'd18);
			run_instr_paused(16'd6, 16'd0, k[2:0]);
		end
		end_section;

		//SECTION 6: RESET IN THE MIDDLE OF AN INSTRUCTION, THEN THE PROGRAM MUST RESTART FROM ADDRESS 0
		//the reset lands in tick k of add r1, r1 at address 2 on the second pass, whose next PC would be 4,
		//    so PC = 0 can only come from the reset, and r1 (9) and the display (18) are non-zero beforehand
		begin_section("Reset mid-instruction");
		load_pause_prog;
		for (k = 1; k <= 4; k = k + 1) begin
			do_reset;
			run_instr(16'd0, 16'd2);
			run_instr(16'd2, 16'd4);
			run_instr(16'd4, 16'd6);
			run_instr(16'd6, 16'd0);
			run_instr(16'd0, 16'd2);
			check_value("before reset: r1 = 9", R1, 16'd9);
			check_value("before reset: display = 18", display, 16'd18);
			for (i = 1; i < k; i = i + 1) tick_edge;
			check_tick(tick_of(k[2:0]));
			rst = 1'b1;
			tick_edge;
			rst = 1'b0;
			check_tick(DIN_READ);
			check_value("reset: PC = 0", PC, 16'd0);
			check_value("reset: r1 = 0", R1, 16'd0);
			check_value("reset: display = 0", display, 16'd0);
			run_instr(16'd0, 16'd2);
			check_value("restart: movi r1, 9", R1, 16'd9);
		end
		end_section;

		//SECTION 7: THE memory.mif PROGRAM, FIBONACCI NUMBERS ON THE DISPLAY UNTIL R4 COUNTS DOWN FROM 23
		//this is a copy of the program in memory.mif, so keep the two the same if memory.mif changes
		begin_section("memory.mif program (Fibonacci)");
		clear_rom;
		rom[0] = 9'b010000000;   rom[1] = 9'b000000000;     //addi r0, 0
		rom[2] = 9'b010001000;   rom[3] = 9'b000000001;     //addi r1, 1
		rom[4] = 9'b010010000;   rom[5] = 9'b000000001;     //addi r2, 1
		rom[6] = 9'b010011000;   rom[7] = 9'b000000001;     //addi r3, 1
		rom[8] = 9'b010100000;   rom[9] = 9'b000010111;     //addi r4, 23
		rom[10] = 9'b110100000;  rom[11] = 9'b000001001;    //bez r4, 9
		rom[12] = 9'b000010000;  rom[13] = 9'b000000000;    //disp r2
		rom[14] = 9'b011100001;  rom[15] = 9'b000000000;    //sub r4, r1
		rom[16] = 9'b110100000;  rom[17] = 9'b000000110;    //bez r4, 6
		rom[18] = 9'b001011010;  rom[19] = 9'b000000000;    //add r3, r2
		rom[20] = 9'b000011000;  rom[21] = 9'b000000000;    //disp r3
		rom[22] = 9'b011100001;  rom[23] = 9'b000000000;    //sub r4, r1
		rom[24] = 9'b110100000;  rom[25] = 9'b000000010;    //bez r4, 2
		rom[26] = 9'b001010011;  rom[27] = 9'b000000000;    //add r2, r3
		rom[28] = 9'b110000000;  rom[29] = 9'b111110110;    //bez r0, -10
		rom[30] = 9'b110000000;  rom[31] = 9'b111111111;    //bez r0, -1
		do_reset;
		fib_a = 16'd1;
		fib_b = 16'd2;
		n_disp = 0;
		last_display = display;
		for (i = 0; i < MAX_CYCLES; i = i + 1) begin
			tick_edge;
			//every new value shown must be the next Fibonacci number: 1, 2, 3, 5, 8, ...
			if (display !== last_display) begin
				check_value("display: next Fibonacci value", display, fib_a);
				fib_next = fib_a + fib_b;
				fib_a = fib_b;
				fib_b = fib_next;
				n_disp = n_disp + 1;
				last_display = display;
			end
		end
		check_value("23 values were displayed", n_disp, 16'd23);
		//46368 is above 32767, so the signed HEX4 to HEX0 display shows it as -19168
		check_value("last value = 46368 (0xB520)", display, 16'hB520);
		check_value("r4 counted down to 0", R4, 16'd0);
		while (tick_FSM !== DIN_READ) tick_edge;
		run_instr(16'd30, 16'd30);
		run_instr(16'd30, 16'd30);
		check_value("filler never ran: r7 = 0", R7, 16'd0);
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
		#(CLK_PERIOD * 200000);
		$display("[FAIL] watchdog timeout, testbench did not finish");
		$stop;
	end

	// synthesis translate_on

endmodule
