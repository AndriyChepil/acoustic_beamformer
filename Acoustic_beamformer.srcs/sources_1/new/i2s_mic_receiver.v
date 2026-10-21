`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/21/2026 01:07:24 AM
// Design Name: 
// Module Name: i2s_mic_receiver
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

module i2s_mic_receiver #(
    parameter integer NUM_CHANNELS = 5,
    parameter integer SAMPLE_WIDTH = 24,
    parameter integer SLOT_BITS    = 32,

    // 0 = left slot (WS=0)
    // 1 = right slot (WS=1)
    parameter integer MIC_SLOT     = 0
)(
    input wire clk,
    input wire rst_n,

    // External I2S signals
    input wire i2s_bclk,
    input wire i2s_ws,
    input wire [NUM_CHANNELS-1:0] i2s_data,

    // Parallel signed PCM samples
    output reg [NUM_CHANNELS*SAMPLE_WIDTH-1:0] samples_out,
    output reg samples_valid
);

    // =====================================================
    // Synchronize BCLK and WS to system clock
    // =====================================================

    (* ASYNC_REG = "TRUE" *) reg [2:0] bclk_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] ws_sync;

    // Data synchronization.
    // All microphone data lines share the same clock.
    (* ASYNC_REG = "TRUE" *)
    reg [NUM_CHANNELS-1:0] data_meta;

    (* ASYNC_REG = "TRUE" *)
    reg [NUM_CHANNELS-1:0] data_sync;

    always @(posedge clk) begin
        if (!rst_n) begin
            bclk_sync <= 3'b000;
            ws_sync   <= 3'b000;

            data_meta <= {NUM_CHANNELS{1'b0}};
            data_sync <= {NUM_CHANNELS{1'b0}};
        end
        else begin
            bclk_sync <= {bclk_sync[1:0], i2s_bclk};
            ws_sync   <= {ws_sync[1:0], i2s_ws};

            data_meta <= i2s_data;
            data_sync <= data_meta;
        end
    end

    wire bclk_rising;
    wire ws_changed;

    assign bclk_rising =
        (bclk_sync[2:1] == 2'b01);

    assign ws_changed =
        (ws_sync[2] != ws_sync[1]);

    // =====================================================
    // I2S slot reception
    //
    // Standard I2S:
    // - WS changes one BCLK before the MSB
    // - data sampled on BCLK rising edge
    // - 24 useful bits in a 32-bit slot
    // =====================================================

    localparam integer COUNT_WIDTH = $clog2(SLOT_BITS + 1);

    reg [COUNT_WIDTH-1:0] bit_count;

    reg current_slot;
    reg slot_active;
    reg receiver_locked;

    // One 24-bit shift register per microphone
    reg [SAMPLE_WIDTH-1:0] shift_reg [0:NUM_CHANNELS-1];

    integer ch;

    // =====================================================
    // Receiver state machine
    // =====================================================

    always @(posedge clk) begin
        if (!rst_n) begin

            bit_count       <= 0;
            current_slot    <= 0;
            slot_active     <= 0;
            receiver_locked <= 0;

            samples_out     <= 0;
            samples_valid   <= 0;

            for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1)
                shift_reg[ch] <= 0;

        end
        else begin

            samples_valid <= 1'b0;

            // ---------------------------------------------
            // Detect slot boundary
            // ---------------------------------------------

            if (ws_changed) begin

                current_slot <= ws_sync[1];

                bit_count <= 0;

                slot_active <=
                    (ws_sync[1] == MIC_SLOT);

                receiver_locked <= 1'b1;

            end

            // ---------------------------------------------
            // Receive serial bits
            // ---------------------------------------------

            else if (bclk_rising && receiver_locked) begin

                if (bit_count < SLOT_BITS)
                    bit_count <= bit_count + 1'b1;

                // The first BCLK rising edge after WS
                // transition is the I2S one-bit delay.
                //
                // Useful PCM bits occupy:
                // bit_count = 1 ... SAMPLE_WIDTH

                if (slot_active &&
                    bit_count >= 1 &&
                    bit_count <= SAMPLE_WIDTH) begin

                    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
                        shift_reg[ch] <= {
                            shift_reg[ch][SAMPLE_WIDTH-2:0],
                            data_sync[ch]
                        };
                    end

                    // Last PCM bit received
                    if (bit_count == SAMPLE_WIDTH) begin

                        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin

                            samples_out[
                                ch*SAMPLE_WIDTH +: SAMPLE_WIDTH
                            ] <= {
                                shift_reg[ch][SAMPLE_WIDTH-2:0],
                                data_sync[ch]
                            };

                        end

                        samples_valid <= 1'b1;

                    end
                end
            end
        end
    end

endmodule
