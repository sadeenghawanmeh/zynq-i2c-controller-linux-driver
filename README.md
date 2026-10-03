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

## Architecture

The design consists of a custom I2C controller implemented in RTL, connected to TX/RX FIFOs and exposed to the Zynq processing system through an AXI4-Lite interface.

On the software side, Linux kernel drivers access the custom I2C hardware through memory-mapped registers. A separate driver was also developed for the MCP23008 I/O expander.

The end-to-end communication path is:

Linux → AXI4-Lite → Custom I2C IP → MCP23008 → Linux

## RTL Design

The I2C finite-state machine supports:

- Simple write transactions
- Complex write transactions
- Simple read transactions
- Complex read transactions
- TX/RX FIFO buffering
- Read/write sequencing and protocol control

## Linux Driver

The Linux driver provides processor-side control of the custom I2C peripheral through memory-mapped registers.

A separate driver was developed for the MCP23008 expander to configure pin directions, enable pull-ups, and read/write GPIO values.

## Debugging and Improvements

Several timing and synchronization issues were identified during hardware testing:

- An FSM read path initially triggered twice instead of once.
- RX FIFO return data was occasionally incorrect despite correct internal read/write operation.
- MCP23008 reads initially returned stale FIFO data.

These issues were debugged using an oscilloscope and corrected through FSM logic changes, edge detection, and additional timing delay where required.

## Result

The final system achieved end-to-end communication between Linux, the custom I2C controller, and the MCP23008 expander.
