# Standard Bilateral Filter

This repository contains the hardware implementation of a Standard Bilateral Filter on FPGA using Xilinx Vivado.

## Overview
The bilateral filter is a non-linear, edge-preserving, and noise-reducing smoothing filter for images. This project implements the filter's architecture targeting a Xilinx Zynq-7000 series FPGA (`xc7z020clg484-1`). 

## Implementation Results

The design was synthesized and implemented using Xilinx Vivado. Below are the hardware utilization and power consumption metrics obtained from the post-implementation reports.

### Resource Utilization
| Resource Type      | Used    | Available | Utilization (%) |
|--------------------|---------|-----------|-----------------|
| **Slice LUTs**     | 17,680  | 53,200    | 33.23%          |
| **Slice Registers**| 10,420  | 106,400   | 9.79%           |
| **DSPs (DSP48E1)** | 31      | 220       | 14.09%          |
| **Block RAM**      | 0       | 140       | 0.00%           |

### Power Consumption
- **Total On-Chip Power**: 0.602 W
  - **Dynamic Power**: 0.490 W
  - **Device Static Power**: 0.112 W

### Timing
- **Clock Constraint**: 10.0 ns (100 MHz)

## Tools Used
- Xilinx Vivado
- Target FPGA: `xc7z020clg484-1`
