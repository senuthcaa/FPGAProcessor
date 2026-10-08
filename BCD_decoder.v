`timescale 1ns / 1ps
/*
Monash University ECE2072: Assignment
This file contains Verilog code to decode the 16-bit display register into a signed decimal number
    for HEX4 to HEX0, used by the Task 3 and Task 4 top levels.

Please enter your name and student ID:
-Hoorad 36166804
-

*/

//converts a signed 16-bit value into a negative flag and 5 BCD digits
//uses double dabble (shift and add 3) so that no divide or modulus circuits are needed
module signed_bcd (
	input wire [15:0] value,
	output wire negative,
	output reg [19:0] bcd
);

	wire [15:0] magnitude;
	integer bit_idx;
	integer digit_idx;

	assign negative = value[15];

	//-32768 negates to itself, which reads as 32768 unsigned, so the magnitude is correct for every input
	assign magnitude = negative ? (~value + 16'd1) : value;

	always @(*) begin
		bcd = 20'd0;
		for (bit_idx = 15; bit_idx >= 0; bit_idx = bit_idx - 1) begin
			//add 3 to every digit that is 5 or more, then shift the next bit in
			for (digit_idx = 0; digit_idx < 5; digit_idx = digit_idx + 1) begin
				if (bcd[4*digit_idx +: 4] >= 4'd5) bcd[4*digit_idx +: 4] = bcd[4*digit_idx +: 4] + 4'd3;
			end
			bcd = {bcd[18:0], magnitude[bit_idx]};
		end
	end

endmodule



//decodes one BCD digit for a de10-lite hex display, which is active-low
//hex[6:0] are the segments (g to a) and hex[7] is the decimal point, which lights when dp is 1
module hex_digit (
	input wire [3:0] digit,
	input wire dp,
	output reg [7:0] hex
);

	always @(*) begin
		hex[7] = ~dp;
		case (digit)
			4'd0 : hex[6:0] = 7'b1000000;
			4'd1 : hex[6:0] = 7'b1111001;
			4'd2 : hex[6:0] = 7'b0100100;
			4'd3 : hex[6:0] = 7'b0110000;
			4'd4 : hex[6:0] = 7'b0011001;
			4'd5 : hex[6:0] = 7'b0010010;
			4'd6 : hex[6:0] = 7'b0000010;
			4'd7 : hex[6:0] = 7'b1111000;
			4'd8 : hex[6:0] = 7'b0000000;
			4'd9 : hex[6:0] = 7'b0010000;
			default : hex[6:0] = 7'b1111111;
		endcase
	end

endmodule



//shows a signed 16-bit value on 5 hex displays, the decimal point of every display lights when the value is negative
module display_decoder (
	input wire [15:0] value,

	output wire [7:0] hex0,
	output wire [7:0] hex1,
	output wire [7:0] hex2,
	output wire [7:0] hex3,
	output wire [7:0] hex4
);

	wire negative;
	wire [19:0] bcd;

	signed_bcd bcd_inst (
		.value(value),
		.negative(negative),
		.bcd(bcd)
	);

	hex_digit digit0_inst (
		.digit(bcd[3:0]),
		.dp(negative),
		.hex(hex0)
	);

	hex_digit digit1_inst (
		.digit(bcd[7:4]),
		.dp(negative),
		.hex(hex1)
	);

	hex_digit digit2_inst (
		.digit(bcd[11:8]),
		.dp(negative),
		.hex(hex2)
	);

	hex_digit digit3_inst (
		.digit(bcd[15:12]),
		.dp(negative),
		.hex(hex3)
	);

	hex_digit digit4_inst (
		.digit(bcd[19:16]),
		.dp(negative),
		.hex(hex4)
	);

endmodule