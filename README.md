# SPI SD Card Interface with VGA Visualization

## Overview
Implemented an FPGA-based system in Verilog to read image data from an SD card over SPI and display it through VGA output on the Intel Cyclone IV DE2-115 FPGA board.

The project integrates SD card communication, frame buffering and VGA video generation into a complete hardware pipeline.

---

## Features
- SPI-based SD card communication
- SD card block data loading
- Frame buffer based image storage
- VGA display controller
- 25 MHz pixel clock generation using PLL IP
- Implemented and tested on Intel Cyclone IV DE2-115

---

## System Architecture

Data Flow:

SD Card  
→ SPI Master  
→ SD Controller  
→ SD Loader  
→ Frame Buffer  
→ VGA Controller  
→ VGA Display

---

## RTL Modules

### top.v
Top-level integration module connecting all submodules.

### spi_master.v
Implements SPI master interface for SD card communication.

### sd_controller.v
Handles SD card command/control sequencing.

### sd_loader.v
Loads image data blocks from SD card into frame buffer.

### frame_buffer.v
Stores pixel data used for display output.

### vga_controller.v
Generates VGA timing and display signals.

### pll_25mhz
25 MHz pixel clock generated using Quartus IP Catalog PLL.

---

## Project Structure
```text
rtl/
├── top.v
├── spi_master.v
├── sd_controller.v
├── sd_loader.v
├── frame_buffer.v
├── vga_controller.v

constraints/
├── sd_vga.sdc
├── sd_vga_de2115.qsf
```

---

## Tools and Platform
- Verilog HDL
- Intel Quartus Prime
- Cyclone IV DE2-115 FPGA
- Quartus PLL IP Catalog

---

## Implementation Notes
- PLL generated through Quartus IP Catalog for VGA pixel clock.
- Timing constraints provided using SDC.
- Pin assignments configured through QSF.
- Modular RTL structure used for subsystem integration.

---

## Functionality
- Initializes and communicates with SD card through SPI
- Transfers image data into frame buffer
- Generates VGA timing signals
- Displays stored image data on monitor

---

## Future Improvements
- Higher resolution support
- Multi-image support from SD card
- BMP parser / file system support
- Hardware acceleration for image processing

---

## Repository Contents
- RTL source files
- Timing and pin constraint files
- Quartus project configuration

---
