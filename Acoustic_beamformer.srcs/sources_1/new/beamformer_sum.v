`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/20/2026 09:53:42 PM
// Design Name: 
// Module Name: beamformer_sum
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module beamformer_sum #(
    parameter integer SAMPLE_WIDTH = 24
)(
    input wire clk,
    input wire rst_n,

    input wire signed [SAMPLE_WIDTH-1:0] sample_ch0,
    input wire signed [SAMPLE_WIDTH-1:0] sample_ch1,
    input wire signed [SAMPLE_WIDTH-1:0] sample_ch2,
    input wire signed [SAMPLE_WIDTH-1:0] sample_ch3,
    input wire signed [SAMPLE_WIDTH-1:0] sample_ch4,

    input wire sample_valid,

    output reg signed [SAMPLE_WIDTH-1:0] sample_out,
    output reg sample_out_valid
);

    localparam integer SUM_WIDTH = SAMPLE_WIDTH + 3;

    // This optimized reciprocal divider is intended for
    // SAMPLE_WIDTH = 24.
    // It is exact for magnitudes within the 27-bit sum range.
    // Reciprocal: ceil(2^34 / 5) = 0xCCCCCCCD.

    localparam [31:0] RECIP = 32'hCCCCCCCD;

    // -----------------------------------------------------
    // Stage 1: pairwise sums
    // -----------------------------------------------------

    reg signed [SAMPLE_WIDTH:0] sum01_s1;
    reg signed [SAMPLE_WIDTH:0] sum23_s1;
    reg signed [SAMPLE_WIDTH-1:0] ch4_s1;
    reg valid_s1;

    wire signed [SAMPLE_WIDTH:0] sum01 =
        $signed({sample_ch0[SAMPLE_WIDTH-1], sample_ch0}) +
        $signed({sample_ch1[SAMPLE_WIDTH-1], sample_ch1});

    wire signed [SAMPLE_WIDTH:0] sum23 =
        $signed({sample_ch2[SAMPLE_WIDTH-1], sample_ch2}) +
        $signed({sample_ch3[SAMPLE_WIDTH-1], sample_ch3});

    // -----------------------------------------------------
    // Stage 2: total sum
    // -----------------------------------------------------

    reg signed [SUM_WIDTH-1:0] total_s2;
    reg valid_s2;

    wire signed [SUM_WIDTH-1:0] sum01_ext =
        {{(SUM_WIDTH-SAMPLE_WIDTH-1){sum01_s1[SAMPLE_WIDTH]}},
          sum01_s1};

    wire signed [SUM_WIDTH-1:0] sum23_ext =
        {{(SUM_WIDTH-SAMPLE_WIDTH-1){sum23_s1[SAMPLE_WIDTH]}},
          sum23_s1};

    wire signed [SUM_WIDTH-1:0] ch4_ext =
        {{(SUM_WIDTH-SAMPLE_WIDTH){ch4_s1[SAMPLE_WIDTH-1]}},
          ch4_s1};

    wire signed [SUM_WIDTH-1:0] total_sum =
        sum01_ext + sum23_ext + ch4_ext;

    // -----------------------------------------------------
    // Stage 3: absolute value and rounding offset
    // -----------------------------------------------------

    reg [SUM_WIDTH-1:0] magnitude_s3;
    reg negative_s3;
    reg valid_s3;

    wire negative_s2 = total_s2[SUM_WIDTH-1];

    wire [SUM_WIDTH-1:0] absolute_total =
        negative_s2 ? -total_s2 : total_s2;

    // -----------------------------------------------------
    // Stage 4: split reciprocal multiplication
    // -----------------------------------------------------

    reg [SUM_WIDTH+16-1:0] product_lo_s4;
    reg [SUM_WIDTH+16-1:0] product_hi_s4;
    reg negative_s4;
    reg valid_s4;

    // Two unsigned 16-bit multipliers.
    wire [15:0] recip_lo = RECIP[15:0];
    wire [15:0] recip_hi = RECIP[31:16];

    // -----------------------------------------------------
    // Stage 5: reconstruct product
    // -----------------------------------------------------

    localparam integer PRODUCT_WIDTH = SUM_WIDTH + 32;

    reg [PRODUCT_WIDTH-1:0] product_s5;
    reg negative_s5;
    reg valid_s5;

    wire [PRODUCT_WIDTH-1:0] product_lo_ext =
        {{(PRODUCT_WIDTH-(SUM_WIDTH+16)){1'b0}},
          product_lo_s4};

    wire [PRODUCT_WIDTH-1:0] product_hi_ext =
        {{(PRODUCT_WIDTH-(SUM_WIDTH+16)){1'b0}},
          product_hi_s4};

    // -----------------------------------------------------
    // Stage 6: normalization and output
    // -----------------------------------------------------

    // Round to nearest integer:
    // floor((abs(total) + 2) / 5).
    //
    // For a 27-bit unsigned magnitude, the reciprocal
    // multiplication is exact after shifting by 34.

    wire [PRODUCT_WIDTH-1:0] rounded_product =
        product_s5 + ({{(PRODUCT_WIDTH-34){1'b0}}, 34'd2}
                      * RECIP);

    wire [PRODUCT_WIDTH-1:0] quotient =
        rounded_product >> 34;

    wire signed [SAMPLE_WIDTH-1:0] normalized =
        negative_s5
            ? -$signed(quotient[SAMPLE_WIDTH-1:0])
            :  $signed(quotient[SAMPLE_WIDTH-1:0]);

    // -----------------------------------------------------
    // Sequential pipeline
    // -----------------------------------------------------

    always @(posedge clk) begin
        if (!rst_n) begin
            sum01_s1 <= 0;
            sum23_s1 <= 0;
            ch4_s1 <= 0;
            valid_s1 <= 0;

            total_s2 <= 0;
            valid_s2 <= 0;

            magnitude_s3 <= 0;
            negative_s3 <= 0;
            valid_s3 <= 0;

            product_lo_s4 <= 0;
            product_hi_s4 <= 0;
            negative_s4 <= 0;
            valid_s4 <= 0;

            product_s5 <= 0;
            negative_s5 <= 0;
            valid_s5 <= 0;

            sample_out <= 0;
            sample_out_valid <= 0;
        end
        else begin

            // Stage 6
            sample_out_valid <= valid_s5;

            if (valid_s5)
                sample_out <= normalized;

            // Stage 5
            valid_s5 <= valid_s4;
            negative_s5 <= negative_s4;

            if (valid_s4)
                product_s5 <= product_lo_ext +
                              (product_hi_ext << 16);

            // Stage 4
            valid_s4 <= valid_s3;
            negative_s4 <= negative_s3;

            if (valid_s3) begin
                product_lo_s4 <= magnitude_s3 * recip_lo;
                product_hi_s4 <= magnitude_s3 * recip_hi;
            end

            // Stage 3
            valid_s3 <= valid_s2;
            negative_s3 <= negative_s2;

            if (valid_s2)
                magnitude_s3 <= absolute_total;

            // Stage 2
            valid_s2 <= valid_s1;

            if (valid_s1)
                total_s2 <= total_sum;

            // Stage 1
            valid_s1 <= sample_valid;

            if (sample_valid) begin
                sum01_s1 <= sum01;
                sum23_s1 <= sum23;
                ch4_s1 <= sample_ch4;
            end
        end
    end

endmodule
