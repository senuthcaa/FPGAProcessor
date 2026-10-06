`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment
This file contains Verilog code to implement the simple x72 processor for Task 2,
    which supports the movi, add, addi and sub instructions.

Please enter your name and student ID:
-Senuth 36180513
-

*/
module simple_proc (
	input wire clk,
	input wire rst,
	input wire enable,
	input wire [8:0] din,

	output wire [15:0] bus,
	output wire [3:0] tick_FSM,

	output wire [15:0] R0,
	output wire [15:0] R1,
	output wire [15:0] R2,
	output wire [15:0] R3,
	output wire [15:0] R4,
	output wire [15:0] R5,
	output wire [15:0] R6,
	output wire [15:0] R7
);

	//instruction opcodes, from the moodle x72 instruction table
	//type 1 is OPCODE Rx Ry, opcode = din[8:6], Rx = din[5:3], Ry = din[2:0]
	//type 2 is OPCODE Rx xxx, the immediate value is presented on din on the next tick
	localparam
		INSTR_ADD = 3'b001,
		INSTR_ADDI = 3'b010,
		INSTR_SUB = 3'b011,
		INSTR_SSI = 3'b101,
		INSTR_MOVI = 3'b111;

	//alu op codes, from components.v
	localparam
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

	wire [15:0] SignExtDin;
	wire [15:0] alu_result;

	//control vars
	reg [3:0] mux_sel;
	reg [2:0] alu_op;

	reg ir_in;
	reg a_in;
	reg g_in;
	reg [7:0] r_in;

	//Rx and Ry are 3-bit register numbers, a leading zero makes them the 4-bit mux select values
	wire [3:0] rx_sel;
	wire [3:0] ry_sel;

	assign rx_sel = {1'b0, IR[5:3]};
	assign ry_sel = {1'b0, IR[2:0]};

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

	//control unit
	//DIN_READ loads din into IR
	//BUS_WRITE_ONE puts the immediate into Rx for movi, and Rx into A for add, addi, sub and ssi
	//OPERATE_ALU puts Ry through the alu into G for add and sub, and the immediate for addi and ssi
	//BUS_WRITE_TWO puts G into Rx
	always @(*) begin
		//default values
		mux_sel = SEL_R0;
		alu_op = OP_ADD;

		ir_in = 1'b0;
		a_in = 1'b0;
		g_in = 1'b0;
		r_in = 8'b00000000;

		if (enable) begin
			case (tick_FSM)

				//fetch instruction
				DIN_READ : ir_in = 1'b1;

				BUS_WRITE_ONE : begin
					case (IR[8:6])
						//movi Rx, immediate, which comes directly from din
						INSTR_MOVI : begin
							mux_sel = SEL_DIN;
							r_in[IR[5:3]] = 1'b1;
						end
						//add, addi, sub and ssi first place Rx into A
						INSTR_ADD, INSTR_ADDI, INSTR_SUB, INSTR_SSI : begin
							mux_sel = rx_sel;
							a_in = 1'b1;
						end
						default : mux_sel = SEL_R0;
					endcase
				end

				OPERATE_ALU : begin
					case (IR[8:6])
						//add Rx, Ry
						INSTR_ADD : begin
							mux_sel = ry_sel;
							alu_op = OP_ADD;
							g_in = 1'b1;
						end
						//addi Rx, immediate
						INSTR_ADDI : begin
							mux_sel = SEL_DIN;
							alu_op = OP_ADD;
							g_in = 1'b1;
						end
						//sub Rx, Ry
						INSTR_SUB : begin
							mux_sel = ry_sel;
							alu_op = OP_SUB;
							g_in = 1'b1;
						end
						//shift Rx by immediate
						INSTR_SSI : begin
							mux_sel = SEL_DIN;
							alu_op = OP_SHF;
							g_in = 1'b1;
						end
						default : mux_sel = SEL_R0;
					endcase
				end

				BUS_WRITE_TWO : begin
					case (IR[8:6])
						//write the result in G back to Rx
						INSTR_ADD, INSTR_ADDI, INSTR_SUB, INSTR_SSI : begin
							mux_sel = SEL_G;
							r_in[IR[5:3]] = 1'b1;
						end
						default : mux_sel = SEL_R0;
					endcase
				end

				default : mux_sel = SEL_R0;

			endcase
		end
	end

endmodule