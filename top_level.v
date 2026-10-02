`timescale 1ns/1ps

// ECE2072 Task 2 DE10-Lite top level
//
// SW[8:0]  -> processor DIN
// ~KEY[0]  -> synchronous processor reset
// ~KEY[1]  -> processor clock
// processor enable -> 1'b1
// bus[9:0] -> LEDR[9:0]
// tick_FSM -> HEX5

module top_level (
    input  wire [9:0] SW,
    input  wire [1:0] KEY,

    output wire [9:0] LEDR,
    output reg  [6:0] HEX5
);

    wire [15:0] bus;
    wire [3:0]  tick;

    // ------------------------------------------------------------
    // Instantiate Task 2 processor
    // ------------------------------------------------------------
    simple_proc proc_inst (
        .clk(~KEY[1]),
        .rst(~KEY[0]),
        .enable(1'b1),
        .din(SW[8:0]),
        .bus(bus),
        .tick_FSM(tick),

        // Testbench outputs are not required on hardware.
        .R0(),
        .R1(),
        .R2(),
        .R3(),
        .R4(),
        .R5(),
        .R6(),
        .R7()
    );

    // ------------------------------------------------------------
    // Display bottom 10 bits of processor bus on LEDs
    // ------------------------------------------------------------
    assign LEDR = bus[9:0];

    // ------------------------------------------------------------
    // Display current tick on HEX5.
    // DE10-Lite seven-segment displays are active-low.
    // ------------------------------------------------------------
    always @(*) begin
        case (tick)
            4'b0001: HEX5 = 7'b1111001; // 1
            4'b0010: HEX5 = 7'b0100100; // 2
            4'b0100: HEX5 = 7'b0110000; // 3
            4'b1000: HEX5 = 7'b0011001; // 4
            default: HEX5 = 7'b1111111; // blank
        endcase
    end

endmodule
