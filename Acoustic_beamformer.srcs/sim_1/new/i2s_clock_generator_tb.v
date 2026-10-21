`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/21/2026 03:09:28 AM
// Design Name: 
// Module Name: i2s_clock_generator_tb
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

module i2s_clock_generator_tb;

    // =====================================================
    // Parameters
    // =====================================================

    localparam integer CLK_FREQ_HZ    = 50000000;
    localparam integer SAMPLE_RATE_HZ = 48000;
    localparam integer SLOT_BITS      = 32;

    localparam integer BCLK_FREQ_HZ =
        SAMPLE_RATE_HZ * SLOT_BITS * 2;

    localparam integer CLK_PERIOD_NS = 20;

    localparam integer TEST_FRAMES = 1000;

    // =====================================================
    // DUT signals
    // =====================================================

    reg clk;
    reg rst_n;

    wire i2s_bclk;
    wire i2s_ws;

    wire bclk_rising_tick;
    wire bclk_falling_tick;
    wire frame_tick;

    // =====================================================
    // Counters
    // =====================================================

    integer errors;
    integer checked_frames;

    integer bclk_rises;
    integer bclk_falls;
    integer ws_rises;
    integer ws_falls;
    integer frame_ticks;

    integer slot_bit_count;
    integer frame_bit_count;

    integer cycles_since_bclk;
    integer last_bclk_cycles;

    integer min_bclk_cycles;
    integer max_bclk_cycles;

    integer start_time_ns;
    integer end_time_ns;

    real measured_sample_rate;
    real measured_bclk_rate;

    reg previous_bclk;
    reg previous_ws;

    reg previous_rising_tick;
    reg previous_falling_tick;
    reg previous_frame_tick;

    reg tracking_enabled;

    // =====================================================
    // DUT
    // =====================================================

    i2s_clock_generator #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .SAMPLE_RATE_HZ(SAMPLE_RATE_HZ),
        .SLOT_BITS(SLOT_BITS),
        .ACC_WIDTH(32)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),

        .bclk_rising_tick(bclk_rising_tick),
        .bclk_falling_tick(bclk_falling_tick),
        .frame_tick(frame_tick)
    );

    // =====================================================
    // 50 MHz clock
    // =====================================================

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    // =====================================================
    // Error reporting
    // =====================================================

    task report_error;
        input [8*120-1:0] message;
        begin
            errors = errors + 1;
            $display("ERROR: %0s at %0t", message, $time);
        end
    endtask

    // =====================================================
    // Reset counters
    // =====================================================

    task reset_counters;
        begin
            checked_frames = 0;

            bclk_rises = 0;
            bclk_falls = 0;

            ws_rises = 0;
            ws_falls = 0;

            frame_ticks = 0;

            slot_bit_count = 0;
            frame_bit_count = 0;

            cycles_since_bclk = 0;
            last_bclk_cycles = 0;

            min_bclk_cycles = 1000000;
            max_bclk_cycles = 0;

            previous_bclk = i2s_bclk;
            previous_ws = i2s_ws;

            previous_rising_tick = bclk_rising_tick;
            previous_falling_tick = bclk_falling_tick;
            previous_frame_tick = frame_tick;
        end
    endtask

    // =====================================================
    // Signal monitor
    //
    // Sample after NBA updates, so all DUT registered
    // outputs have settled.
    // =====================================================

    always @(posedge clk) begin
        #1;

        if (rst_n && tracking_enabled) begin

            cycles_since_bclk = cycles_since_bclk + 1;

            // ---------------------------------------------
            // Rising edge of BCLK
            // ---------------------------------------------

            if (!previous_bclk && i2s_bclk) begin

                bclk_rises = bclk_rises + 1;
                frame_bit_count = frame_bit_count + 1;
                slot_bit_count = slot_bit_count + 1;

                if (!bclk_rising_tick)
                    report_error(
                        "Missing bclk_rising_tick"
                    );

                if (bclk_falling_tick)
                    report_error(
                        "Falling tick during BCLK rising edge"
                    );

                if (bclk_rises > 1) begin

                    last_bclk_cycles = cycles_since_bclk;

                    if (last_bclk_cycles < min_bclk_cycles)
                        min_bclk_cycles = last_bclk_cycles;

                    if (last_bclk_cycles > max_bclk_cycles)
                        max_bclk_cycles = last_bclk_cycles;

                end

                cycles_since_bclk = 0;
            end

            // ---------------------------------------------
            // Falling edge of BCLK
            // ---------------------------------------------

            if (previous_bclk && !i2s_bclk) begin

                bclk_falls = bclk_falls + 1;

                if (!bclk_falling_tick)
                    report_error(
                        "Missing bclk_falling_tick"
                    );

                if (bclk_rising_tick)
                    report_error(
                        "Rising tick during BCLK falling edge"
                    );
            end

            // ---------------------------------------------
            // Tick consistency
            // ---------------------------------------------

            if (bclk_rising_tick &&
                !( !previous_bclk && i2s_bclk ))
                report_error(
                    "Unexpected bclk_rising_tick"
                );

            if (bclk_falling_tick &&
                !( previous_bclk && !i2s_bclk ))
                report_error(
                    "Unexpected bclk_falling_tick"
                );

            // ---------------------------------------------
            // WS rising edge
            // ---------------------------------------------

            if (!previous_ws && i2s_ws) begin

                ws_rises = ws_rises + 1;

                if (i2s_bclk)
                    report_error(
                        "WS changed while BCLK high"
                    );

                if (slot_bit_count != SLOT_BITS)
                    report_error(
                        "Incorrect first slot length"
                    );

                slot_bit_count = 0;
            end

            // ---------------------------------------------
            // WS falling edge
            // ---------------------------------------------

            if (previous_ws && !i2s_ws) begin

                ws_falls = ws_falls + 1;

                if (i2s_bclk)
                    report_error(
                        "WS changed while BCLK high"
                    );

                if (slot_bit_count != SLOT_BITS)
                    report_error(
                        "Incorrect second slot length"
                    );

                slot_bit_count = 0;

                if (frame_bit_count != 2*SLOT_BITS)
                    report_error(
                        "Incorrect frame length"
                    );

                frame_bit_count = 0;
                checked_frames = checked_frames + 1;
            end

            // ---------------------------------------------
            // Frame tick
            // ---------------------------------------------

            if (frame_tick) begin

                frame_ticks = frame_ticks + 1;

                if (!(previous_ws && !i2s_ws))
                    report_error(
                        "frame_tick not aligned with frame end"
                    );

            end

            if (previous_frame_tick && frame_tick)
                report_error(
                    "frame_tick longer than one clock cycle"
                );

            // ---------------------------------------------
            // Update previous values
            // ---------------------------------------------

            previous_bclk = i2s_bclk;
            previous_ws = i2s_ws;

            previous_rising_tick = bclk_rising_tick;
            previous_falling_tick = bclk_falling_tick;
            previous_frame_tick = frame_tick;

        end
    end

    // =====================================================
    // Test sequence
    // =====================================================

    initial begin

        errors = 0;
        tracking_enabled = 0;

        rst_n = 0;

        $display("========================================");
        $display(" I2S CLOCK GENERATOR TESTBENCH");
        $display("========================================");

        $display("CLK frequency  : %0d Hz", CLK_FREQ_HZ);
        $display("Sample rate    : %0d Hz", SAMPLE_RATE_HZ);
        $display("BCLK frequency : %0d Hz", BCLK_FREQ_HZ);
        $display("Slot bits      : %0d", SLOT_BITS);
        $display("Test frames    : %0d", TEST_FRAMES);

        // ---------------------------------------------
        // TEST 1: Reset
        // ---------------------------------------------

        $display("");
        $display("TEST 1: Reset");

        repeat (10) @(negedge clk);

        if (i2s_bclk !== 1'b0)
            report_error("BCLK not zero during reset");

        if (i2s_ws !== 1'b0)
            report_error("WS not zero during reset");

        if (frame_tick !== 1'b0)
            report_error("frame_tick not zero during reset");

        $display("Reset check completed");

        // ---------------------------------------------
        // TEST 2: Normal operation
        // ---------------------------------------------

        $display("");
        $display("TEST 2: Normal clock generation");

        rst_n = 1;

        // Wait for a complete frame boundary.
        @(posedge frame_tick);
        @(negedge clk);

        reset_counters();

        tracking_enabled = 1;
        start_time_ns = $time;

        wait (checked_frames >= TEST_FRAMES);

        @(negedge clk);

        tracking_enabled = 0;
        end_time_ns = $time;

        // ---------------------------------------------
        // Frequency measurements
        // ---------------------------------------------

        measured_sample_rate =
            (checked_frames * 1.0e9) /
            (end_time_ns - start_time_ns);

        measured_bclk_rate =
            (bclk_rises * 1.0e9) /
            (end_time_ns - start_time_ns);

        $display("");
        $display("========================================");
        $display(" RESULTS");
        $display("========================================");

        $display("Checked frames : %0d", checked_frames);

        $display("BCLK rises     : %0d", bclk_rises);
        $display("BCLK falls     : %0d", bclk_falls);

        $display("WS rises       : %0d", ws_rises);
        $display("WS falls       : %0d", ws_falls);

        $display("Frame ticks    : %0d", frame_ticks);

        $display("");
        $display("Measured sample rate : %f Hz",
                 measured_sample_rate);

        $display("Measured BCLK rate   : %f Hz",
                 measured_bclk_rate);

        $display("BCLK period min : %0d system clocks",
                 min_bclk_cycles);

        $display("BCLK period max : %0d system clocks",
                 max_bclk_cycles);

        // ---------------------------------------------
        // Final checks
        // ---------------------------------------------

        if (checked_frames != TEST_FRAMES)
            report_error("Frame count mismatch");

        if (frame_ticks != TEST_FRAMES)
            report_error("Frame tick count mismatch");

        if (ws_rises != TEST_FRAMES)
            report_error("WS rising edge count mismatch");

        if (ws_falls != TEST_FRAMES)
            report_error("WS falling edge count mismatch");

        if (bclk_rises != TEST_FRAMES*2*SLOT_BITS)
            report_error("BCLK rising edge count mismatch");

        if (bclk_falls != TEST_FRAMES*2*SLOT_BITS)
            report_error("BCLK falling edge count mismatch");

        if ((measured_sample_rate < 47900.0) ||
            (measured_sample_rate > 48100.0))
            report_error("Sample rate outside tolerance");

        if ((measured_bclk_rate < 3060000.0) ||
            (measured_bclk_rate > 3084000.0))
            report_error("BCLK rate outside tolerance");

        // ---------------------------------------------
        // Final result
        // ---------------------------------------------

        $display("");

        if (errors == 0) begin
            $display("========================================");
            $display(" PASS: I2S CLOCK GENERATOR");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display(" FAIL: %0d errors", errors);
            $display("========================================");
        end

        $finish;

    end

    // =====================================================
    // Timeout protection
    // =====================================================

    initial begin
        #30000000;

        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule

