# Zynq I2C Controller + Linux Driver

Custom I2C controller implemented in SystemVerilog and integrated with a Xilinx Zynq-7000 SoC through AXI4-Lite.

The project combines FPGA-based RTL design with processor-side Linux driver development, enabling software control of the custom I2C peripheral through memory-mapped registers.

## Key Features

- Custom I2C controller written in SystemVerilog
- FSM-based protocol handling
- TX/RX buffering
- AXI4-Lite interface for processor–FPGA communication
- Linux kernel module for peripheral control
- Memory-mapped register access
- sysfs interface for user-space interaction
- Timing and synchronization debugging using logic analyzer, oscilloscope, and kernel logs
