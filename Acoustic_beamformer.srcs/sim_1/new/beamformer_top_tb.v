module beamformer_top_tb;

    localparam integer CLK_PERIOD_NS = 20;
    localparam integer SAMPLE_WIDTH  = 24;
    localparam integer SLOT_BITS     = 32;
    localparam integer NUM_CHANNELS  = 5;
    localparam integer TEST_FRAMES   = 32;
    localparam integer TIMEOUT_NS    = 2000000;

    // -------------------------------------------------
    // Clock and reset
    // -------------------------------------------------

    reg aclk = 1'b0;
    reg aresetn = 1'b0;

    always #(CLK_PERIOD_NS/2) aclk = ~aclk;

    // -------------------------------------------------
    // AXI4-Lite
    // -------------------------------------------------

    reg  [5:0]  s_axi_awaddr  = 0;
    reg         s_axi_awvalid = 0;
    wire        s_axi_awready;

    reg  [31:0] s_axi_wdata   = 0;
    reg  [3:0]  s_axi_wstrb   = 0;
    reg         s_axi_wvalid  = 0;
    wire        s_axi_wready;

    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready  = 0;

    reg  [5:0]  s_axi_araddr  = 0;
    reg         s_axi_arvalid = 0;
    wire        s_axi_arready;

    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready  = 0;

    // -------------------------------------------------
    // I2S
    // -------------------------------------------------

    wire i2s_bclk;
    wire i2s_ws;
    wire i2s_dout;

    reg [4:0] i2s_data = 0;

    wire signed [23:0] audio_out;
    wire audio_valid;

    // -------------------------------------------------
    // Test data and counters
    // -------------------------------------------------

    reg signed [23:0] mic_data [0:4];

    integer errors = 0;
    integer sent_frames = 0;
    integer received_frames = 0;

    integer i;
    integer bit_index;

    reg signed [26:0] expected_sum;
    reg signed [23:0] expected_audio;

    reg [31:0] frame_number = 0;

    reg previous_ws = 0;
    reg previous_bclk = 0;

    integer ws_edges = 0;
    integer bclk_edges = 0;

    // -------------------------------------------------
    // DUT
    // -------------------------------------------------

    beamformer_top #(
        .SAMPLE_WIDTH(24),
        .MAX_DELAY(31),
        .FRAC_BITS(8),
        .AXI_ADDR_WIDTH(6)
    ) dut (

        .aclk(aclk),
        .aresetn(aresetn),

        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),

        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),

        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),

        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),

        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),

        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),
        .i2s_data(i2s_data),
        .i2s_dout(i2s_dout),

        .audio_out(audio_out),
        .audio_valid(audio_valid)
    );

    // -------------------------------------------------
    // AXI write transaction
    //
    // AW and W are independently handshaked.
    // -------------------------------------------------

    task axi_write;
        input [5:0] addr;
        input [31:0] data;

        reg aw_done;
        reg w_done;

        begin
            @(negedge aclk);

            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;

            s_axi_wdata   = data;
            s_axi_wstrb   = 4'b1111;
            s_axi_wvalid  = 1'b1;

            s_axi_bready  = 1'b1;

            aw_done = 0;
            w_done  = 0;

            while (!aw_done || !w_done) begin

                @(posedge aclk);

                if (s_axi_awvalid && s_axi_awready)
                    aw_done = 1;

                if (s_axi_wvalid && s_axi_wready)
                    w_done = 1;

                @(negedge aclk);

                if (aw_done)
                    s_axi_awvalid = 0;

                if (w_done)
                    s_axi_wvalid = 0;
            end

            while (!s_axi_bvalid)
                @(negedge aclk);

            if (s_axi_bresp !== 2'b00) begin
                errors = errors + 1;
                $display("ERROR: AXI write response");
            end

            @(negedge aclk);
            s_axi_bready = 0;

            $display("AXI WRITE addr=%h data=%h",
                     addr, data);
        end
    endtask

    // -------------------------------------------------
    // Generate microphone samples
    // -------------------------------------------------

    task generate_samples;
        input integer frame;

        begin
            mic_data[0] = 24'sd100000 + frame*100;
            mic_data[1] = 24'sd200000 + frame*100;
            mic_data[2] = 24'sd300000 + frame*100;
            mic_data[3] = 24'sd400000 + frame*100;
            mic_data[4] = 24'sd500000 + frame*100;
        end
    endtask

    // -------------------------------------------------
    // Drive I2S data
    //
    // I2S standard:
    // WS changes one BCLK before the MSB.
    //
    // Five microphones use separate data lines.
    // Only the left slot is populated.
    // -------------------------------------------------

    integer slot_counter = 0;

    always @(negedge i2s_bclk) begin

        if (!aresetn) begin
            i2s_data = 0;
            slot_counter = 0;
        end
        else begin

            if (i2s_ws == 1'b0) begin

                if (slot_counter == 0) begin
                    generate_samples(sent_frames);
                end

                if (slot_counter >= 1 &&
                    slot_counter <= SAMPLE_WIDTH) begin

                    bit_index =
                        SAMPLE_WIDTH - slot_counter;

                    for (i=0; i<NUM_CHANNELS; i=i+1)
                        i2s_data[i] =
                            mic_data[i][bit_index];

                end
                else begin
                    i2s_data = 0;
                end

            end
            else begin
                i2s_data = 0;
            end

            slot_counter = slot_counter + 1;

            if (slot_counter >= SLOT_BITS)
                slot_counter = 0;

        end
    end

    // -------------------------------------------------
    // Count transmitted frames
    // -------------------------------------------------

    always @(negedge i2s_ws) begin

        if (aresetn) begin
            sent_frames = sent_frames + 1;
        end
    end

    // -------------------------------------------------
    // Audio output monitor
    // -------------------------------------------------

    always @(posedge aclk) begin

        if (aresetn && audio_valid) begin

            received_frames = received_frames + 1;

            $display(
                "AUDIO frame=%0d value=%0d time=%0t",
                received_frames,
                $signed(audio_out),
                $time
            );

        end

    end

    // -------------------------------------------------
    // DAC I2S self-checking monitor (Philips I2S, 24/32)
    // -------------------------------------------------
    // The TX captures the latest sample on the LEFT-slot boundary.
    // Track that boundary independently of the DUT internals.

    reg [23:0] dac_pending_pcm = 24'd0;
    reg [23:0] dac_active_pcm  = 24'd0;
    integer dac_valid_samples = 0;
    integer dac_checked_words = 0;
    integer dac_nonzero_words = 0;
    integer dac_padding_errors = 0;
    integer dac_data_errors = 0;
    integer dac_skipped_words = 0;

    // Capture the most recent beamformer sample on the system clock.
    always @(posedge aclk) begin
        if (!aresetn) begin
            dac_pending_pcm <= 24'd0;
            dac_valid_samples <= 0;
        end else if (audio_valid) begin
            dac_pending_pcm <= audio_out;
            dac_valid_samples <= dac_valid_samples + 1;
        end
    end

    // Left slot starts on falling WS; TX should latch pending PCM.
    always @(negedge i2s_ws) begin
        if (aresetn)
            dac_active_pcm <= dac_pending_pcm;
    end

    reg dac_ws_previous = 1'b1;
    integer dac_bit_position = 0;
    reg [23:0] dac_shift_word = 24'd0;
    reg [23:0] dac_expected_word = 24'd0;
    integer dac_slots_seen = 0;
    integer dac_slot_errors = 0;
    reg dac_slot_ws = 1'b0;

    // DAC samples DIN on the rising BCLK edge.
    // WS transition occupies bit position 0 (the one-bit I2S delay).
    // Positions 1..24 carry PCM[23:0]; 25..31 are zero padding.
    always @(posedge i2s_bclk) begin
        if (!aresetn) begin
            dac_ws_previous = 1'b1;
            dac_bit_position = 0;
            dac_shift_word = 0;
            dac_expected_word = 0;
            dac_slots_seen = 0;
            dac_slot_errors = 0;
            dac_slot_ws = 0;
        end else begin
            if (i2s_ws !== dac_ws_previous) begin
                dac_bit_position = 0;
                dac_shift_word = 0;
                dac_slot_errors = 0;
                dac_slot_ws = i2s_ws;
                // Expected PCM is latched on the left-slot boundary.
                dac_expected_word = dac_active_pcm;
            end else begin
                dac_bit_position = dac_bit_position + 1;
            end
            dac_ws_previous = i2s_ws;

            if (dac_bit_position >= 1 && dac_bit_position <= 24)
                dac_shift_word[24-dac_bit_position] = i2s_dout;

            if (dac_bit_position >= 25 && dac_bit_position <= 31) begin
                if (i2s_dout !== 1'b0) begin
                    dac_slot_errors = dac_slot_errors + 1;
                    dac_padding_errors = dac_padding_errors + 1;
                end
            end

            if (dac_bit_position == 31) begin
                dac_slots_seen = dac_slots_seen + 1;
                // Skip initial startup slots before the pipeline is primed.
                if (dac_slots_seen > 4) begin
                    dac_checked_words = dac_checked_words + 1;
                    if (dac_shift_word !== dac_expected_word) begin
                        dac_data_errors = dac_data_errors + 1;
                        errors = errors + 1;
                        $display("ERROR DAC WS=%b got=%h expected=%h time=%0t",
                                 dac_slot_ws, dac_shift_word, dac_expected_word, $time);
                    end else if (dac_checked_words <= 12) begin
                        $display("OK DAC WS=%b PCM=%h", dac_slot_ws, dac_shift_word);
                    end
                    if (dac_shift_word != 24'd0)
                        dac_nonzero_words = dac_nonzero_words + 1;
                    if (dac_slot_errors != 0) begin
                        errors = errors + dac_slot_errors;
                        $display("ERROR DAC padding WS=%b bad_bits=%0d", dac_slot_ws, dac_slot_errors);
                    end
                end else begin
                    dac_skipped_words = dac_skipped_words + 1;
                end
            end
        end
    end

    // -------------------------------------------------
    // I2S clock monitor
    // -------------------------------------------------

    always @(posedge aclk) begin

        if (aresetn) begin

            if (i2s_ws != previous_ws)
                ws_edges = ws_edges + 1;

            if (i2s_bclk != previous_bclk)
                bclk_edges = bclk_edges + 1;

        end

        previous_ws <= i2s_ws;
        previous_bclk <= i2s_bclk;

    end

    // -------------------------------------------------
    // Main test
    // -------------------------------------------------

    initial begin

        $display("=====================================");
        $display(" BEAMFORMER TOP INTEGRATION TEST");
        $display("=====================================");

        repeat (20) @(negedge aclk);
        aresetn = 1;

        // Allow clocks to stabilize
        repeat (100) @(negedge aclk);

        // ---------------------------------------------
        // Configure zero delays
        //
        // IMPORTANT:
        // Register addresses must match
        // beamformer_axi_regs.v
        // ---------------------------------------------

        $display("Configuring beamformer");

        // Example addresses.
        // Replace if register map differs.

        axi_write(6'h04, 32'h00000000);
        axi_write(6'h08, 32'h00000000);
        axi_write(6'h0C, 32'h00000000);
        axi_write(6'h10, 32'h00000000);
        axi_write(6'h14, 32'h00000000);
        // Enable beamformer
        axi_write(6'h00, 32'h00000001);
        // ---------------------------------------------
        // Run audio stream
        // ---------------------------------------------

        $display("Starting audio stream");

        wait (sent_frames >= TEST_FRAMES);

        // Wait for pipeline
        repeat (2000) @(negedge aclk);

        // ---------------------------------------------
        // Results
        // ---------------------------------------------

        $display("");
        $display("=====================================");
        $display(" RESULTS");
        $display("=====================================");

        $display("Sent frames     : %0d", sent_frames);
        $display("Received frames : %0d", received_frames);

        $display("WS edges        : %0d", ws_edges);
        $display("BCLK edges      : %0d", bclk_edges);

        $display("DAC checked words : %0d", dac_checked_words);
        $display("DAC nonzero words : %0d", dac_nonzero_words);
        $display("DAC data errors   : %0d", dac_data_errors);
        $display("DAC padding errors: %0d", dac_padding_errors);

        if (dac_checked_words < 8) begin
            errors = errors + 1;
            $display("ERROR: Too few DAC words checked");
        end
        if (dac_nonzero_words == 0) begin
            errors = errors + 1;
            $display("ERROR: No nonzero DAC output observed");
        end

        $display("Errors          : %0d", errors);

        if (received_frames == 0) begin
            errors = errors + 1;
            $display("ERROR: No audio output");
        end

        if (errors == 0)
            $display("PASS: BEAMFORMER TOP TEST");
        else
            $display("FAIL: BEAMFORMER TOP TEST");

        $finish;

    end

    // -------------------------------------------------
    // Timeout
    // -------------------------------------------------

    initial begin
        #TIMEOUT_NS;
        $display("ERROR: Simulation timeout");
        $finish;
    end

endmodule

