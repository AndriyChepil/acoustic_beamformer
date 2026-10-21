#create_clock -period 20.000 -name sys_clk [get_ports aclk]

# LED GPIO - 8 bits
set_property PACKAGE_PIN V14  [get_ports {gpio_rtl_0_tri_o[0]}]
set_property PACKAGE_PIN AA14 [get_ports {gpio_rtl_0_tri_o[1]}]
set_property PACKAGE_PIN Y16  [get_ports {gpio_rtl_0_tri_o[2]}]
set_property PACKAGE_PIN AB17 [get_ports {gpio_rtl_0_tri_o[3]}]

set_property PACKAGE_PIN W17  [get_ports {gpio_rtl_0_tri_o[4]}]
set_property PACKAGE_PIN W13  [get_ports {gpio_rtl_0_tri_o[5]}]
set_property PACKAGE_PIN AA13 [get_ports {gpio_rtl_0_tri_o[6]}]
set_property PACKAGE_PIN AB15 [get_ports {gpio_rtl_0_tri_o[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {gpio_rtl_0_tri_o[*]}]

# ==============================================
# Acoustic Beamformer - Zynq-7020
# I2S microphones + PCM5102A
# ==============================================

# I2S clocks
set_property PACKAGE_PIN D22 [get_ports i2s_bclk]
set_property PACKAGE_PIN E20   [get_ports i2s_ws]

# DAC PCM5102A
set_property PACKAGE_PIN U22 [get_ports i2s_dout_0]

# Microphone data inputs
set_property PACKAGE_PIN H19 [get_ports {i2s_data[0]}]
set_property PACKAGE_PIN E18 [get_ports {i2s_data[1]}]
set_property PACKAGE_PIN F17 [get_ports {i2s_data[2]}]
set_property PACKAGE_PIN C17 [get_ports {i2s_data[3]}]
set_property PACKAGE_PIN G19 [get_ports {i2s_data[4]}]

# I/O voltage standard
set_property IOSTANDARD LVCMOS33 [get_ports {
    i2s_bclk
    i2s_ws
    i2s_dout_0
    i2s_data[*]
}]