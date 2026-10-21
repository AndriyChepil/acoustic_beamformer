`timescale 1ns / 1ps
// Self-checking AXI4-Lite + beamformer integration test (Verilog-2001).
// DUT: beamformer_top; all processing runs on aclk (100 MHz).
module beamformer_axi_tb;
    localparam integer AW = 6;
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    localparam [AW-1:0] CONTROL=6'h00, D0=6'h04, D1=6'h08,
        D2=6'h0c, D3=6'h10, D4=6'h14, STATUS=6'h18,
        PEAK=6'h1c, COUNT=6'h20;

    reg aclk = 0;
    always #5 aclk = ~aclk;
    reg aresetn = 0;
    reg [AW-1:0] s_axi_awaddr = 0;
    reg s_axi_awvalid = 0;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata = 0;
    reg [3:0] s_axi_wstrb = 0;
    reg s_axi_wvalid = 0;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready = 0;
    reg [AW-1:0] s_axi_araddr = 0;
    reg s_axi_arvalid = 0;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready = 0;
    reg [119:0] samples_in = 0;
    reg samples_valid = 0;
    wire signed [23:0] audio_out;
    wire audio_valid;

    beamformer_top dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready), .samples_in(samples_in),
        .samples_valid(samples_valid), .audio_out(audio_out),
        .audio_valid(audio_valid)
    );

    integer errors = 0;
    integer checks = 0;
    integer audio_seen = 0;
    integer update_pulses = 0;
    integer clear_pulses = 0;
    reg [31:0] rd_data;
    reg [1:0] rd_resp;
    reg [1:0] wr_resp;
    integer k;

    // Inspect pulses at the AXI-register block boundary.
    always @(posedge aclk) begin
        if (aresetn) begin
            if (dut.u_beamformer_axi_wrapper.regs.delay_update)
                update_pulses = update_pulses + 1;
            if (dut.u_beamformer_axi_wrapper.regs.clear_history)
                clear_pulses = clear_pulses + 1;
            if (audio_valid)
                audio_seen = audio_seen + 1;
        end
    end

    task check32;
        input [31:0] got;
        input [31:0] expected;
        input [8*70-1:0] description;
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got=%h expected=%h at %0t", description, got, expected, $time);
            end else
                $display("PASS %0s = %h", description, got);
        end
    endtask

    task check_resp;
        input [1:0] got;
        input [1:0] expected;
        input [8*70-1:0] description;
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: response=%b expected=%b", description, got, expected);
            end else
                $display("PASS %0s response=%b", description, got);
        end
    endtask

    // AW and W sent independently; aw_first selects ordering.
    // hold_response keeps BREADY low for several clocks to check stability.
    task axi_write;
        input [AW-1:0] addr;
        input [31:0] data;
        input [3:0] strb;
        input integer aw_first;
        input integer hold_response;
        output [1:0] response;
        integer wait_n;
        begin
            if (aw_first == 1) begin
                send_aw(addr);
                repeat (2) @(negedge aclk);
                send_w(data, strb);
            end else if (aw_first == 2) begin
                send_w(data, strb);
                repeat (2) @(negedge aclk);
                send_aw(addr);
            end else begin
                fork
                    send_aw(addr);
                    send_w(data, strb);
                join
            end
            wait_n = 0;
            while (s_axi_bvalid !== 1'b1 && wait_n < 40) begin
                @(negedge aclk);
                wait_n = wait_n + 1;
            end
            if (s_axi_bvalid !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL AXI write timeout addr=%h", addr);
                response = 2'bxx;
            end else begin
                response = s_axi_bresp;
                repeat (hold_response) begin
                    @(negedge aclk);
                    if (s_axi_bvalid !== 1'b1 || s_axi_bresp !== response) begin
                        errors = errors + 1;
                        $display("FAIL B response unstable during backpressure");
                    end
                end
                s_axi_bready = 1;
                @(negedge aclk);
                s_axi_bready = 0;
            end
        end
    endtask

    task send_aw;
        input [AW-1:0] addr;
        integer wait_n;
        begin
            @(negedge aclk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1;
            wait_n = 0;
            begin : aw_loop
                forever begin
                    @(posedge aclk);
                    if (s_axi_awready) disable aw_loop;
                    wait_n = wait_n + 1;
                    if (wait_n > 40) begin
                        errors = errors + 1;
                        $display("FAIL AW handshake timeout");
                        disable aw_loop;
                    end
                end
            end
            @(negedge aclk);
            s_axi_awvalid = 0;
        end
    endtask

    task send_w;
        input [31:0] data;
        input [3:0] strb;
        integer wait_n;
        begin
            @(negedge aclk);
            s_axi_wdata = data;
            s_axi_wstrb = strb;
            s_axi_wvalid = 1;
            wait_n = 0;
            begin : w_loop
                forever begin
                    @(posedge aclk);
                    if (s_axi_wready) disable w_loop;
                    wait_n = wait_n + 1;
                    if (wait_n > 40) begin
                        errors = errors + 1;
                        $display("FAIL W handshake timeout");
                        disable w_loop;
                    end
                end
            end
            @(negedge aclk);
            s_axi_wvalid = 0;
        end
    endtask

    task axi_read;
        input [AW-1:0] addr;
        input integer hold_response;
        output [31:0] data;
        output [1:0] response;
        integer wait_n;
        begin
            @(negedge aclk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1;
            wait_n = 0;
            begin : ar_loop
                forever begin
                    @(posedge aclk);
                    if (s_axi_arready) disable ar_loop;
                    wait_n = wait_n + 1;
                    if (wait_n > 40) begin
                        errors = errors + 1;
                        $display("FAIL AR handshake timeout");
                        disable ar_loop;
                    end
                end
            end
            @(negedge aclk);
            s_axi_arvalid = 0;
            wait_n = 0;
            while (s_axi_rvalid !== 1'b1 && wait_n < 40) begin
                @(negedge aclk);
                wait_n = wait_n + 1;
            end
            if (s_axi_rvalid !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL AXI read timeout addr=%h", addr);
                data = 32'hxxxxxxxx;
                response = 2'bxx;
            end else begin
                data = s_axi_rdata;
                response = s_axi_rresp;
                repeat (hold_response) begin
                    @(negedge aclk);
                    if (s_axi_rvalid !== 1'b1 ||
                        s_axi_rdata !== data || s_axi_rresp !== response) begin
                        errors = errors + 1;
                        $display("FAIL R response unstable during backpressure");
                    end
                end
                s_axi_rready = 1;
                @(negedge aclk);
                s_axi_rready = 0;
            end
        end
    endtask

    task send_frame;
        input signed [23:0] a, b, c, d, e;
        begin
            @(negedge aclk);
            samples_in = {e,d,c,b,a};
            samples_valid = 1;
            @(negedge aclk);
            samples_valid = 0;
        end
    endtask

    initial begin
        $display("=== beamformer AXI4-Lite integration test ===");
        repeat (6) @(negedge aclk);
        aresetn = 1;
        repeat (3) @(negedge aclk);

        $display("TEST 1: reset values and read backpressure");
        axi_read(CONTROL, 3, rd_data, rd_resp);
        check_resp(rd_resp, OKAY, "CONTROL read");
        check32(rd_data, 0, "CONTROL reset");
        axi_read(D0, 0, rd_data, rd_resp);
        check32(rd_data, 0, "DELAY0 reset");
        axi_read(STATUS, 0, rd_data, rd_resp);
        check32(rd_data, 0, "STATUS reset");

        $display("TEST 2: independent AW/W and five delay registers");
        axi_write(D0, 32'd0,    4'hf, 1, 2, wr_resp);
        check_resp(wr_resp, OKAY, "AW first");
        axi_write(D1, 32'd128,  4'hf, 2, 0, wr_resp);
        check_resp(wr_resp, OKAY, "W first");
        axi_write(D2, 32'd256,  4'hf, 0, 0, wr_resp);
        axi_write(D3, 32'd384,  4'hf, 1, 0, wr_resp);
        axi_write(D4, 32'd8191, 4'hf, 2, 0, wr_resp);
        axi_read(D0, 0, rd_data, rd_resp); check32(rd_data, 0, "DELAY0");
        axi_read(D1, 0, rd_data, rd_resp); check32(rd_data, 128, "DELAY1");
        axi_read(D2, 0, rd_data, rd_resp); check32(rd_data, 256, "DELAY2");
        axi_read(D3, 0, rd_data, rd_resp); check32(rd_data, 384, "DELAY3");
        axi_read(D4, 0, rd_data, rd_resp); check32(rd_data, 8191, "DELAY4");

        $display("TEST 3: WSTRB byte updates and 13-bit masking");
        axi_write(D1, 32'h00001234, 4'b0001, 0, 0, wr_resp);
        axi_read(D1, 0, rd_data, rd_resp);
        check32(rd_data, 32'h00000034, "low byte update");
        axi_write(D1, 32'h00001f00, 4'b0010, 0, 0, wr_resp);
        axi_read(D1, 0, rd_data, rd_resp);
        check32(rd_data, 32'h00001f34, "high byte update");
        axi_write(D1, 32'hffffffff, 4'b1100, 0, 0, wr_resp);
        axi_read(D1, 0, rd_data, rd_resp);
        check32(rd_data, 32'h00001f34, "ignored upper bytes");
        axi_write(D1, 32'd0, 4'hf, 0, 0, wr_resp);

        $display("TEST 4: invalid addresses return SLVERR");
        axi_write(6'h05, 32'hdeadbeef, 4'hf, 0, 0, wr_resp);
        check_resp(wr_resp, SLVERR, "unaligned write");
        axi_read(6'h05, 0, rd_data, rd_resp);
        check_resp(rd_resp, SLVERR, "unaligned read");
        axi_write(6'h24, 32'hdeadbeef, 4'hf, 0, 0, wr_resp);
        check_resp(wr_resp, SLVERR, "unmapped write");
        axi_read(6'h24, 0, rd_data, rd_resp);
        check_resp(rd_resp, SLVERR, "unmapped read");

        $display("TEST 5: enable, apply, pending, sticky event");
        // Use zero delays for deterministic audio test later.
        for (k=0; k<5; k=k+1) begin
            axi_write(D0 + k*4, 0, 4'hf, 0, 0, wr_resp);
        end
        axi_write(CONTROL, 32'h00000003, 4'h1, 1, 2, wr_resp);
        axi_read(CONTROL, 0, rd_data, rd_resp);
        check32(rd_data, 1, "beam enable + command auto-clear");
        axi_read(STATUS, 0, rd_data, rd_resp);
        check32(rd_data & 32'h8, 32'h8, "configuration pending");
        // A frame boundary causes beamformer_core to apply pending delay config.
        send_frame(1000,1000,1000,1000,1000);
        repeat (5) @(negedge aclk);
        axi_read(STATUS, 0, rd_data, rd_resp);
        check32(rd_data & 32'h0a, 32'h02, "config applied sticky and no pending");
        check32(update_pulses, 1, "exactly one delay_update pulse");
        axi_write(STATUS, 32'h2, 4'h1, 0, 0, wr_resp);
        axi_read(STATUS, 0, rd_data, rd_resp);
        check32(rd_data & 32'h2, 0, "W1C configuration event");

        $display("TEST 6: audio output, peak and sample count");
        repeat (18) @(negedge aclk);
        axi_read(COUNT, 0, rd_data, rd_resp);
        check32(rd_data, 1, "one output frame counted");
        axi_read(PEAK, 0, rd_data, rd_resp);
        check32(rd_data, 1000, "peak 1000");
        check32(audio_seen, 1, "one audio_valid pulse");
        send_frame(-2500,-2500,-2500,-2500,-2500);
        repeat (18) @(negedge aclk);
        axi_read(COUNT, 0, rd_data, rd_resp);
        check32(rd_data, 2, "two output frames counted");
        axi_read(PEAK, 0, rd_data, rd_resp);
        check32(rd_data, 2500, "peak 2500");
        check32(audio_seen, 2, "two audio_valid pulses");
        check32({{8{audio_out[23]}},audio_out}, 32'hfffff63c, "last PCM -2500");

        $display("TEST 7: clear history and disable");
        axi_write(CONTROL, 32'h00000005, 4'h1, 2, 0, wr_resp);
        repeat (3) @(negedge aclk);
        check32(clear_pulses, 1, "one clear_history pulse");
        axi_read(COUNT, 0, rd_data, rd_resp);
        check32(rd_data, 0, "sample counter cleared");
        axi_read(PEAK, 0, rd_data, rd_resp);
        check32(rd_data, 0, "peak cleared");
        axi_write(CONTROL, 32'h0, 4'h1, 0, 0, wr_resp);
        axi_read(CONTROL, 0, rd_data, rd_resp);
        check32(rd_data, 0, "beam disabled");
        send_frame(7000,7000,7000,7000,7000);
        repeat (18) @(negedge aclk);
        axi_read(COUNT, 0, rd_data, rd_resp);
        check32(rd_data, 0, "disabled frames not processed");

        $display("==============================================");
        $display("Checks=%0d Errors=%0d Audio frames=%0d", checks, errors, audio_seen);
        if (errors == 0) $display("PASS: beamformer AXI integration tests");
        else $display("FAIL: beamformer AXI integration tests");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: testbench timeout");
        $finish;
    end
endmodule
