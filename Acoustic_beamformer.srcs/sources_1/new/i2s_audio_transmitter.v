`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/21/2026 12:12:31 PM
// Design Name: 
// Module Name: i2s_audio_transmitter
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

module i2s_audio_transmitter #(
    parameter integer SAMPLE_WIDTH = 24,
    parameter integer SLOT_BITS    = 32
)(
    input wire clk,
    input wire rst_n,

    input wire signed [SAMPLE_WIDTH-1:0] sample_in,
    input wire sample_valid,

    input wire i2s_bclk,
    input wire i2s_ws,

    output reg i2s_dout
);

    localparam integer COUNT_WIDTH = $clog2(SLOT_BITS + 1);

    reg signed [SAMPLE_WIDTH-1:0] pending_sample;
    reg signed [SAMPLE_WIDTH-1:0] active_sample;

    reg bclk_d;
    reg ws_d;

    reg [COUNT_WIDTH-1:0] bit_count;

    wire bclk_fall = bclk_d && !i2s_bclk;
    wire ws_change = ws_d ^ i2s_ws;
    wire ws_fall = ws_d && !i2s_ws;

    always @(posedge clk) begin
        if (!rst_n) begin
            pending_sample <= 0;
            active_sample  <= 0;

            bclk_d <= 0;
            ws_d   <= 0;

            bit_count <= 0;
            i2s_dout <= 0;
        end
        else begin
            bclk_d <= i2s_bclk;
            ws_d   <= i2s_ws;

            // Capture PCM sample
            if (sample_valid)
                pending_sample <= sample_in;

            // Detect channel transition independently
            if (ws_change) begin
                bit_count <= 0;

                // One-bit I2S delay
                i2s_dout <= 0;

                // Capture sample at left-channel start
                if (ws_fall)
                    active_sample <= pending_sample;
            end
            else if (bclk_fall) begin

                // First falling edge after WS transition:
                // transmit MSB.
                if (bit_count < SAMPLE_WIDTH) begin
                    i2s_dout <= active_sample[
                        SAMPLE_WIDTH - 1 - bit_count
                    ];
                end
                else begin
                    i2s_dout <= 0;
                end

                if (bit_count < SLOT_BITS)
                    bit_count <= bit_count + 1'b1;
            end
        end
    end

endmodule
