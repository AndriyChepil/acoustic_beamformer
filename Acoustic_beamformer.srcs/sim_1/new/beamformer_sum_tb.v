`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/20/2026 09:59:37 PM
// Design Name: 
// Module Name: beamformer_sum_tb
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

module beamformer_sum_tb;

    parameter SAMPLE_WIDTH = 24;

    localparam integer PIPELINE_STAGES = 6;

    localparam signed [SAMPLE_WIDTH-1:0] PCM_MAX =  8388607;
    localparam signed [SAMPLE_WIDTH-1:0] PCM_MIN = -8388608;

    reg clk;
    reg rst_n;

    reg signed [SAMPLE_WIDTH-1:0] sample_ch0;
    reg signed [SAMPLE_WIDTH-1:0] sample_ch1;
    reg signed [SAMPLE_WIDTH-1:0] sample_ch2;
    reg signed [SAMPLE_WIDTH-1:0] sample_ch3;
    reg signed [SAMPLE_WIDTH-1:0] sample_ch4;

    reg sample_valid;

    wire signed [SAMPLE_WIDTH-1:0] sample_out;
    wire sample_out_valid;

    integer test_count;
    integer pass_count;
    integer fail_count;
    integer cycle_count;

    integer i;
    integer k;

    // Expected pipeline
    reg signed [SAMPLE_WIDTH-1:0]
        expected_data [0:PIPELINE_STAGES-1];

    reg expected_valid [0:PIPELINE_STAGES-1];

    // =====================================================
    // DUT
    // =====================================================

    beamformer_sum #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .sample_ch0(sample_ch0),
        .sample_ch1(sample_ch1),
        .sample_ch2(sample_ch2),
        .sample_ch3(sample_ch3),
        .sample_ch4(sample_ch4),

        .sample_valid(sample_valid),

        .sample_out(sample_out),
        .sample_out_valid(sample_out_valid)
    );

    // =====================================================
    // Clock: 100 MHz
    // =====================================================

    initial clk = 0;
    always #5 clk = ~clk;

    // =====================================================
    // Reference model: exact average of 5 channels
    // =====================================================

    function signed [SAMPLE_WIDTH-1:0] reference_sum;
        input signed [SAMPLE_WIDTH-1:0] a;
        input signed [SAMPLE_WIDTH-1:0] b;
        input signed [SAMPLE_WIDTH-1:0] c;
        input signed [SAMPLE_WIDTH-1:0] d;
        input signed [SAMPLE_WIDTH-1:0] e;

        reg signed [SAMPLE_WIDTH+2:0] total;
        reg signed [SAMPLE_WIDTH+2:0] rounded;
        reg signed [SAMPLE_WIDTH+2:0] result;

        begin
            total =
                $signed(a) +
                $signed(b) +
                $signed(c) +
                $signed(d) +
                $signed(e);

            if (total >= 0)
                rounded = total + 2;
            else
                rounded = total - 2;

            result = rounded / 5;

            reference_sum = result[SAMPLE_WIDTH-1:0];
        end
    endfunction

    // =====================================================
    // One clock cycle + scoreboard
    // =====================================================

    task tick;
        reg signed [SAMPLE_WIDTH-1:0] new_expected;

        begin
            // Sample input values before rising edge
            new_expected = reference_sum(
                sample_ch0,
                sample_ch1,
                sample_ch2,
                sample_ch3,
                sample_ch4
            );

            @(posedge clk);

            // Wait for nonblocking assignments in DUT
            #1;

            if (!rst_n) begin
                for (k = 0; k < PIPELINE_STAGES; k = k + 1) begin
                    expected_valid[k] = 0;
                    expected_data[k]  = 0;
                end
            end
            else begin

                // Shift expected pipeline
                for (k = PIPELINE_STAGES-1; k > 0; k = k - 1) begin
                    expected_valid[k] = expected_valid[k-1];
                    expected_data[k]  = expected_data[k-1];
                end

                expected_valid[0] = sample_valid;

                if (sample_valid)
                    expected_data[0] = new_expected;
            end

            cycle_count = cycle_count + 1;

            // Check output valid on every clock
            if (sample_out_valid !==
                expected_valid[PIPELINE_STAGES-1]) begin

                fail_count = fail_count + 1;

                $display(
                    "FAIL VALID cycle=%0d expected=%b actual=%b",
                    cycle_count,
                    expected_valid[PIPELINE_STAGES-1],
                    sample_out_valid
                );
            end

            // Check data only when expected valid
            if (expected_valid[PIPELINE_STAGES-1]) begin

                test_count = test_count + 1;

                if (sample_out ===
                    expected_data[PIPELINE_STAGES-1]) begin

                    pass_count = pass_count + 1;

                    $display(
                        "PASS [%0d] OUT=%0d",
                        test_count,
                        $signed(sample_out)
                    );
                end
                else begin

                    fail_count = fail_count + 1;

                    $display(
                        "FAIL [%0d] expected=%0d actual=%0d",
                        test_count,
                        $signed(expected_data[PIPELINE_STAGES-1]),
                        $signed(sample_out)
                    );
                end
            end

            // Next stimulus is applied after falling edge
            @(negedge clk);
        end
    endtask

    // =====================================================
    // Send one frame
    // =====================================================

    task send_frame;
        input signed [SAMPLE_WIDTH-1:0] a;
        input signed [SAMPLE_WIDTH-1:0] b;
        input signed [SAMPLE_WIDTH-1:0] c;
        input signed [SAMPLE_WIDTH-1:0] d;
        input signed [SAMPLE_WIDTH-1:0] e;

        begin
            sample_ch0 = a;
            sample_ch1 = b;
            sample_ch2 = c;
            sample_ch3 = d;
            sample_ch4 = e;

            sample_valid = 1;
            tick();
        end
    endtask

    // =====================================================
    // Idle cycle
    // =====================================================

    task idle_cycle;
        begin
            sample_valid = 0;
            tick();
        end
    endtask

    // =====================================================
    // Flush pipeline
    // =====================================================

    task flush_pipeline;
        integer j;
        begin
            for (j = 0; j < PIPELINE_STAGES; j = j + 1)
                idle_cycle();
        end
    endtask

    // =====================================================
    // Main test sequence
    // =====================================================

    initial begin

        rst_n = 0;

        sample_ch0 = 0;
        sample_ch1 = 0;
        sample_ch2 = 0;
        sample_ch3 = 0;
        sample_ch4 = 0;

        sample_valid = 0;

        test_count  = 0;
        pass_count  = 0;
        fail_count  = 0;
        cycle_count = 0;

        for (i = 0; i < PIPELINE_STAGES; i = i + 1) begin
            expected_valid[i] = 0;
            expected_data[i]  = 0;
        end

        // Reset
        repeat (4) tick();
        rst_n = 1;

        // -------------------------------------------------
        // TEST 1: Identical signals
        // -------------------------------------------------

        $display("");
        $display("TEST 1: IDENTICAL SIGNALS");

        send_frame(1000, 1000, 1000, 1000, 1000);
        flush_pipeline();

        // -------------------------------------------------
        // TEST 2: Single active channel
        // -------------------------------------------------

        $display("");
        $display("TEST 2: SINGLE ACTIVE CHANNEL");

        send_frame(5000, 0, 0, 0, 0);
        flush_pipeline();

        // -------------------------------------------------
        // TEST 3: Mixed signed signals
        // -------------------------------------------------

        $display("");
        $display("TEST 3: MIXED SIGNED SIGNALS");

        send_frame(1000, -1000, 2000, -2000, 500);
        flush_pipeline();

        // -------------------------------------------------
        // TEST 4: Maximum PCM
        // -------------------------------------------------

        $display("");
        $display("TEST 4: PCM MAX");

        send_frame(
            PCM_MAX, PCM_MAX, PCM_MAX, PCM_MAX, PCM_MAX
        );
        flush_pipeline();

        // -------------------------------------------------
        // TEST 5: Minimum PCM
        // -------------------------------------------------

        $display("");
        $display("TEST 5: PCM MIN");

        send_frame(
            PCM_MIN, PCM_MIN, PCM_MIN, PCM_MIN, PCM_MIN
        );
        flush_pipeline();

        // -------------------------------------------------
        // TEST 6: Positive rounding
        // -------------------------------------------------

        $display("");
        $display("TEST 6: POSITIVE ROUNDING");

        send_frame(1, 1, 1, 0, 0);
        send_frame(1, 1, 0, 0, 0);
        send_frame(1, 0, 0, 0, 0);
        flush_pipeline();

        // -------------------------------------------------
        // TEST 7: Negative rounding
        // -------------------------------------------------

        $display("");
        $display("TEST 7: NEGATIVE ROUNDING");

        send_frame(-1, -1, -1, 0, 0);
        send_frame(-1, -1, 0, 0, 0);
        send_frame(-1, 0, 0, 0, 0);
        flush_pipeline();

        // -------------------------------------------------
        // TEST 8: Continuous stream
        // -------------------------------------------------

        $display("");
        $display("TEST 8: CONTINUOUS STREAM");

        for (i = 0; i < 100; i = i + 1) begin
            send_frame(
                i * 100,
                i * 200,
                -(i * 50),
                i * 300,
                -(i * 150)
            );
        end

        flush_pipeline();

        // -------------------------------------------------
        // TEST 9: Alternating polarity
        // -------------------------------------------------

        $display("");
        $display("TEST 9: ALTERNATING POLARITY");

        for (i = 0; i < 20; i = i + 1) begin

            if (i % 2 == 0)
                send_frame(
                    8000000, -8000000,
                    8000000, -8000000, 0
                );
            else
                send_frame(
                    -8000000, 8000000,
                    -8000000, 8000000, 0
                );
        end

        flush_pipeline();

        // -------------------------------------------------
        // TEST 10: Reset during operation
        // -------------------------------------------------

        $display("");
        $display("TEST 10: RESET DURING OPERATION");

        send_frame(1000, 2000, 3000, 4000, 5000);
        send_frame(2000, 3000, 4000, 5000, 6000);

        // Reset before pending frames reach output
        rst_n = 0;
        sample_valid = 0;

        repeat (3) tick();

        rst_n = 1;

        send_frame(100, 200, 300, 400, 500);
        flush_pipeline();

        // -------------------------------------------------
        // Final results
        // -------------------------------------------------

        $display("");
        $display("=================================");
        $display("SIMULATION RESULTS");
        $display("=================================");

        $display("Total checked frames : %0d", test_count);
        $display("Passed               : %0d", pass_count);
        $display("Failed               : %0d", fail_count);

        if (fail_count == 0)
            $display("FINAL RESULT: PASS");
        else
            $display("FINAL RESULT: FAIL");

        $display("=================================");

        $finish;
    end

endmodule

