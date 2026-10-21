`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/21/2026 01:13:11 AM
// Design Name: 
// Module Name: i2s_mic_receiver_tb
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

module i2s_mic_receiver_tb;

    localparam integer NUM_CHANNELS = 5;
    localparam integer SAMPLE_WIDTH = 24;
    localparam integer SLOT_BITS    = 32;

    // 100 MHz system clock
    localparam integer CLK_HALF = 5;

    // BCLK = 3.072 MHz approximately
    // Period = 325.52 ns
    // Use real delay for simulation only
    localparam real BCLK_HALF = 162.7604167;

    reg clk = 0;
    reg rst_n = 0;

    reg i2s_bclk = 0;
    reg i2s_ws = 1;

    reg [NUM_CHANNELS-1:0] i2s_data = 0;

    wire [NUM_CHANNELS*SAMPLE_WIDTH-1:0] samples_out;
    wire samples_valid;

    integer errors = 0;
    integer checked = 0;
    integer received = 0;
    integer sent = 0;

    reg [119:0] expected_samples;
    reg expected_pending = 0;

    integer ch;
    integer frame;

    // =====================================================
    // DUT
    // =====================================================

    i2s_mic_receiver #(
        .NUM_CHANNELS(NUM_CHANNELS),
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .SLOT_BITS(SLOT_BITS),
        .MIC_SLOT(0)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),
        .i2s_data(i2s_data),

        .samples_out(samples_out),
        .samples_valid(samples_valid)
    );

    // =====================================================
    // System clock
    // =====================================================

    always #CLK_HALF clk = ~clk;

    // =====================================================
    // Scoreboard
    // =====================================================

    always @(posedge clk) begin
        #1;

        if (rst_n && samples_valid) begin

            received = received + 1;

            if (!expected_pending) begin
                $display(
                    "ERROR: unexpected samples_valid at %0t",
                    $time
                );
                errors = errors + 1;
            end
            else begin

                checked = checked + 1;

                if (samples_out !== expected_samples) begin

                    $display(
                        "ERROR: frame %0d mismatch",
                        received
                    );

                    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin

                        $display(
                            " CH%0d expected=%h received=%h",
                            ch,
                            expected_samples[
                                ch*SAMPLE_WIDTH +: SAMPLE_WIDTH
                            ],
                            samples_out[
                                ch*SAMPLE_WIDTH +: SAMPLE_WIDTH
                            ]
                        );

                    end

                    errors = errors + 1;

                end
                else begin
                    $display(
                        "PASS: frame %0d data=%h",
                        received,
                        samples_out
                    );
                end

                expected_pending = 0;

            end
        end
    end

    // =====================================================
    // Generate one I2S BCLK cycle
    //
    // Data is driven before BCLK rising edge.
    // Receiver samples on rising edge.
    // =====================================================

    task bclk_cycle;
        input [NUM_CHANNELS-1:0] serial_bits;

        begin
            i2s_bclk = 0;
            i2s_data = serial_bits;

            #(BCLK_HALF);

            i2s_bclk = 1;

            #(BCLK_HALF);

            i2s_bclk = 0;
        end
    endtask

    // =====================================================
    // Send one 32-bit I2S slot
    //
    // Standard I2S has a one-bit delay after WS change.
    // =====================================================

    task send_slot;

        input slot_ws;
        input [119:0] pcm_data;

        integer bit_index;
        integer channel_index;

        reg [NUM_CHANNELS-1:0] serial_bits;

        begin

            i2s_ws = slot_ws;

            // First bit clock is the I2S delay bit.
            // This bit is ignored by receiver.

            bclk_cycle(5'b00000);

            // Send 24 PCM bits, MSB first

            for (bit_index = SAMPLE_WIDTH-1;
                 bit_index >= 0;
                 bit_index = bit_index - 1) begin

                for (channel_index = 0;
                     channel_index < NUM_CHANNELS;
                     channel_index = channel_index + 1) begin

                    serial_bits[channel_index] =
                        pcm_data[
                            channel_index*SAMPLE_WIDTH +
                            bit_index
                        ];

                end

                bclk_cycle(serial_bits);

            end

            // Remaining padding clocks:
            // 32 - 1 - 24 = 7

            for (bit_index = 0;
                 bit_index < SLOT_BITS-SAMPLE_WIDTH-1;
                 bit_index = bit_index + 1) begin

                bclk_cycle(5'b10101);

            end

        end
    endtask

    // =====================================================
    // Send complete stereo I2S frame
    //
    // All five microphones use left slot.
    // Right slot contains dummy data.
    // =====================================================

    task send_frame;

        input [23:0] s0;
        input [23:0] s1;
        input [23:0] s2;
        input [23:0] s3;
        input [23:0] s4;

        reg [119:0] frame_data;

        begin

            frame_data = {
                s4, s3, s2, s1, s0
            };

            // Register expected result
            expected_samples = frame_data;
            expected_pending = 1;

            sent = sent + 1;

            // Left slot: real microphone data
            send_slot(1'b0, frame_data);

            // Right slot: ignored
            send_slot(1'b1, {120{1'b1}});

            // Allow synchronized output to settle
            repeat (5) @(posedge clk);

            if (expected_pending) begin
                $display(
                    "ERROR: frame %0d not received",
                    sent
                );
                errors = errors + 1;
                expected_pending = 0;
            end

        end
    endtask

    // =====================================================
    // Reset
    // =====================================================

    task reset_receiver;
        begin

            rst_n = 0;
            i2s_bclk = 0;
            i2s_ws = 1;
            i2s_data = 0;

            expected_pending = 0;

            repeat (10) @(posedge clk);

            @(negedge clk);
            rst_n = 1;

            repeat (10) @(posedge clk);

        end
    endtask

    // =====================================================
    // Test sequence
    // =====================================================

    initial begin

        $display("======================================");
        $display("I2S MIC RECEIVER TESTBENCH");
        $display("======================================");

        reset_receiver();

        // ---------------------------------------------
        // TEST 1: All microphones zero
        // ---------------------------------------------

        $display("TEST 1: all zero");

        send_frame(
            24'h000000,
            24'h000000,
            24'h000000,
            24'h000000,
            24'h000000
        );

        // ---------------------------------------------
        // TEST 2: Identical positive values
        // ---------------------------------------------

        $display("TEST 2: identical samples");

        send_frame(
            24'h123456,
            24'h123456,
            24'h123456,
            24'h123456,
            24'h123456
        );

        // ---------------------------------------------
        // TEST 3: Independent microphone data
        // ---------------------------------------------

        $display("TEST 3: independent channels");

        send_frame(
            24'h000001,
            24'h000002,
            24'h000003,
            24'h000004,
            24'h000005
        );

        // ---------------------------------------------
        // TEST 4: Signed values
        // ---------------------------------------------

        $display("TEST 4: signed PCM");

        send_frame(
            24'h0003E8, // +1000
            24'hFFFC18, // -1000
            24'h0007D0, // +2000
            24'hFFF830, // -2000
            24'h000000
        );

        // ---------------------------------------------
        // TEST 5: PCM limits
        // ---------------------------------------------

        $display("TEST 5: PCM limits");

        send_frame(
            24'h7FFFFF,
            24'h800000,
            24'hFFFFFF,
            24'h000000,
            24'h400000
        );

        // ---------------------------------------------
        // TEST 6: Bit patterns
        // ---------------------------------------------

        $display("TEST 6: bit ordering");

        send_frame(
            24'hAAAAAA,
            24'h555555,
            24'hF0F0F0,
            24'h0F0F0F,
            24'h123456
        );

        // ---------------------------------------------
        // TEST 7: Continuous frames
        // ---------------------------------------------

        $display("TEST 7: continuous frames");

        for (frame = 0; frame < 20; frame = frame + 1) begin

            send_frame(
                frame * 100,
                frame * 200,
                frame * 300,
                frame * 400,
                frame * 500
            );

        end

        // ---------------------------------------------
        // TEST 8: Reset and restart
        // ---------------------------------------------

        $display("TEST 8: reset and restart");

        reset_receiver();

        send_frame(
            24'h111111,
            24'h222222,
            24'h333333,
            24'h444444,
            24'h555555
        );

        // ---------------------------------------------
        // Final report
        // ---------------------------------------------

        $display("======================================");

        $display(
            "Sent=%0d Received=%0d Checked=%0d Errors=%0d",
            sent,
            received,
            checked,
            errors
        );

        if ((errors == 0) &&
            (sent == received) &&
            (checked == sent)) begin

            $display("PASS: I2S receiver tests");

        end
        else begin

            $display("FAIL: I2S receiver tests");

        end

        $finish;

    end

    // =====================================================
    // Simulation timeout
    // =====================================================

    initial begin
        #2000000;

        $display("ERROR: simulation timeout");
        $finish;
    end

endmodule
