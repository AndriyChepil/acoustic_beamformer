`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/20/2026 08:02:20 PM
// Design Name: 
// Module Name: fractional_delay_tb
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


module fractional_delay_tb;

    parameter SAMPLE_WIDTH = 24;
    parameter MAX_DELAY    = 31;
    parameter FRAC_BITS    = 8;
    parameter DELAY_WIDTH  = 13;

    reg clk;
    reg rst_n;

    reg signed [SAMPLE_WIDTH-1:0] sample_in;
    reg sample_valid;

    reg [DELAY_WIDTH-1:0] delay_value;
    reg clear_history;

    wire signed [SAMPLE_WIDTH-1:0] sample_out;
    wire sample_out_valid;

    integer test_count;
    integer pass_count;
    integer fail_count;
    integer i;

    // =====================================================
    // DUT - Device Under Test
    // =====================================================

    fractional_delay #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .MAX_DELAY(MAX_DELAY),
        .FRAC_BITS(FRAC_BITS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .sample_in(sample_in),
        .sample_valid(sample_valid),

        .delay_value(delay_value),
        .clear_history(clear_history),

        .sample_out(sample_out),
        .sample_out_valid(sample_out_valid)
    );

    // =====================================================
    // Clock generation: 100 MHz
    // =====================================================

    initial clk = 0;

    always #5 clk = ~clk;

    // =====================================================
    // Reset task
    // =====================================================

    task reset_dut;
    begin
        @(negedge clk);

        rst_n         = 0;
        sample_in     = 0;
        sample_valid  = 0;
        delay_value   = 0;
        clear_history = 0;

        repeat (3) @(negedge clk);

        rst_n = 1;

        @(negedge clk);
    end
    endtask

    // =====================================================
    // Send one sample and verify output
    // =====================================================

    task send_and_check;

        input signed [SAMPLE_WIDTH-1:0] input_sample;
        input signed [SAMPLE_WIDTH-1:0] expected_sample;

    begin

        // Drive input before rising edge
        sample_in    = input_sample;
        sample_valid = 1;

        // DUT captures sample
        @(posedge clk);

        // Avoid race with nonblocking assignments
        #1;

        // Stop sending new samples
        @(negedge clk);
        sample_valid = 0;

        // Next rising edge produces output
        @(posedge clk);
        #1;

        test_count = test_count + 1;

        if (!sample_out_valid) begin

            $display(
                "FAIL [%0d]: output valid missing",
                test_count
            );

            fail_count = fail_count + 1;

        end
        else if (sample_out !== expected_sample) begin

            $display(
                "FAIL [%0d]: IN=%0d EXPECTED=%0d GOT=%0d",
                test_count,
                input_sample,
                expected_sample,
                sample_out
            );

            fail_count = fail_count + 1;

        end
        else begin

            $display(
                "PASS [%0d]: IN=%0d OUT=%0d",
                test_count,
                input_sample,
                sample_out
            );

            pass_count = pass_count + 1;

        end

        @(negedge clk);

    end
    endtask

    // =====================================================
    // Test sequence
    // =====================================================

    initial begin

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        rst_n         = 0;
        sample_in     = 0;
        sample_valid  = 0;
        delay_value   = 0;
        clear_history = 0;

        // -------------------------------------------------
        // TEST 1: Zero delay
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 1: ZERO DELAY");
        $display("==================================");

        reset_dut();

        delay_value = 13'h0000;

        send_and_check( 1000,  1000);
        send_and_check( 2000,  2000);
        send_and_check(-1000, -1000);

        // -------------------------------------------------
        // TEST 2: Integer delay = 1
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 2: INTEGER DELAY = 1");
        $display("==================================");

        reset_dut();

        delay_value = 13'h0100;

        send_and_check(1000,    0);
        send_and_check(2000, 1000);
        send_and_check(3000, 2000);

        // -------------------------------------------------
        // TEST 3: Fractional delay = 1.5
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 3: FRACTIONAL DELAY = 1.5");
        $display("==================================");

        reset_dut();

        delay_value = 13'h0180;

        send_and_check(1000,    0);
        send_and_check(2000,  500);
        send_and_check(3000, 1500);
        send_and_check(4000, 2500);

        // -------------------------------------------------
        // TEST 4: Signed fractional delay = 0.5
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 4: SIGNED FRACTIONAL DELAY");
        $display("==================================");

        reset_dut();

        delay_value = 13'h0080;

        send_and_check(-1000, -500);
        send_and_check( 1000,    0);
        send_and_check(-1000,    0);

        // -------------------------------------------------
        // TEST 5: Maximum integer delay = 31
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 5: MAXIMUM DELAY = 31");
        $display("==================================");

        reset_dut();

        delay_value = 13'h1F00;

        send_and_check(12345, 0);

        for (i = 0; i < 30; i = i + 1)
            send_and_check(0, 0);

        // The first sample must appear at n = 31
        send_and_check(0, 12345);

        send_and_check(0, 0);

        // -------------------------------------------------
        // TEST 6: Clear history
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 6: CLEAR HISTORY");
        $display("==================================");

        reset_dut();

        delay_value = 13'h0100;

        send_and_check(5000, 0);
        send_and_check(6000, 5000);

        // Clear buffer
        @(negedge clk);
        clear_history = 1;

        @(posedge clk);
        #1;

        @(negedge clk);
        clear_history = 0;

        // Previous samples must no longer exist
        send_and_check(7000, 0);
        send_and_check(8000, 7000);
        
         // -------------------------------------------------
        // TEST 7: Maximum positive 24-bit PCM
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 7: MAXIMUM POSITIVE PCM");
        $display("==================================");

        reset_dut();

        delay_value = 13'h0000;

        send_and_check( 8388607,  8388607);
        send_and_check(       0,        0);
        send_and_check(-8388608, -8388608);

        // -------------------------------------------------
        // TEST 8: Minimum negative 24-bit PCM
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 8: MINIMUM NEGATIVE PCM");
        $display("==================================");

        reset_dut();

        delay_value = 13'h0080;  // 0.5 samples

        // Average of 0 and -8388608
        send_and_check(-8388608, -4194304);

        // Average of -8388608 and +8388607
        // Exact result = -0.5
        // Arithmetic right shift rounds toward -infinity
        send_and_check(8388607, -1);

        // Average of +8388607 and +8388607
        send_and_check(8388607, 8388607);

        // -------------------------------------------------
        // TEST 9: Maximum fractional delay = 31.5
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 9: MAXIMUM FRACTIONAL DELAY");
        $display("==================================");

        reset_dut();

        delay_value = 13'h1F80;  // 31.5 samples

        // Insert an impulse at n = 0
        send_and_check(10000, 0);

        // n = 1 ... 30
        for (i = 0; i < 30; i = i + 1)
            send_and_check(0, 0);

        // n = 31:
        // x[n-31] = 10000, x[n-32] = 0
        // y = 0.5 * 10000 = 5000
        send_and_check(0, 5000);

        // n = 32:
        // x[n-31] = 0, x[n-32] = 10000
        // y = 0.5 * 10000 = 5000
        send_and_check(0, 5000);

        // n = 33: impulse has passed
        send_and_check(0, 0);

        // -------------------------------------------------
        // TEST 10: Circular buffer wrap-around
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("TEST 10: BUFFER WRAP-AROUND");
        $display("==================================");

        reset_dut();

        delay_value = 13'h0100;  // 1 sample

        // More than two complete buffer cycles
        for (i = 0; i < 80; i = i + 1) begin
            if (i == 0)
                send_and_check(i * 100, 0);
            else
                send_and_check(i * 100, (i - 1) * 100);
        end

        // -------------------------------------------------
        // Final results
        // -------------------------------------------------

        $display("");
        $display("==================================");
        $display("SIMULATION RESULTS");
        $display("==================================");

        $display("Total tests : %0d", test_count);
        $display("Passed      : %0d", pass_count);
        $display("Failed      : %0d", fail_count);

        if (fail_count == 0)
            $display("FINAL RESULT: PASS");
        else
            $display("FINAL RESULT: FAIL");

        $display("==================================");

        $finish;

    end

    // =====================================================
    // Simulation timeout
    // =====================================================

    initial begin
        #1000000;
        $display("ERROR: SIMULATION TIMEOUT");
        $finish;
    end

endmodule
