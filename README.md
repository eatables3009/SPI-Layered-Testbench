# SPI Layered Testbench (SystemVerilog)

This repository contains a **layered testbench implementation** used to verify the functionality of an SPI (Serial Peripheral Interface) master–slave communication system. The verification follows a **UVM-lite style** environment, separating stimulus generation, driving, monitoring, and result checking to ensure clarity, scalability, and reusability.

**When running on EDA Playground add (-access +rwc -coverage all -covoverwrite -covtest spi_loopback) in Run Options to see coverage analysis.**

## 🧩 Testbench Architecture
The testbench is structured into the following components:
- **Transaction** – Represents a single SPI data frame (Master TX/RX and Slave TX/RX).
- **Generator** – Randomizes and sends transactions to the driver.
- **Driver** – Drives SPI signals based on the transaction.
- **Monitor** – Observes SPI outputs and reconstructs received data.
- **Scoreboard** – Compares expected vs actual data and reports PASS/FAIL.
- **Environment** – Instantiates, connects, and manages all TB components.

## 🔄 Communication Model
- Full-duplex **8-bit** data shifting on **MOSI** and **MISO**.
- **Master controls** SCLK and CS_n.
- Both ends simultaneously transmit and receive data per clock cycle.

## ✅ Assertions Included
The testbench includes protocol-level SystemVerilog Assertions to ensure:
- CS_n stays high when idle
- CS_n goes low after start
- SCLK remains stable when CS_n is high
- Finish is a single-cycle pulse
- Data is only valid when finish is asserted
- No overlapping transfers occur
- CS_n resets to high after reset

## 📊 Output & Reporting
The scoreboard prints pass/fail for each transaction, and coverage monitors data distribution and state behavior.

---
