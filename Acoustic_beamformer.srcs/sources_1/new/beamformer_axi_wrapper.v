`timescale 1ns / 1ps
// Integration wrapper: AXI-Lite control + five-channel beamformer.
// PCM interface is INTERNAL to PL; connect I2S receiver later.
module beamformer_axi_wrapper #(
    parameter integer SAMPLE_WIDTH = 24,
    parameter integer MAX_DELAY = 31,
    parameter integer FRAC_BITS = 8,
    parameter integer DELAY_WIDTH = $clog2(MAX_DELAY+1)+FRAC_BITS,
    parameter integer AXI_ADDR_WIDTH = 6
)(
    input wire aclk,
    input wire aresetn,
    input wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    input wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    input wire [5*SAMPLE_WIDTH-1:0] samples_in,
    input wire samples_valid,
    output wire signed [SAMPLE_WIDTH-1:0] audio_out,
    output wire audio_valid
);
    wire beam_enable, delay_update, clear_history;
    wire [5*DELAY_WIDTH-1:0] delay_cfg;
    wire [SAMPLE_WIDTH-1:0] peak_level;
    wire [31:0] sample_counter;
    wire busy,config_applied,overflow_flag;

    beamformer_axi_regs #(.ADDR_WIDTH(AXI_ADDR_WIDTH),.DELAY_WIDTH(DELAY_WIDTH)) regs (
        .aclk(aclk),.aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),.s_axi_awvalid(s_axi_awvalid),.s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),.s_axi_wstrb(s_axi_wstrb),.s_axi_wvalid(s_axi_wvalid),.s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),.s_axi_bvalid(s_axi_bvalid),.s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),.s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),.s_axi_rresp(s_axi_rresp),.s_axi_rvalid(s_axi_rvalid),.s_axi_rready(s_axi_rready),
        .beam_enable(beam_enable),.delay_update(delay_update),.clear_history(clear_history),.delay_cfg(delay_cfg),
        .busy(busy),.config_applied(config_applied),.overflow_flag(overflow_flag),
        .peak_level(peak_level),.sample_counter(sample_counter)
    );
    beamformer_core #(.NUM_CHANNELS(5),.SAMPLE_WIDTH(SAMPLE_WIDTH),
        .MAX_DELAY(MAX_DELAY),.FRAC_BITS(FRAC_BITS)) core (
        .clk(aclk),.rst_n(aresetn),.samples_in(samples_in),.samples_valid(samples_valid),
        .delay_cfg(delay_cfg),.delay_update(delay_update),
        .beam_enable(beam_enable),.clear_history(clear_history),
        .audio_out(audio_out),.audio_valid(audio_valid),.peak_level(peak_level),
        .sample_counter(sample_counter),.overflow_flag(overflow_flag),
        .busy(busy),.config_applied(config_applied)
    );
endmodule
