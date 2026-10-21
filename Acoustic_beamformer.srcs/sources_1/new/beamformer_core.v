`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/20/2026 07:31:44 PM
// Design Name: 
// Module Name: beamformer_core
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


module beamformer_core #(
    parameter integer NUM_CHANNELS   = 5,
    parameter integer SAMPLE_WIDTH   = 24,
    parameter integer MAX_DELAY      = 31,
    parameter integer FRAC_BITS      = 8,
    parameter integer DELAY_INT_BITS = $clog2(MAX_DELAY + 1),
    parameter integer DELAY_WIDTH    = DELAY_INT_BITS + FRAC_BITS
)(
    input wire clk,
    input wire rst_n,

    // Audio input: five synchronized PCM channels
    input wire [NUM_CHANNELS*SAMPLE_WIDTH-1:0] samples_in,
    input wire samples_valid,

    // Fractional delay configuration
    input wire [NUM_CHANNELS*DELAY_WIDTH-1:0] delay_cfg,
    input wire delay_update,

    // Global control
    input wire beam_enable,
    input wire clear_history,

    // Audio output
    output reg signed [SAMPLE_WIDTH-1:0] audio_out,
    output reg audio_valid,

    // Monitoring
    output reg [SAMPLE_WIDTH-1:0] peak_level,
    output reg [31:0] sample_counter,
    output reg overflow_flag,

    // Status
    output reg busy,
    output reg config_applied
);
    
    
    // =====================================================
    // Delay configuration
    // =====================================================

    reg [NUM_CHANNELS*DELAY_WIDTH-1:0] active_delay_cfg;
    reg [NUM_CHANNELS*DELAY_WIDTH-1:0] pending_delay_cfg;
    reg pending_update;

    wire accept_frame =
        samples_valid && beam_enable && !clear_history;

    // Clear the complete processing pipeline.
    // This version assumes synchronous active-low reset
    // inside both processing modules.
    wire processing_rst_n = rst_n && !clear_history;

    always @(posedge clk) begin
        if (!rst_n) begin
            active_delay_cfg <= 0;
            pending_delay_cfg <= 0;
            pending_update <= 0;
            config_applied <= 0;
        end
        else begin
            config_applied <= 0;

            if (samples_valid && pending_update) begin
                active_delay_cfg <= pending_delay_cfg;
                pending_update <= 0;
                config_applied <= 1;
            end

            // New update has priority over applying
            // an older pending configuration.
            if (delay_update) begin
                pending_delay_cfg <= delay_cfg;
                pending_update <= 1;
            end
        end
    end

    // =====================================================
    // Five fractional-delay channels
    // =====================================================

    wire [NUM_CHANNELS*SAMPLE_WIDTH-1:0] delayed_samples;
    wire [NUM_CHANNELS-1:0] delayed_valid;

    genvar ch;

    generate
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1)
        begin : GEN_DELAY

            fractional_delay #(
                .SAMPLE_WIDTH(SAMPLE_WIDTH),
                .MAX_DELAY(MAX_DELAY),
                .FRAC_BITS(FRAC_BITS),
                .DELAY_INT_BITS(DELAY_INT_BITS),
                .DELAY_WIDTH(DELAY_WIDTH)
            ) delay_inst (
                .clk(clk),
                .rst_n(processing_rst_n),

                .sample_in(
                    samples_in[ch*SAMPLE_WIDTH +: SAMPLE_WIDTH]
                ),

                .sample_valid(accept_frame),

                .delay_value(
                    active_delay_cfg[ch*DELAY_WIDTH +: DELAY_WIDTH]
                ),

                .clear_history(clear_history),

                .sample_out(
                    delayed_samples[ch*SAMPLE_WIDTH +: SAMPLE_WIDTH]
                ),

                .sample_out_valid(delayed_valid[ch])
            );

        end
    endgenerate

    // =====================================================
    // Synchronization
    // =====================================================

    wire all_delays_valid = &delayed_valid;

    // =====================================================
    // Five-channel summation
    // =====================================================

    wire signed [SAMPLE_WIDTH-1:0] sum_out;
    wire sum_out_valid;

    beamformer_sum #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) sum_inst (
        .clk(clk),
        .rst_n(processing_rst_n),

        .sample_ch0(
            delayed_samples[0*SAMPLE_WIDTH +: SAMPLE_WIDTH]
        ),
        .sample_ch1(
            delayed_samples[1*SAMPLE_WIDTH +: SAMPLE_WIDTH]
        ),
        .sample_ch2(
            delayed_samples[2*SAMPLE_WIDTH +: SAMPLE_WIDTH]
        ),
        .sample_ch3(
            delayed_samples[3*SAMPLE_WIDTH +: SAMPLE_WIDTH]
        ),
        .sample_ch4(
            delayed_samples[4*SAMPLE_WIDTH +: SAMPLE_WIDTH]
        ),

        .sample_valid(all_delays_valid),

        .sample_out(sum_out),
        .sample_out_valid(sum_out_valid)
    );

    // =====================================================
    // Output monitoring
    // =====================================================

    wire [SAMPLE_WIDTH-1:0] abs_sum =
        sum_out[SAMPLE_WIDTH-1] ? -sum_out : sum_out;

    always @(posedge clk) begin
        if (!rst_n) begin
            audio_out <= 0;
            audio_valid <= 0;
            peak_level <= 0;
            sample_counter <= 0;
            overflow_flag <= 0;
            busy <= 0;
        end
        else if (clear_history) begin
            audio_out <= 0;
            audio_valid <= 0;
            peak_level <= 0;
            sample_counter <= 0;
            overflow_flag <= 0;
            busy <= 0;
        end
        else begin
            audio_valid <= sum_out_valid;

            if (sum_out_valid) begin
                audio_out <= sum_out;
                sample_counter <= sample_counter + 1'b1;

                if (abs_sum > peak_level)
                    peak_level <= abs_sum;
            end

            // Activity indication (not full pipeline occupancy)
            busy <= accept_frame |
                    all_delays_valid |
                    sum_out_valid;
        end
    end

endmodule