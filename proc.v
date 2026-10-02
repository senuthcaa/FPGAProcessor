`timescale 1ns/1ps

// ECE2072 Task 2 simple x72 processor
//
// Supported instructions:
//   movi
//   add
//   addi
//   sub
//
// Instruction format:
// Type 1:
//   OPCODE Rx Ry
//   DIN[8:6] = opcode
//   DIN[5:3] = Rx
//   DIN[2:0] = Ry
//
// Type 2:
//   OPCODE Rx xxx
//   Immediate value is presented on DIN on the next tick.

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

// Opcode definitions from Moodle x72 instruction table

    localparam [2:0] OP_ADD  = 3'b001;
    localparam [2:0] OP_ADDI = 3'b010;
    localparam [2:0] OP_SUB  = 3'b011;
    localparam [2:0] OP_MOVI = 3'b111;

    // ------------------------------------------------------------
    // ALU operation codes from components.v
    // ------------------------------------------------------------

    localparam [2:0] ALU_ADD = 3'b001;
    localparam [2:0] ALU_SUB = 3'b010;

    // ------------------------------------------------------------
    // Bus multiplexer select codes from components.v
    // ------------------------------------------------------------

    localparam [3:0] BUS_R0  = 4'd0;
    localparam [3:0] BUS_R1  = 4'd1;
    localparam [3:0] BUS_R2  = 4'd2;
    localparam [3:0] BUS_R3  = 4'd3;
    localparam [3:0] BUS_R4  = 4'd4;
    localparam [3:0] BUS_R5  = 4'd5;
    localparam [3:0] BUS_R6  = 4'd6;
    localparam [3:0] BUS_R7  = 4'd7;
    localparam [3:0] BUS_G   = 4'd8;
    localparam [3:0] BUS_DIN = 4'd9;

    // ------------------------------------------------------------
    // Internal datapath signals
    // ------------------------------------------------------------

    wire [8:0] ir;
    wire [15:0] A;
    wire [15:0] G;

    wire [15:0] din_ext;
    wire [15:0] alu_result;

    reg [3:0] bus_control;
    reg [2:0] alu_op;

    reg ir_in;
    reg a_in;
    reg g_in;
    reg [7:0] reg_in;

    wire [3:0] rx_select;
    wire [3:0] ry_select;

    // Rx and Ry are 3-bit register numbers.
    // Add a leading zero so they can be used as the
    // 4-bit multiplexer select values.
    assign rx_select = {1'b0, ir[5:3]};
    assign ry_select = {1'b0, ir[2:0]};

    // ------------------------------------------------------------
    // Sign extender
    // ------------------------------------------------------------

    sign_ext sign_ext_inst (
        .in(din),
        .ext(din_ext)
    );

    // ------------------------------------------------------------
    // Tick FSM
    // ------------------------------------------------------------

    tick_FSM tick_inst (
        .enable(enable),
        .rst(rst),
        .clk(clk),
        .tick(tick_FSM)
    );

    // ------------------------------------------------------------
    // ALU
    // ------------------------------------------------------------

    alu alu_inst (
        .input_a(A),
        .input_b(bus),
        .alu_op(alu_op),
        .result(alu_result)
    );

    // ------------------------------------------------------------
    // Processor bus multiplexer
    // ------------------------------------------------------------

    multiplexer mux_inst (
        .r0(R0),
        .r1(R1),
        .r2(R2),
        .r3(R3),
        .r4(R4),
        .r5(R5),
        .r6(R6),
        .r7(R7),
        .g(G),
        .din_ext(din_ext),
        .sel(bus_control),
        .bus_out(bus)
    );

    // ------------------------------------------------------------
    // Instruction register
    // ------------------------------------------------------------

    register_n #(
        .N(9)
    ) ir_inst (
        .clk(clk),
        .rst(rst),
        .r_in(ir_in),
        .data_in(din),
        .Q(ir)
    );

    // ------------------------------------------------------------
    // A register
    // ------------------------------------------------------------

    register_n #(
        .N(16)
    ) a_inst (
        .clk(clk),
        .rst(rst),
        .r_in(a_in),
        .data_in(bus),
        .Q(A)
    );

    // ------------------------------------------------------------
    // G register
    // ------------------------------------------------------------

    register_n #(
        .N(16)
    ) g_inst (
        .clk(clk),
        .rst(rst),
        .r_in(g_in),
        .data_in(alu_result),
        .Q(G)
    );

    // ------------------------------------------------------------
    // General-purpose registers
    // ------------------------------------------------------------

    register_n #(.N(16)) r0_inst (
        .clk(clk),
        .rst(rst),
        .r_in(reg_in[0]),
        .data_in(bus),
        .Q(R0)
    );

    register_n #(.N(16)) r1_inst (
        .clk(clk),
        .rst(rst),
        .r_in(reg_in[1]),
        .data_in(bus),
        .Q(R1)
    );

    register_n #(.N(16)) r2_inst (
        .clk(clk),
        .rst(rst),
        .r_in(reg_in[2]),
        .data_in(bus),
        .Q(R2)
    );

    register_n #(.N(16)) r3_inst (
        .clk(clk),
        .rst(rst),
        .r_in(reg_in[3]),
        .data_in(bus),
        .Q(R3)
    );

    register_n #(.N(16)) r4_inst (
        .clk(clk),
        .rst(rst),
        .r_in(reg_in[4]),
        .data_in(bus),
        .Q(R4)
    );

    register_n #(.N(16)) r5_inst (
        .clk(clk),
        .rst(rst),
        .r_in(reg_in[5]),
        .data_in(bus),
        .Q(R5)
    );

    register_n #(.N(16)) r6_inst (
        .clk(clk),
        .rst(rst),
        .r_in(reg_in[6]),
        .data_in(bus),
        .Q(R6)
    );

    register_n #(.N(16)) r7_inst (
        .clk(clk),
        .rst(rst),
        .r_in(reg_in[7]),
        .data_in(bus),
        .Q(R7)
    );

    // ------------------------------------------------------------
    // Control unit
    //
    // Tick 1:
    //   Load DIN into the instruction register.
    //
    // Tick 2:
    //   movi: immediate -> destination register
    //   add/addi/sub: Rx -> A
    //
    // Tick 3:
    //   add:  Ry -> ALU -> G
    //   addi: immediate -> ALU -> G
    //   sub:  Ry -> ALU -> G
    //
    // Tick 4:
    //   G -> destination register
    // ------------------------------------------------------------

    always @(*) begin

        // Default values
        bus_control = BUS_R0;
        alu_op = ALU_ADD;

        ir_in = 1'b0;
        a_in = 1'b0;
        g_in = 1'b0;
        reg_in = 8'b00000000;

        if (enable) begin

            case (tick_FSM)

                // ------------------------------------------------
                // TICK 1
                // Fetch instruction
                // ------------------------------------------------

                4'b0001: begin
                    ir_in = 1'b1;
                end

                // ------------------------------------------------
                // TICK 2
                // ------------------------------------------------

                4'b0010: begin

                    case (ir[8:6])

                        // movi Rx, Immediate
                        // Immediate comes directly from DIN.
                        OP_MOVI: begin
                            bus_control = BUS_DIN;
                            reg_in[ir[5:3]] = 1'b1;
                        end

                        // add Rx, Ry
                        // addi Rx, Immediate
                        // sub Rx, Ry
                        //
                        // First place Rx into A.
                        OP_ADD,
                        OP_ADDI,
                        OP_SUB: begin
                            bus_control = rx_select;
                            a_in = 1'b1;
                        end

                        default: begin
                            bus_control = BUS_R0;
                        end

                    endcase

                end

                // ------------------------------------------------
                // TICK 3
                // ------------------------------------------------

                4'b0100: begin

                    case (ir[8:6])

                        // add Rx, Ry
                        OP_ADD: begin
                            bus_control = ry_select;
                            alu_op = ALU_ADD;
                            g_in = 1'b1;
                        end

                        // addi Rx, Immediate
                        OP_ADDI: begin
                            bus_control = BUS_DIN;
                            alu_op = ALU_ADD;
                            g_in = 1'b1;
                        end

                        // sub Rx, Ry
                        OP_SUB: begin
                            bus_control = ry_select;
                            alu_op = ALU_SUB;
                            g_in = 1'b1;
                        end

                        default: begin
                            bus_control = BUS_R0;
                        end

                    endcase

                end

                // ------------------------------------------------
                // TICK 4
                // ------------------------------------------------

                4'b1000: begin

                    case (ir[8:6])

                        // Write the result in G back to Rx.
                        OP_ADD,
                        OP_ADDI,
                        OP_SUB: begin
                            bus_control = BUS_G;
                            reg_in[ir[5:3]] = 1'b1;
                        end

                        default: begin
                            bus_control = BUS_R0;
                        end

                    endcase

                end

                default: begin
                    bus_control = BUS_R0;
                end

            endcase

        end

    end

endmodule