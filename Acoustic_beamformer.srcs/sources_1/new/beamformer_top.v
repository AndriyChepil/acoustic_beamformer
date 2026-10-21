`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/21/2026 12:05:26 AM
// Design Name: 
// Module Name: beamformer_top
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


module beamformer_top #(
    parameter integer SAMPLE_WIDTH   = 24,
    parameter integer MAX_DELAY      = 31,
    parameter integer FRAC_BITS      = 8,
    parameter integer AXI_ADDR_WIDTH = 6
)(
    // =====================================================
    // Clock and reset
    // =====================================================

    input wire aclk,
    input wire aresetn,

    // =====================================================
    // AXI4-Lite Write Address Channel
    // =====================================================

    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire s_axi_awvalid,
    output wire s_axi_awready,

    // =====================================================
    // AXI4-Lite Write Data Channel
    // =====================================================

    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire s_axi_wvalid,
    output wire s_axi_wready,

    // =====================================================
    // AXI4-Lite Write Response Channel
    // =====================================================

    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input  wire s_axi_bready,

    // =====================================================
    // AXI4-Lite Read Address Channel
    // =====================================================

    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire s_axi_arvalid,
    output wire s_axi_arready,

    // =====================================================
    // AXI4-Lite Read Data Channel
    // =====================================================

    output wire [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input  wire s_axi_rready,

    // =====================================================
    // Five-channel PCM Input
    // =====================================================

    // Shared I2S clocks for microphones and DAC
    output wire i2s_bclk,
    output wire i2s_ws,

    // Five microphone data inputs
    input wire [4:0] i2s_data,

    // PCM5102A serial audio data output
    output wire i2s_dout,

    // =====================================================
    // Mono PCM Output
    // =====================================================

    output wire signed [SAMPLE_WIDTH-1:0] audio_out,
    output wire audio_valid
);

    // =====================================================
    // Internal PCM signals
    // =====================================================

    wire [5*SAMPLE_WIDTH-1:0] mic_samples;
    wire mic_samples_valid;

    //===================
    // Clock
    //====================
    
    i2s_clock_generator #(
        .CLK_FREQ_HZ(50000000),
        .SAMPLE_RATE_HZ(48000),
        .SLOT_BITS(32),
        .ACC_WIDTH(32)
    ) u_i2s_clk (
        .clk(aclk),
        .rst_n(aresetn),

        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),

        .bclk_rising_tick(),
        .bclk_falling_tick(),
        .frame_tick()
    );
    
    // =====================================================
    // I2S Microphone Receiver
    // =====================================================

    i2s_mic_receiver #(
        .NUM_CHANNELS(5),
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .SLOT_BITS(32),
        .MIC_SLOT(0)
    ) mic_rx_inst (
        .clk(aclk),
        .rst_n(aresetn),

        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),
        .i2s_data(i2s_data),

        .samples_out(mic_samples),
        .samples_valid(mic_samples_valid)
    );

    // =====================================================
    // AXI4-Lite + Beamformer
    // =====================================================

    beamformer_axi_wrapper #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .MAX_DELAY(MAX_DELAY),
        .FRAC_BITS(FRAC_BITS),

        .DELAY_WIDTH(
            $clog2(MAX_DELAY + 1) + FRAC_BITS
        ),

        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH)
    ) u_beamformer_axi_wrapper (

        .aclk(aclk),
        .aresetn(aresetn),

        // AXI Write Address
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),

        // AXI Write Data
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),

        // AXI Write Response
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),

        // AXI Read Address
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),

        // AXI Read Data
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),

        // PCM from I2S receiver
        .samples_in(mic_samples),
        .samples_valid(mic_samples_valid),

        // Beamformer output
        .audio_out(audio_out),
        .audio_valid(audio_valid)
    );
    
    // =====================================================
    // I2S Audio Transmitter - PCM5102A
    // =====================================================

    i2s_audio_transmitter #(
        .SAMPLE_WIDTH(SAMPLE_WIDTH),
        .SLOT_BITS(32)
    ) u_i2s_audio_tx (
        .clk(aclk),
        .rst_n(aresetn),

        // PCM from beamformer
        //.sample_in(audio_out),
        //.sample_valid(audio_valid),
        .sample_in(24'sh400000),
        .sample_valid(1'b1),

        // Shared I2S clocks
        .i2s_bclk(i2s_bclk),
        .i2s_ws(i2s_ws),

        // Serial data to PCM5102A
        .i2s_dout(i2s_dout)
    );

endmodule
