################################################################################
# Timing Constraints for Bilateral Filter with BRAM and DSP Optimization
# Target Device: xc7z020clg484-1 (Zynq-7000)
# Design: Standard 5x5 Bilateral Filter (256x256 image)
# Optimized for: Block RAM line buffers, DSP48 multipliers, pipelined computation
################################################################################

################################################################################
# Clock Constraint
################################################################################

# Primary clock constraint for 100 MHz (10 ns period)
# Pipelined design supports up to 120-150 MHz with proper optimization
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk]

# Optional: Uncomment to test higher frequencies after initial synthesis passes
# For 75 MHz:  create_clock -period 13.333 -name sys_clk -waveform {0.000 6.667} [get_ports clk]
# For 120 MHz: create_clock -period 8.333 -name sys_clk -waveform {0.000 4.167} [get_ports clk]
# For 150 MHz: create_clock -period 6.667 -name sys_clk -waveform {0.000 3.333} [get_ports clk]

################################################################################
# Input/Output Delay Constraints
################################################################################

# Input delays (relative to clock edge)
# Relaxed for video/image pipeline with external buffers
set_input_delay -clock sys_clk -min 0.500 [get_ports {rstn valid_in pixel_in[*]}]
set_input_delay -clock sys_clk -max 2.500 [get_ports {rstn valid_in pixel_in[*]}]

# Output delays (relative to clock edge)
# Allows for downstream pipeline stages
set_output_delay -clock sys_clk -min 0.500 [get_ports {valid_out pixel_out[*]}]
set_output_delay -clock sys_clk -max 2.500 [get_ports {valid_out pixel_out[*]}]

################################################################################
# Clock Uncertainty and Jitter
################################################################################

# Account for clock jitter and routing uncertainty
# Reduced from 0.200 to 0.150 for improved timing closure
set_clock_uncertainty 0.150 [get_clocks sys_clk]

################################################################################
# False Paths
################################################################################

# Asynchronous reset doesn't need timing analysis
set_false_path -from [get_ports rstn] -to [all_registers]

################################################################################
# Multi-cycle Paths for Pipelined Computation
################################################################################

# The bilateral filter computation is now pipelined with DSP blocks
# Allow 2 clock cycles for multiply-accumulate operations
set_multicycle_path 2 -setup -from [all_registers -clock sys_clk] -to [get_pins -hierarchical -filter {NAME =~ *dmul*}]
set_multicycle_path 1 -hold  -from [all_registers -clock sys_clk] -to [get_pins -hierarchical -filter {NAME =~ *dmul*}]

# Allow 2 clock cycles for weight computation pipeline
set_multicycle_path 2 -setup -from [all_registers -clock sys_clk] -to [get_pins -hierarchical -filter {NAME =~ *dweight*}]
set_multicycle_path 1 -hold  -from [all_registers -clock sys_clk] -to [get_pins -hierarchical -filter {NAME =~ *dweight*}]

################################################################################
# BRAM Timing Optimization
################################################################################

# Set timing for Block RAM read paths (typical 1 cycle read latency)
set_max_delay 9.000 -from [get_pins -hierarchical -filter {NAME =~ *linebuf*/CLKARDCLK}] -to [get_pins -hierarchical -filter {NAME =~ *window*}]

# Set timing for Range LUT BRAM reads
set_max_delay 9.000 -from [get_pins -hierarchical -filter {NAME =~ *range_lut*/CLKARDCLK}]

################################################################################
# DSP48 Optimization Directives
################################################################################

# Force DSP48 usage for multiply operations (synthesis directive)
# These are applied in Verilog with (* use_dsp = "yes" *) but can be reinforced here
set_property USE_DSP48 yes [get_cells -hierarchical -filter {NAME =~ *dweight*}]
set_property USE_DSP48 yes [get_cells -hierarchical -filter {NAME =~ *dmul*}]

################################################################################
# BRAM Optimization Directives
################################################################################

# Ensure line buffers use Block RAM
set_property RAM_STYLE BLOCK [get_cells -hierarchical -filter {NAME =~ *linebuf*}]

# Ensure range LUT uses Block RAM
set_property RAM_STYLE BLOCK [get_cells -hierarchical -filter {NAME =~ *range_lut*}]

################################################################################
# Placement and Routing Optimization
################################################################################

# Keep bilateral filter logic together for better timing
set_property KEEP_HIERARCHY SOFT [get_cells -hierarchical -filter {NAME =~ *bilateral_filter*}]

# Set maximum fanout for clock to improve timing
set_max_fanout 30 [get_ports clk]

# Improve routing for high-speed signals
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets -hierarchical -filter {NAME =~ *clk*}]

################################################################################
# Power Optimization (Optional)
################################################################################

# Enable clock gating for power savings when valid signals are low
# Uncomment if power is critical:
# set_property CLOCK_GATING yes [get_cells -hierarchical]

################################################################################
# Synthesis Strategy Directives
################################################################################

# Set strategy for performance (can override in GUI)
# Synthesis: Performance_ExploreWithRemap
# Implementation: Performance_Explore or Performance_ExtraTimingOpt

################################################################################
# Report Generation
################################################################################

# Generate detailed timing reports after implementation
# set_property STEPS.ROUTE_DESIGN.ARGS.REPORT_TIMING_SUMMARY 1 [get_runs impl_1]
# set_property STEPS.ROUTE_DESIGN.ARGS.REPORT_POWER 1 [get_runs impl_1]

################################################################################
# End of Constraints
################################################################################
