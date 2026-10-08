`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment
//FIXED description was copied from proc_extension.v and still said Task 3
This file contains Verilog code to implement the x72 processor for Task 4,
    which adds the program counter (PC output to the instruction memory) and the bez instruction to the Task 3 processor.

Please enter your name and student ID:
-Hoorad 36166804
-

*/
module memory_proc (
	input wire clk,
	input wire rst,
	input wire enable,
	input wire [8:0] din,

	output wire [15:0] bus,
	output wire [15:0] display,
	output wire [3:0] tick_FSM,

	output wire [15:0] R0,
	output wire [15:0] R1,
	output wire [15:0] R2,
	output wire [15:0] R3,
	output wire [15:0] R4,
	output wire [15:0] R5,
	output wire [15:0] R6,
	output wire [15:0] R7,
	
	output wire [15:0] PC //program counter: max value of 0xFFFF words
);

	//FIXED comment brought in line with proc_extension.v, and documents the 2-word instruction layout the PC relies on
	//instruction opcodes, from the moodle x72 instruction table
	//type 1 is OPCODE Rx Ry, opcode = din[8:6], Rx = din[5:3], Ry = din[2:0]
	//type 2 is OPCODE Rx xxx, the immediate value is the next word in the instruction memory
	//every instruction takes 2 words (type 1 and disp are followed by an unused word), so the PC moves by 2 per instruction
	localparam
		INSTR_DISP = 3'b000,
		INSTR_ADD = 3'b001,
		INSTR_ADDI = 3'b010,
		INSTR_SUB = 3'b011,
		INSTR_MUL = 3'b100,
		INSTR_SSI = 3'b101,
		INSTR_BEZ = 3'b110,
		INSTR_MOVI = 3'b111;

	//alu op codes, from components.v
	localparam
		OP_MUL = 3'b000,
		OP_ADD = 3'b001,
		OP_SUB = 3'b010,
		OP_SHF = 3'b011;

	//tick states, from components.v
	localparam
		DIN_READ = 4'b0001,
		BUS_WRITE_ONE = 4'b0010,
		OPERATE_ALU = 4'b0100,
		BUS_WRITE_TWO = 4'b1000;

	//mux select codes, from components.v
	localparam
		SEL_R0 = 4'd0,
		SEL_R1 = 4'd1,
		SEL_R2 = 4'd2,
		SEL_R3 = 4'd3,
		SEL_R4 = 4'd4,
		SEL_R5 = 4'd5,
		SEL_R6 = 4'd6,
		SEL_R7 = 4'd7,
		SEL_G = 4'd8,
		SEL_DIN = 4'd9;

	//datapath vars
	wire [8:0] IR;
	wire [15:0] A;
	wire [15:0] G;
	wire [15:0] B;

	wire [15:0] SignExtDin;
	wire [15:0] alu_result;

	//control vars
	reg [3:0] mux_sel;
	reg [2:0] alu_op;

	reg ir_in;
	reg a_in;
	reg g_in;
	reg h_in;
	reg b_in;
	reg [7:0] r_in;

	//Rx and Ry are 3-bit register numbers, a leading zero makes them the 4-bit mux select values
	wire [2:0] instruction; //stores instruction opcode
	wire [3:0] rx_sel;
	wire [3:0] ry_sel;
	
	assign instruction = IR[8:6];
	assign rx_sel = {1'b0, IR[5:3]};
	assign ry_sel = {1'b0, IR[2:0]};
	
	//PC variables
	reg pc_in;
	reg branch;
	
	wire [15:0] PC_count;
	wire [15:0] PC_branch;
	wire [15:0] PC_next;
	
	assign PC_count = PC + 16'd1;
	//FIXED the bez immediate counts instructions, not words (memory.mif uses 9, 6, 2, -10 and -1 this way),
	//FIXED and each instruction is 2 words, so the offset is doubled. PC already points to the next instruction here
	assign PC_branch = PC + {B[14:0], 1'b0};
	assign PC_next = branch ? PC_branch : PC_count; //2-1 mux

	//instantiate modules
	sign_extend sign_ext_inst (
		.in(din),
		.ext(SignExtDin)
	);

	tick_FSM tick_inst (
		.rst(rst),
		.clk(clk),
		.enable(enable),
		.tick(tick_FSM)
	);

	multiplexer mux_inst (
		.SignExtDin(SignExtDin),
		.R0(R0),
		.R1(R1),
		.R2(R2),
		.R3(R3),
		.R4(R4),
		.R5(R5),
		.R6(R6),
		.R7(R7),
		.G(G),
		.sel(mux_sel),
		.Bus(bus)
	);

	ALU alu_inst (
		.input_a(A),
		.input_b(bus),
		.alu_op(alu_op),
		.result(alu_result)
	);

	//instruction register
	register_n #(.N(9)) reg_IR (
		.data_in(din),
		.r_in(ir_in),
		.clk(clk),
		.Q(IR),
		.rst(rst)
	);

	//A register
	register_n #(.N(16)) reg_A (
		.data_in(bus),
		.r_in(a_in),
		.clk(clk),
		.Q(A),
		.rst(rst)
	);

	//G register
	register_n #(.N(16)) reg_G (
		.data_in(alu_result),
		.r_in(g_in),
		.clk(clk),
		.Q(G),
		.rst(rst)
	);

	//H register, holds the display value until the next disp instruction
	register_n #(.N(16)) reg_H (
		.data_in(bus),
		.r_in(h_in),
		.clk(clk),
		.Q(display),
		.rst(rst)
	);
	
	//B register, holds the immediate value to branch by
	register_n #(.N(16)) reg_B (
		.data_in(bus),
		.r_in(b_in),
		.clk(clk),
		.Q(B),
		.rst(rst)
	);
	
	//PC register, stores program counter
	register_n #(.N(16)) reg_PC (
		.data_in(PC_next),
		.r_in(pc_in),
		.clk(clk),
		.Q(PC),
		.rst(rst)
	);

	//general purpose registers
	register_n #(.N(16)) reg_R0 (
		.data_in(bus),
		.r_in(r_in[0]),
		.clk(clk),
		.Q(R0),
		.rst(rst)
	);

	register_n #(.N(16)) reg_R1 (
		.data_in(bus),
		.r_in(r_in[1]),
		.clk(clk),
		.Q(R1),
		.rst(rst)
	);

	register_n #(.N(16)) reg_R2 (
		.data_in(bus),
		.r_in(r_in[2]),
		.clk(clk),
		.Q(R2),
		.rst(rst)
	);

	register_n #(.N(16)) reg_R3 (
		.data_in(bus),
		.r_in(r_in[3]),
		.clk(clk),
		.Q(R3),
		.rst(rst)
	);

	register_n #(.N(16)) reg_R4 (
		.data_in(bus),
		.r_in(r_in[4]),
		.clk(clk),
		.Q(R4),
		.rst(rst)
	);

	register_n #(.N(16)) reg_R5 (
		.data_in(bus),
		.r_in(r_in[5]),
		.clk(clk),
		.Q(R5),
		.rst(rst)
	);

	register_n #(.N(16)) reg_R6 (
		.data_in(bus),
		.r_in(r_in[6]),
		.clk(clk),
		.Q(R6),
		.rst(rst)
	);

	register_n #(.N(16)) reg_R7 (
		.data_in(bus),
		.r_in(r_in[7]),
		.clk(clk),
		.Q(R7),
		.rst(rst)
	);

	
	//FIXED replaced the banner (it ended in a backslash) with a description in the same style as proc_extension.v
	//control unit
	//DIN_READ loads din into IR and moves the PC to the immediate word
	//BUS_WRITE_ONE moves the PC to the next instruction, and puts Rx into H for disp, the immediate into Rx for movi,
	//    the immediate into A for addi and ssi, Rx into A for add, sub and mul, and the immediate into B for bez
	//OPERATE_ALU puts Ry through the alu into G for add, sub and mul, and Rx for addi and ssi
	//BUS_WRITE_TWO puts G into Rx, or for bez puts Rx on the bus and moves the PC by 2 * B when it is 0
	always @(*) begin
		//default values
		mux_sel = SEL_R0;
		alu_op = OP_ADD;

		ir_in = 1'b0;
		a_in = 1'b0;
		g_in = 1'b0;
		h_in = 1'b0;
		b_in = 1'b0;
		r_in = 8'b00000000;
		
		pc_in = 1'b0;
		branch = 1'b0;
		
		if (enable) begin
			case (tick_FSM)

				//fetch instruction
				DIN_READ : begin
					pc_in = 1'b1;
					ir_in = 1'b1;
				end

				BUS_WRITE_ONE : begin
					pc_in = 1'b1;
					case (instruction)
						//disp Rx, Rx goes on the bus and into the display register
						INSTR_DISP : begin
							mux_sel = rx_sel;
							h_in = 1'b1;
						end
						//movi Rx, immediate, which comes directly from din
						INSTR_MOVI : begin
							mux_sel = SEL_DIN;
							r_in[IR[5:3]] = 1'b1;
						end
						//addi and ssi place the immediate into A
						INSTR_ADDI, INSTR_SSI : begin
							mux_sel = SEL_DIN;
							a_in = 1'b1;
						end
						//add, sub and mul place Rx into A
						INSTR_ADD, INSTR_SUB, INSTR_MUL : begin
							mux_sel = rx_sel;
							a_in = 1'b1;
						end
						INSTR_BEZ : begin
							mux_sel = SEL_DIN;
							//FIXED typo, stores -> stored
							b_in = 1'b1; //the bez immediate value will be stored in register B
						end
						default : mux_sel = SEL_R0;
					endcase
				end

				OPERATE_ALU : begin
					case (instruction)
						//add Rx, Ry
						INSTR_ADD : begin
							mux_sel = ry_sel;
							alu_op = OP_ADD;
							g_in = 1'b1;
						end
						//addi Rx, immediate, A already holds the immediate so Rx goes on the bus
						INSTR_ADDI : begin
							mux_sel = rx_sel;
							alu_op = OP_ADD;
							g_in = 1'b1;
						end
						//sub Rx, Ry
						INSTR_SUB : begin
							mux_sel = ry_sel;
							alu_op = OP_SUB;
							g_in = 1'b1;
						end
						//mul Rx, Ry
						INSTR_MUL : begin
							mux_sel = ry_sel;
							alu_op = OP_MUL;
							g_in = 1'b1;
						end
						//ssi Rx, immediate, A already holds the shift amount so Rx goes on the bus to be shifted
						INSTR_SSI : begin
							mux_sel = rx_sel;
							alu_op = OP_SHF;
							g_in = 1'b1;
						end
						default : mux_sel = SEL_R0;
					endcase
				end

				BUS_WRITE_TWO : begin
					case (instruction)
						//write the result in G back to Rx
						INSTR_ADD, INSTR_ADDI, INSTR_SUB, INSTR_MUL, INSTR_SSI : begin
							mux_sel = SEL_G;
							r_in[IR[5:3]] = 1'b1;
						end
						//check bus (which has value of Rx) to see whether to branch or not.
						INSTR_BEZ : begin
							mux_sel = rx_sel;
							if (bus == 16'd0) begin
								branch = 1'b1;
								pc_in = 1'b1;
							end
						end
						default : mux_sel = SEL_R0;
					endcase
				end

				default : mux_sel = SEL_R0;

			endcase
		end
	end

endmodule
