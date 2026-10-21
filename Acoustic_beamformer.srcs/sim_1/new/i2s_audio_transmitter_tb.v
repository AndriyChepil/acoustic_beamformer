`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/21/2026 12:39:55 PM
// Design Name: 
// Module Name: i2s_audio_transmitter_tb
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

module i2s_audio_transmitter_tb;

    reg clk = 0;
    always #10 clk = ~clk;  // 50 MHz

    reg rst_n = 0;

    reg signed [23:0] sample_in = 0;
    reg sample_valid = 0;

    reg i2s_bclk = 0;
    reg i2s_ws = 1;

    reg [23:0] pending_expected = 0;
    reg [23:0] active_expected  = 0;

    wire i2s_dout;

    integer errors = 0;
    integer checked = 0;

    // Approximate 3.072 MHz BCLK:
    // 16 system clocks per BCLK period
    integer div_count = 0;
    integer bit_position = 0;

    // Test samples
    reg signed [23:0] expected_sample = 0;

    i2s_audio_transmitter #(
        .SAMPLE_WIDTH(24),
        .SLOT_BITS(32)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .sample_in(sample_in),
        .sample_valid(sample_valid),

        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),

        .i2s_dout(i2s_dout)
    );

    // ----------------------------------------------
    // Generate BCLK and WS
    // WS changes at BCLK falling edge.
    // 32 BCLK cycles per channel.
    // ----------------------------------------------

    always @(posedge clk) begin
        if (!rst_n) begin
            div_count <= 0;
            i2s_bclk <= 0;
            i2s_ws <= 1;
            bit_position <= 0;
        end
        else begin
            if (div_count == 7) begin
                div_count <= 0;
                i2s_bclk <= ~i2s_bclk;

                if (i2s_bclk) begin
                    if (bit_position == 31) begin
                        bit_position <= 0;
                        i2s_ws <= ~i2s_ws;
                    end
                    else begin
                        bit_position <= bit_position + 1;
                    end
                end
            end
            else begin
                div_count <= div_count + 1;
            end
        end
    end

    // ----------------------------------------------
    // Send a new PCM sample
    // ----------------------------------------------

    task send_sample;
    input signed [23:0] value;
    begin
        @(negedge clk);
        sample_in = value;
        sample_valid = 1;

        @(negedge clk);
        sample_valid = 0;
        pending_expected = value;
    end
endtask

    // ----------------------------------------------
    // Decode serial I2S data.
    //
    // At the first rising BCLK edge after a WS
    // transition, the previous channel's LSB/padding
    // is still present (one-bit I2S delay).
    //
    // The next 24 rising edges carry PCM MSB..LSB.
    // ----------------------------------------------

    reg ws_previous = 1;
    integer slot_bit = 0;
    reg [23:0] received_word = 0;
    reg [23:0] expected_word = 0;

    always @(posedge i2s_bclk) begin
        if (rst_n) begin
            if (i2s_ws != ws_previous) begin
                slot_bit = 0;
                received_word = 0;

            // Beginning of the left channel
                if (i2s_ws == 0)
                    active_expected = pending_expected;
            end
            else begin
                slot_bit = slot_bit + 1;
            end

            ws_previous = i2s_ws;

            if (slot_bit >= 1 && slot_bit <= 24) begin
                received_word[24-slot_bit] = i2s_dout;
            end

            if (slot_bit == 24) begin
                checked = checked + 1;

                // First frames after reset may contain
                // zero before the pipeline is filled.
                if (checked > 4) begin
                    if (received_word !== active_expected) begin
                        $display(
                            "ERROR: WS=%b received=%h expected=%h time=%0t",
                            i2s_ws,
                            received_word,
                            expected_word,
                            $time
                        );
                        errors = errors + 1;
                    end
                    else begin
                        $display(
                            "OK: WS=%b sample=%h time=%0t",
                            i2s_ws,
                            received_word,
                            $time
                        );
                    end
                end
            end
        end
    end

    // ----------------------------------------------
    // Test sequence
    // ----------------------------------------------

    initial begin
        $display("=================================");
        $display("I2S AUDIO TRANSMITTER TEST");
        $display("=================================");

        repeat (10) @(posedge clk);
        rst_n = 1;

        // Allow I2S to stabilize
        repeat (3000) @(posedge clk);

        expected_word = 24'h123456;
        send_sample(24'h123456);
        repeat (3000) @(posedge clk);

        expected_word = 24'h7FFFFF;
        send_sample(24'h7FFFFF);
        repeat (3000) @(posedge clk);

        expected_word = 24'h800000;
        send_sample(24'h800000);
        repeat (3000) @(posedge clk);

        expected_word = 24'hA5C39E;
        send_sample(24'hA5C39E);
        repeat (3000) @(posedge clk);

        expected_word = 24'h000000;
        send_sample(24'h000000);
        repeat (3000) @(posedge clk);

        $display("=================================");
        $display("Checked words: %0d", checked);
        $display("Errors: %0d", errors);

        if (errors == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");

        $display("=================================");

        $finish;
    end

endmodule

