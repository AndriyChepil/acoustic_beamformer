`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/21/2026 03:03:51 AM
// Design Name: 
// Module Name: i2s_clock_generator
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


module i2s_clock_generator #(
    parameter integer CLK_FREQ_HZ = 50000000,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer SLOT_BITS = 32,
    parameter integer ACC_WIDTH = 32
)(
    input  wire clk,
    input  wire rst_n,

    output reg  i2s_bclk,
    output reg  i2s_ws,

    output reg  bclk_rising_tick,
    output reg  bclk_falling_tick,
    output reg  frame_tick
);

    localparam integer BCLK_FREQ_HZ =
        SAMPLE_RATE_HZ * SLOT_BITS * 2;

    // Number of half-BCLK transitions per second.
    localparam integer TOGGLE_FREQ_HZ =
        BCLK_FREQ_HZ * 2;

    // NCO frequency tuning word.
    // Calculated using 64-bit integer arithmetic.
    localparam [63:0] PHASE_SCALE =
        64'd1 << ACC_WIDTH;

    localparam [63:0] PHASE_INC_64 =
        ((TOGGLE_FREQ_HZ * PHASE_SCALE)
          + CLK_FREQ_HZ / 2) / CLK_FREQ_HZ;

    localparam [ACC_WIDTH-1:0] PHASE_INC =
        PHASE_INC_64[ACC_WIDTH-1:0];

    reg [ACC_WIDTH-1:0] phase_acc;

    reg [6:0] bit_count;

    wire [ACC_WIDTH:0] phase_sum;

    assign phase_sum =
        {1'b0, phase_acc} +
        {1'b0, PHASE_INC};

    wire toggle_tick = phase_sum[ACC_WIDTH];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= {ACC_WIDTH{1'b0}};

            i2s_bclk <= 1'b0;
            i2s_ws   <= 1'b0;

            bit_count <= 7'd0;

            bclk_rising_tick  <= 1'b0;
            bclk_falling_tick <= 1'b0;
            frame_tick        <= 1'b0;
        end
        else begin
            phase_acc <= phase_sum[ACC_WIDTH-1:0];

            bclk_rising_tick  <= 1'b0;
            bclk_falling_tick <= 1'b0;
            frame_tick        <= 1'b0;

            if (toggle_tick) begin
                i2s_bclk <= ~i2s_bclk;

                if (!i2s_bclk) begin
                    // BCLK transitions from 0 to 1.
                    bclk_rising_tick <= 1'b1;
                end
                else begin
                    // BCLK transitions from 1 to 0.
                    bclk_falling_tick <= 1'b1;

                    if (bit_count == (2*SLOT_BITS-1)) begin
                        bit_count  <= 7'd0;
                        frame_tick <= 1'b1;
                    end
                    else begin
                        bit_count <= bit_count + 1'b1;
                    end

                    // WS is low during the first slot,
                    // high during the second slot.
                    if (bit_count == SLOT_BITS-1)
                        i2s_ws <= 1'b1;
                    else if (bit_count == 2*SLOT_BITS-1)
                        i2s_ws <= 1'b0;
                end
            end
        end
    end

endmodule

