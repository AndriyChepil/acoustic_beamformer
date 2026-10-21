`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/20/2026 07:50:11 PM
// Design Name: 
// Module Name: fractional_delay
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

module fractional_delay #(
    parameter integer SAMPLE_WIDTH   = 24,
    parameter integer MAX_DELAY      = 31,
    parameter integer FRAC_BITS      = 8,
    parameter integer DELAY_INT_BITS = $clog2(MAX_DELAY + 1),
    parameter integer DELAY_WIDTH    = DELAY_INT_BITS + FRAC_BITS
)(
    input  wire clk,
    input  wire rst_n,

    // Signed PCM sample
    input  wire signed [SAMPLE_WIDTH-1:0] sample_in,
    input  wire sample_valid,

    // Unsigned fixed-point delay, Q5.8 by default
    input  wire [DELAY_WIDTH-1:0] delay_value,

    // Synchronous reset of sample history and pipeline
    input  wire clear_history,

    // Delayed PCM output
    output reg signed [SAMPLE_WIDTH-1:0] sample_out,
    output reg sample_out_valid
);

    // =====================================================
    // Local parameters
    // =====================================================

    // Stores x[n-1] ... x[n-MAX_DELAY-1]
    localparam integer DEPTH = MAX_DELAY + 1;

    localparam integer DIFF_WIDTH = SAMPLE_WIDTH + 1;
    localparam integer PROD_WIDTH = DIFF_WIDTH + FRAC_BITS + 1;
    localparam integer ACC_WIDTH  = PROD_WIDTH + 1;

    // =====================================================
    // Sample history: shift register
    // =====================================================

    reg signed [SAMPLE_WIDTH-1:0] history [0:DEPTH-1];

    integer i;

    wire [DELAY_INT_BITS-1:0] delay_int;
    wire [FRAC_BITS-1:0] delay_frac;

    assign delay_int  = delay_value[DELAY_WIDTH-1:FRAC_BITS];
    assign delay_frac = delay_value[FRAC_BITS-1:0];

    // =====================================================
    // Stage 1: Read samples
    //
    // history[0] = x[n-1] before shift
    // history[1] = x[n-2]
    //
    // x0 = x[n-D]
    // x1 = x[n-D-1]
    // =====================================================

    reg signed [SAMPLE_WIDTH-1:0] x0_s1;
    reg signed [SAMPLE_WIDTH-1:0] x1_s1;
    reg [FRAC_BITS-1:0] frac_s1;
    reg valid_s1;

    // =====================================================
    // Stage 2: Difference
    // =====================================================

    reg signed [DIFF_WIDTH-1:0] diff_s2;
    reg signed [SAMPLE_WIDTH-1:0] x0_s2;
    reg [FRAC_BITS-1:0] frac_s2;
    reg valid_s2;

    wire signed [DIFF_WIDTH-1:0] difference;

    assign difference =
        $signed({x1_s1[SAMPLE_WIDTH-1], x1_s1}) -
        $signed({x0_s1[SAMPLE_WIDTH-1], x0_s1});

    // =====================================================
    // Stage 3: Multiplication
    // =====================================================

    reg signed [PROD_WIDTH-1:0] product_s3;
    reg signed [SAMPLE_WIDTH-1:0] x0_s3;
    reg valid_s3;

    wire signed [FRAC_BITS:0] frac_signed;
    wire signed [PROD_WIDTH-1:0] product;

    assign frac_signed = $signed({1'b0, frac_s2});
    assign product = diff_s2 * frac_signed;

    // =====================================================
    // Stage 4: Add and output
    // =====================================================

    wire signed [ACC_WIDTH-1:0] x0_extended;
    wire signed [ACC_WIDTH-1:0] base_scaled;
    wire signed [ACC_WIDTH-1:0] product_extended;
    wire signed [ACC_WIDTH-1:0] interpolated_scaled;
    wire signed [ACC_WIDTH-1:0] interpolated;

    assign x0_extended =
        {{(ACC_WIDTH-SAMPLE_WIDTH){x0_s3[SAMPLE_WIDTH-1]}},
          x0_s3};

    assign base_scaled = x0_extended <<< FRAC_BITS;

    assign product_extended =
        {{(ACC_WIDTH-PROD_WIDTH){product_s3[PROD_WIDTH-1]}},
          product_s3};

    assign interpolated_scaled =
        base_scaled + product_extended;

    assign interpolated =
        interpolated_scaled >>> FRAC_BITS;

    // =====================================================
    // Sequential logic
    // =====================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            for (i = 0; i < DEPTH; i = i + 1)
                history[i] <= 0;

            x0_s1            <= 0;
            x1_s1            <= 0;
            frac_s1          <= 0;
            valid_s1         <= 0;

            diff_s2          <= 0;
            x0_s2            <= 0;
            frac_s2          <= 0;
            valid_s2         <= 0;

            product_s3       <= 0;
            x0_s3            <= 0;
            valid_s3         <= 0;

            sample_out       <= 0;
            sample_out_valid <= 0;

        end
        else if (clear_history) begin

            for (i = 0; i < DEPTH; i = i + 1)
                history[i] <= 0;

            x0_s1            <= 0;
            x1_s1            <= 0;
            frac_s1          <= 0;
            valid_s1         <= 0;

            diff_s2          <= 0;
            x0_s2            <= 0;
            frac_s2          <= 0;
            valid_s2         <= 0;

            product_s3       <= 0;
            x0_s3            <= 0;
            valid_s3         <= 0;

            sample_out       <= 0;
            sample_out_valid <= 0;

        end
        else begin

            // ---------------------------------------------
            // Stage 4: Output
            // ---------------------------------------------

            sample_out_valid <= valid_s3;

            if (valid_s3)
                sample_out <= interpolated[SAMPLE_WIDTH-1:0];

            // ---------------------------------------------
            // Stage 3: Multiplication
            // ---------------------------------------------

            valid_s3 <= valid_s2;

            if (valid_s2) begin
                product_s3 <= product;
                x0_s3      <= x0_s2;
            end

            // ---------------------------------------------
            // Stage 2: Difference
            // ---------------------------------------------

            valid_s2 <= valid_s1;

            if (valid_s1) begin
                diff_s2 <= difference;
                x0_s2   <= x0_s1;
                frac_s2 <= frac_s1;
            end

            // ---------------------------------------------
            // Stage 1: Shift history and read samples
            // ---------------------------------------------

            valid_s1 <= sample_valid;

            if (sample_valid) begin

                // Select samples BEFORE updating history
                if (delay_int == 0)
                    x0_s1 <= sample_in;
                else
                    x0_s1 <= history[delay_int - 1'b1];

                x1_s1   <= history[delay_int];
                frac_s1 <= delay_frac;

                // Shift history only when a new PCM
                // sample arrives
                for (i = DEPTH-1; i > 0; i = i - 1)
                    history[i] <= history[i-1];

                history[0] <= sample_in;

            end
        end
    end

endmodule
