`timescale 1ns / 1ps
// AXI4-Lite 32-bit slave, 9 word-aligned registers, 100 MHz clock domain.
// Single outstanding write/read response. AW and W may arrive independently.
module beamformer_axi_regs #(
    parameter integer ADDR_WIDTH = 6,
    parameter integer DELAY_WIDTH = 13
)(
    input wire aclk,
    input wire aresetn,
    input wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,
    output reg beam_enable,
    output reg delay_update,
    output reg clear_history,
    output wire [5*DELAY_WIDTH-1:0] delay_cfg,
    input wire busy,
    input wire config_applied,
    input wire overflow_flag,
    input wire [23:0] peak_level,
    input wire [31:0] sample_counter
);
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    reg [ADDR_WIDTH-1:0] awaddr_hold;
    reg aw_hold;
    reg [31:0] wdata_hold;
    reg [3:0] wstrb_hold;
    reg w_hold;
    reg [DELAY_WIDTH-1:0] delay0,delay1,delay2,delay3,delay4;
    reg config_event;
    reg config_pending;

    assign delay_cfg = {delay4,delay3,delay2,delay1,delay0};
    assign s_axi_awready = !aw_hold && !s_axi_bvalid;
    assign s_axi_wready  = !w_hold && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    // Apply byte strobes to a 32-bit register.
    function [31:0] merge_bytes;
        input [31:0] old_data;
        input [31:0] new_data;
        input [3:0] strobes;
        integer k;
        begin
            merge_bytes = old_data;
            for (k=0;k<4;k=k+1)
                if (strobes[k])
                    merge_bytes[k*8 +: 8] = new_data[k*8 +: 8];
        end
    endfunction

    wire write_fire = aw_hold && w_hold && !s_axi_bvalid;
    reg [31:0] merged;

    always @(posedge aclk) begin
        if (!aresetn) begin
            awaddr_hold <= 0;
            aw_hold <= 0;
            wdata_hold <= 0;
            wstrb_hold <= 0;
            w_hold <= 0;
            s_axi_bresp <= OKAY;
            s_axi_bvalid <= 0;
            s_axi_rdata <= 0;
            s_axi_rresp <= OKAY;
            s_axi_rvalid <= 0;
            beam_enable <= 0;
            delay_update <= 0;
            clear_history <= 0;
            delay0 <= 0; delay1 <= 0; delay2 <= 0;
            delay3 <= 0; delay4 <= 0;
            config_event <= 0;
            config_pending <= 0;
            merged <= 0;
        end else begin
            delay_update <= 0;
            clear_history <= 0;
            if (config_applied) begin
                config_event <= 1;
                config_pending <= 0;
            end
            if (s_axi_awready && s_axi_awvalid) begin
                awaddr_hold <= s_axi_awaddr;
                aw_hold <= 1;
            end
            if (s_axi_wready && s_axi_wvalid) begin
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
                w_hold <= 1;
            end
            if (write_fire) begin
                aw_hold <= 0;
                w_hold <= 0;
                s_axi_bvalid <= 1;
                s_axi_bresp <= OKAY;
                if (awaddr_hold[1:0] != 0)
                    s_axi_bresp <= SLVERR;
                else case (awaddr_hold)
                    6'h00: begin
                        merged = merge_bytes({31'b0,beam_enable},wdata_hold,wstrb_hold);
                        beam_enable <= merged[0];
                        if (wstrb_hold[0] && wdata_hold[1]) begin
                            delay_update <= 1;
                            config_pending <= 1;
                            config_event <= 0;
                        end
                        if (wstrb_hold[0] && wdata_hold[2])
                            clear_history <= 1;
                    end
                    6'h04: delay0 <= merge_bytes({{(32-DELAY_WIDTH){1'b0}},delay0},wdata_hold,wstrb_hold);
                    6'h08: delay1 <= merge_bytes({{(32-DELAY_WIDTH){1'b0}},delay1},wdata_hold,wstrb_hold);
                    6'h0c: delay2 <= merge_bytes({{(32-DELAY_WIDTH){1'b0}},delay2},wdata_hold,wstrb_hold);
                    6'h10: delay3 <= merge_bytes({{(32-DELAY_WIDTH){1'b0}},delay3},wdata_hold,wstrb_hold);
                    6'h14: delay4 <= merge_bytes({{(32-DELAY_WIDTH){1'b0}},delay4},wdata_hold,wstrb_hold);
                    6'h18: begin
                        // W1C sticky configuration event.
                        if (wstrb_hold[0] && wdata_hold[1]) config_event <= 0;
                    end
                    default: s_axi_bresp <= SLVERR;
                endcase
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (s_axi_arready && s_axi_arvalid) begin
                s_axi_rvalid <= 1;
                s_axi_rresp <= OKAY;
                s_axi_rdata <= 0;
                if (s_axi_araddr[1:0] != 0)
                    s_axi_rresp <= SLVERR;
                else case (s_axi_araddr)
                    6'h00: s_axi_rdata <= {31'b0,beam_enable};
                    6'h04: s_axi_rdata <= delay0;
                    6'h08: s_axi_rdata <= delay1;
                    6'h0c: s_axi_rdata <= delay2;
                    6'h10: s_axi_rdata <= delay3;
                    6'h14: s_axi_rdata <= delay4;
                    6'h18: s_axi_rdata <= {28'b0,config_pending,overflow_flag,config_event,busy};
                    6'h1c: s_axi_rdata <= {8'b0,peak_level};
                    6'h20: s_axi_rdata <= sample_counter;
                    default: s_axi_rresp <= SLVERR;
                endcase
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
        end
    end
endmodule
