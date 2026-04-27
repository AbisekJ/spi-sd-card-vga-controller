# =============================================================================
# FILE: sd_vga.sdc
# TARGET: DE2-115 (EP4CE115F29C7)
# =============================================================================

create_clock -name {CLOCK_50} -period 20.000 [get_ports {CLOCK_50}]

derive_pll_clocks
derive_clock_uncertainty

set_false_path -from [get_ports {KEY[0]}]
set_false_path -from [get_ports {SD_MISO}]
set_false_path -to   [get_ports {SD_CS_N}]
set_false_path -to   [get_ports {SD_SCLK}]
set_false_path -to   [get_ports {SD_MOSI}]
set_false_path -to   [get_ports {VGA_*}]
set_false_path -to   [get_ports {LEDR[*]}]
