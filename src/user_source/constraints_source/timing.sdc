create_clock -name audit_ref -period 20 -waveform {0 10} [get_ports {clk}]
create_generated_clock -name audit_sd -source [get_ports {clk}] -master_clock audit_ref -multiply_by 2 -duty_cycle 50 [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
create_generated_clock -name audit_mem -source [get_ports {clk}] -master_clock audit_ref -multiply_by 2.5 -duty_cycle 50 [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
create_generated_clock -name audit_mem_180 -source [get_ports {clk}] -master_clock audit_ref -multiply_by 2.5 -phase 180 -duty_cycle 50 [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
create_generated_clock -name audit_pixel -source [get_ports {clk}] -master_clock audit_ref -multiply_by 1.5 -duty_cycle 50 [get_pins {video_pll_m0/pll_inst.clkc[0]}]
create_generated_clock -name audit_serial -source [get_ports {clk}] -master_clock audit_ref -multiply_by 7.5 -phase 90 -duty_cycle 50 [get_pins {video_pll_m0/pll_inst.clkc[1]}]
set_cross_domain_timing all
set_false_path \
    -from [get_clocks {audit_mem}] \
    -to   [get_clocks {audit_mem_180}]

set_false_path \
    -from [get_clocks {audit_mem_180}] \
    -to   [get_clocks {audit_mem}]

set_false_path \
    -from [get_clocks {audit_mem}] \
    -to   [get_clocks {audit_sd}]

set_false_path \
    -from [get_clocks {audit_sd}] \
    -to   [get_clocks {audit_pixel}]

set_false_path \
    -from [get_clocks {audit_mem}] \
    -to   [get_clocks {audit_pixel}]

set_false_path -from [get_clocks {audit_sd}] -to [get_clocks {audit_ref}]
set_false_path -from [get_clocks {audit_mem}] -to [get_clocks {audit_ref}]
set_false_path -from [get_clocks {audit_pixel}]   -to [get_clocks {audit_ref}]

set_false_path -from [get_regs {*/S_odd_even}] -to [get_regs {*/S_odd_even_1d}]
set_multicycle_path 2 -setup -end -from [get_regs {*/S_pixel_word*}] -to [get_regs {*/S_shift_data*}]
set_multicycle_path 1 -hold -end -from [get_regs {*/S_pixel_word*}] -to [get_regs {*/S_shift_data*}]
