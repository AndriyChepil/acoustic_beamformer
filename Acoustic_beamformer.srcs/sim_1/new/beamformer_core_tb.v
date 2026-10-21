`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/20/2026 11:27:05 PM
// Design Name: 
// Module Name: beamformer_core_tb
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

module beamformer_core_tb;

    localparam integer N = 5;
    localparam integer W = 24;
    localparam integer FB = 8;
    localparam integer DW = 13;
    localparam integer LATENCY = 11;
    localparam integer MAX_EXPECT = 1024;

    // =====================================================
    // Clock and DUT signals
    // =====================================================

    reg clk = 1'b0;
    always #5 clk = ~clk;  // 100 MHz

    reg rst_n = 1'b0;

    reg [N*W-1:0] samples_in = 0;
    reg samples_valid = 0;

    reg [N*DW-1:0] delay_cfg = 0;
    reg delay_update = 0;

    reg beam_enable = 1;
    reg clear_history = 0;

    wire signed [W-1:0] audio_out;
    wire audio_valid;

    wire [W-1:0] peak_level;
    wire [31:0] sample_counter;
    wire overflow_flag;

    wire busy;
    wire config_applied;

    // =====================================================
    // DUT
    // =====================================================

    beamformer_core #(
        .NUM_CHANNELS(N),
        .SAMPLE_WIDTH(W),
        .MAX_DELAY(31),
        .FRAC_BITS(FB)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .samples_in(samples_in),
        .samples_valid(samples_valid),

        .delay_cfg(delay_cfg),
        .delay_update(delay_update),

        .beam_enable(beam_enable),
        .clear_history(clear_history),

        .audio_out(audio_out),
        .audio_valid(audio_valid),

        .peak_level(peak_level),
        .sample_counter(sample_counter),
        .overflow_flag(overflow_flag),

        .busy(busy),
        .config_applied(config_applied)
    );

    // =====================================================
    // Scoreboard and reference model
    // =====================================================

    integer errors = 0;
    integer checked = 0;
    integer sent = 0;
    integer received = 0;
    integer cycle_no = 0;

    integer q_head = 0;
    integer q_tail = 0;

    integer q_value [0:MAX_EXPECT-1];
    integer q_cycle [0:MAX_EXPECT-1];

    reg [W-1:0] model_history [0:N-1][0:31];
    integer model_delay [0:N-1];

    integer model_peak = 0;
    integer model_count = 0;

    integer c;
    integer t;

    integer sum_value;
    integer avg_value;
    integer magnitude;

    integer d_int;
    integer d_frac;

    integer x0;
    integer x1;
    integer interp;

    reg signed [63:0] scaled_interp;
    integer signed_sample;

    // =====================================================
    // Convert 24-bit PCM to signed integer
    // =====================================================

    function integer as_signed24;
        input [23:0] raw;
        begin
            if (raw[23])
                as_signed24 = $signed({{8{raw[23]}}, raw});
            else
                as_signed24 = raw;
        end
    endfunction

    // =====================================================
    // Arithmetic right shift equivalent
    // =====================================================

    function integer floor_div256;
        input signed [63:0] val;
        begin
            floor_div256 = val >>> 8;
        end
    endfunction

    // =====================================================
    // Mean of five with symmetric rounding
    // =====================================================

    function integer mean5;
        input integer total;
        integer abs_total;
        begin
            abs_total = (total < 0) ? -total : total;

            mean5 = (abs_total + 2) / 5;

            if (total < 0)
                mean5 = -mean5;
        end
    endfunction

    // =====================================================
    // Reset reference model
    // =====================================================

    task clear_model;
        integer a, b;
        begin
            for (a = 0; a < N; a = a + 1)
                for (b = 0; b < 32; b = b + 1)
                    model_history[a][b] = 0;

            q_head = 0;
            q_tail = 0;

            model_peak = 0;
            model_count = 0;
        end
    endtask

    // =====================================================
    // Reference model for one accepted audio frame
    // =====================================================

    task model_frame;
        integer a, b;
        begin
            sum_value = 0;

            for (a = 0; a < N; a = a + 1) begin

                signed_sample =
                    as_signed24(samples_in[a*W +: W]);

                d_int = model_delay[a] >> FB;
                d_frac = model_delay[a] & 255;

                if (d_int == 0)
                    x0 = signed_sample;
                else
                    x0 = as_signed24(
                        model_history[a][d_int-1]
                    );

                x1 = as_signed24(
                    model_history[a][d_int]
                );

                scaled_interp =
                    ($signed(x0) * 64'sd256) +
                    ($signed(x1) - $signed(x0)) *
                    $signed(d_frac);

                interp = floor_div256(scaled_interp);

                sum_value = sum_value + interp;

                for (b = 31; b > 0; b = b - 1)
                    model_history[a][b] =
                        model_history[a][b-1];

                model_history[a][0] =
                    samples_in[a*W +: W];
            end

            avg_value = mean5(sum_value);

            if (q_tail >= MAX_EXPECT) begin
                $display("ERROR: expected queue overflow");
                $finish;
            end

            q_value[q_tail] = avg_value;
            q_cycle[q_tail] = cycle_no + LATENCY;

            q_tail = q_tail + 1;
            sent = sent + 1;
        end
    endtask

    // =====================================================
    // Send one PCM frame
    // =====================================================

    task send_frame;
        input integer a0, a1, a2, a3, a4;
        begin
            @(negedge clk);

            samples_in[0*W +: W] = a0;
            samples_in[1*W +: W] = a1;
            samples_in[2*W +: W] = a2;
            samples_in[3*W +: W] = a3;
            samples_in[4*W +: W] = a4;

            samples_valid = 1;

            if (beam_enable && !clear_history)
                model_frame();

            @(negedge clk);
            samples_valid = 0;
        end
    endtask

    // =====================================================
    // Idle cycles
    // =====================================================

    task idle_cycles;
        input integer count;
        integer j;
        begin
            for (j = 0; j < count; j = j + 1)
                @(negedge clk);
        end
    endtask

    // =====================================================
    // Wait for pipeline to drain
    // =====================================================

    task wait_drain;
        begin
            idle_cycles(LATENCY + 5);

            if (q_head != q_tail) begin
                $display(
                    "ERROR: undelivered frames: %0d",
                    q_tail - q_head
                );
                errors = errors + 1;
            end
        end
    endtask

    // =====================================================
    // Configure fractional delays
    // =====================================================

    task set_delays;
        input integer d0, d1, d2, d3, d4;
        begin
            @(negedge clk);

            delay_cfg[0*DW +: DW] = d0;
            delay_cfg[1*DW +: DW] = d1;
            delay_cfg[2*DW +: DW] = d2;
            delay_cfg[3*DW +: DW] = d3;
            delay_cfg[4*DW +: DW] = d4;

            delay_update = 1;

            @(negedge clk);
            delay_update = 0;

            // Apply at frame boundary without
            // admitting a processing frame.

            beam_enable = 0;
            samples_valid = 1;

            @(negedge clk);
            samples_valid = 0;

            idle_cycles(2);

            model_delay[0] = d0;
            model_delay[1] = d1;
            model_delay[2] = d2;
            model_delay[3] = d3;
            model_delay[4] = d4;

            beam_enable = 1;
        end
    endtask

    // =====================================================
    // Flush sample history
    // =====================================================

    task flush_history;
        begin
            wait_drain();

            @(negedge clk);
            clear_history = 1;

            clear_model();

            @(negedge clk);
            clear_history = 0;

            idle_cycles(2);
        end
    endtask

    // =====================================================
    // Output scoreboard
    // =====================================================

    always @(posedge clk) begin
        if (rst_n) begin

            cycle_no = cycle_no + 1;

            // Wait until nonblocking assignments finish
            #1;

            if (audio_valid) begin

                received = received + 1;

                if (q_head >= q_tail) begin
                    $display(
                        "FAIL unexpected output cycle=%0d data=%0d",
                        cycle_no,
                        audio_out
                    );
                    errors = errors + 1;
                end
                else begin

                    if ($signed(audio_out) !==
                        q_value[q_head]) begin

                        $display(
                            "FAIL sample %0d cycle=%0d got=%0d expected=%0d",
                            checked,
                            cycle_no,
                            $signed(audio_out),
                            q_value[q_head]
                        );

                        errors = errors + 1;
                    end

                    checked = checked + 1;

                    magnitude =
                        (q_value[q_head] < 0)
                        ? -q_value[q_head]
                        : q_value[q_head];

                    if (magnitude > model_peak)
                        model_peak = magnitude;

                    model_count = model_count + 1;

                    if (peak_level !== model_peak[W-1:0]) begin
                        $display(
                            "FAIL peak got=%0d expected=%0d",
                            peak_level,
                            model_peak
                        );
                        errors = errors + 1;
                    end

                    if (sample_counter !== model_count) begin
                        $display(
                            "FAIL count got=%0d expected=%0d",
                            sample_counter,
                            model_count
                        );
                        errors = errors + 1;
                    end

                    q_head = q_head + 1;
                end
            end

            if (overflow_flag !== 1'b0) begin
                $display("FAIL overflow_flag asserted");
                errors = errors + 1;
            end
        end
    end

    // =====================================================
    // Main test sequence
    // =====================================================

    initial begin

        clear_model();

        for (c = 0; c < N; c = c + 1)
            model_delay[c] = 0;

        idle_cycles(4);
        rst_n = 1;
        idle_cycles(2);

        // -------------------------------------------------
        // TEST 1: Zero delay
        // -------------------------------------------------

        $display("TEST 1: zero delay, identical channels");

        set_delays(0, 0, 0, 0, 0);

        send_frame(1000, 1000, 1000, 1000, 1000);

        send_frame(-1001, -1001, -1001, -1001, -1001);

        send_frame(
            8388607, 8388607, 8388607, 8388607, 8388607
        );

        send_frame(
            -8388608, -8388608, -8388608,
            -8388608, -8388608
        );

        wait_drain();

        // -------------------------------------------------
        // TEST 2: Mixed positive/negative PCM
        // -------------------------------------------------

        $display("TEST 2: mixed positive/negative samples");

        send_frame(100, 200, -300, 400, -500);
        send_frame(-1, 0, 0, 0, 0);
        send_frame(1, 0, 0, 0, 0);
        send_frame(3, 0, 0, 0, 0);

        wait_drain();

        // -------------------------------------------------
        // TEST 3: Integer delays
        // -------------------------------------------------

        $display("TEST 3: integer delays 0..4");

        flush_history();

        set_delays(0, 256, 512, 768, 1024);

        for (t = 0; t < 42; t = t + 1)
            send_frame(
                t*100,
                t*200,
                t*300,
                t*400,
                t*500
            );

        wait_drain();

        // -------------------------------------------------
        // TEST 4: Fractional delays
        // -------------------------------------------------

        $display("TEST 4: fractional delays");

        flush_history();

        set_delays(128, 384, 640, 896, 1152);

        for (t = 0; t < 42; t = t + 1)
            send_frame(
                t*101 - 500,
                t*201 - 700,
                t*301 - 900,
                t*401 - 1100,
                t*501 - 1300
            );

        wait_drain();

        // -------------------------------------------------
        // TEST 5: Maximum fractional delay
        // -------------------------------------------------

        $display("TEST 5: max delay 31.996 samples");

        flush_history();

        set_delays(8191, 8191, 8191, 8191, 8191);

        for (t = 0; t < 42; t = t + 1)
            send_frame(
                t*1000,
                t*1000,
                t*1000,
                t*1000,
                t*1000
            );

        wait_drain();

        // -------------------------------------------------
        // TEST 6: Global beam enable
        // -------------------------------------------------

        $display("TEST 6: beam_enable blocks new frames");

        flush_history();

        set_delays(0, 0, 0, 0, 0);

        @(negedge clk);

        beam_enable = 0;
        samples_valid = 1;
        samples_in = {5{24'd1234}};

        idle_cycles(3);

        samples_valid = 0;
        beam_enable = 1;

        send_frame(987, 987, 987, 987, 987);

        wait_drain();

        // -------------------------------------------------
        // TEST 7: Clear history and restart
        // -------------------------------------------------

        $display("TEST 7: reset history, then restart");

        flush_history();

        set_delays(256, 256, 256, 256, 256);

        send_frame(5000, 5000, 5000, 5000, 5000);
        send_frame(6000, 6000, 6000, 6000, 6000);

        wait_drain();

        flush_history();

        send_frame(7000, 7000, 7000, 7000, 7000);

        wait_drain();

        // -------------------------------------------------
        // Final report
        // -------------------------------------------------

        $display("------------------------------------------");

        $display(
            "Sent=%0d Received=%0d Checked=%0d Errors=%0d",
            sent,
            received,
            checked,
            errors
        );

        if (errors == 0 &&
            q_head == q_tail &&
            received == sent)
            $display("PASS: beamformer_core integration tests");
        else
            $display("FAIL: beamformer_core integration tests");

        $finish;
    end

    // =====================================================
    // Simulation timeout
    // =====================================================

    initial begin
        #1000000;
        $display("FAIL: simulation timeout");
        $finish;
    end

endmodule

