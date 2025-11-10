//TESTBENCH
`timescale 1ns/1ps

//=============================================================================
// Transaction Class - Represents a single SPI transaction
//=============================================================================
class spi_transaction;
    rand bit [7:0] master_data;
    rand bit [7:0] slave_data;
    bit [7:0] master_received;
    bit [7:0] slave_received;
    bit finish;
    bit data_valid;
    
    // Constraints
    constraint data_c {
        master_data inside {[0:255]};
        slave_data inside {[0:255]};
    }
    
    // Display function
    function void display(string tag = "");
        $display("[%s] Time=%0t | M_TX=0x%0h | S_TX=0x%0h | M_RX=0x%0h | S_RX=0x%0h", 
                 tag, $time, master_data, slave_data, master_received, slave_received);
    endfunction
endclass

//=============================================================================
// Generator Class - Generates random transactions
//=============================================================================
class generator;
    mailbox #(spi_transaction) gen2drv;
    event drv_done;
    int num_transactions;
    
    function new(mailbox #(spi_transaction) g2d, event done);
        this.gen2drv = g2d;
        this.drv_done = done;
        this.num_transactions = 10; // Default
    endfunction
    
    task run();
        spi_transaction trans;
        repeat(num_transactions) begin
            trans = new();
            assert(trans.randomize()) else $error("Randomization failed!");
            gen2drv.put(trans);
            trans.display("GEN");
            @(drv_done);
            #100; // Gap between transactions
        end
    endtask
endclass

//=============================================================================
// Driver Class - Drives transactions to DUT
//=============================================================================
class driver;
    virtual spi_if vif;
    mailbox #(spi_transaction) gen2drv;
    mailbox #(spi_transaction) drv2scb;
    event drv_done;
    
    function new(virtual spi_if vif, mailbox #(spi_transaction) g2d, 
                 mailbox #(spi_transaction) d2s, event done);
        this.vif = vif;
        this.gen2drv = g2d;
        this.drv2scb = d2s;
        this.drv_done = done;
    endfunction
    
    task run();
        spi_transaction trans;
        forever begin
            gen2drv.get(trans);
            drive_transaction(trans);
            drv2scb.put(trans);
            ->drv_done;
        end
    endtask
    
    task drive_transaction(spi_transaction trans);
        @(posedge vif.clk);
        vif.data_m_in <= trans.master_data;
        vif.data_s_in <= trans.slave_data;
        vif.start_m <= 1'b1;
        
        @(posedge vif.clk);
        vif.start_m <= 1'b0;
        
        // Wait for transaction to complete
        wait(vif.finish_m == 1'b1);
        @(posedge vif.clk);
        
        trans.display("DRV");
    endtask
endclass

//=============================================================================
// Monitor Class - Monitors DUT outputs
//=============================================================================
class monitor;
    virtual spi_if vif;
    mailbox #(spi_transaction) mon2scb;
    
    function new(virtual spi_if vif, mailbox #(spi_transaction) m2s);
        this.vif = vif;
        this.mon2scb = m2s;
    endfunction
    
    task run();
        spi_transaction trans;
        forever begin
            trans = new();
            @(posedge vif.finish_m);
            @(posedge vif.clk);
            trans.master_received = vif.data_m_out;
            trans.slave_received = vif.data_s_out;
            trans.finish = vif.finish_m;
            trans.data_valid = vif.data_valid_s;
            mon2scb.put(trans);
            trans.display("MON");
        end
    endtask
endclass

//=============================================================================
// Scoreboard Class - Checks results
//=============================================================================
class scoreboard;
    mailbox #(spi_transaction) drv2scb;
    mailbox #(spi_transaction) mon2scb;
    int passed, failed;
    
    function new(mailbox #(spi_transaction) d2s, mailbox #(spi_transaction) m2s);
        this.drv2scb = d2s;
        this.mon2scb = m2s;
        this.passed = 0;
        this.failed = 0;
    endfunction
    
    task run();
        spi_transaction exp_trans, act_trans;
        forever begin
            drv2scb.get(exp_trans);
            mon2scb.get(act_trans);
            
            // Master should receive what slave transmitted
            if(act_trans.master_received == exp_trans.slave_data) begin
                $display("[SCB-PASS] Master received correct data: 0x%0h", act_trans.master_received);
                passed++;
            end else begin
                $display("[SCB-FAIL] Master expected 0x%0h, got 0x%0h", 
                         exp_trans.slave_data, act_trans.master_received);
                failed++;
            end
            
            // Slave should receive what master transmitted
            if(act_trans.slave_received == exp_trans.master_data) begin
                $display("[SCB-PASS] Slave received correct data: 0x%0h", act_trans.slave_received);
                passed++;
            end else begin
                $display("[SCB-FAIL] Slave expected 0x%0h, got 0x%0h", 
                         exp_trans.master_data, act_trans.slave_received);
                failed++;
            end
            
            $display("---------------------------------------------------");
        end
    endtask
    
    function void report();
        $display("\n===========================================");
        $display("         SIMULATION RESULTS");
        $display("===========================================");
        $display("Total Checks: %0d", passed + failed);
        $display("Passed: %0d", passed);
        $display("Failed: %0d", failed);
        if(failed == 0)
            $display("STATUS: ALL TESTS PASSED!");
        else
            $display("STATUS: SOME TESTS FAILED!");
        $display("===========================================\n");
    endfunction
endclass

//=============================================================================
// Environment Class - Contains all verification components
//=============================================================================
class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;
    
    mailbox #(spi_transaction) gen2drv;
    mailbox #(spi_transaction) drv2scb;
    mailbox #(spi_transaction) mon2scb;
    event drv_done;
    
    virtual spi_if vif;
    
    function new(virtual spi_if vif);
        this.vif = vif;
        gen2drv = new();
        drv2scb = new();
        mon2scb = new();
        
        gen = new(gen2drv, drv_done);
        drv = new(vif, gen2drv, drv2scb, drv_done);
        mon = new(vif, mon2scb);
        scb = new(drv2scb, mon2scb);
    endfunction
    
    task run();
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_any
    endtask
    
    task report();
        scb.report();
    endtask
endclass

//=============================================================================
// Interface - Connects testbench to DUT
//=============================================================================
interface spi_if(input logic clk);
    logic rst_n;
    logic [7:0] data_m_in;
    logic [7:0] data_s_in;
    logic start_m;
    logic finish_m;
    logic [7:0] data_m_out;
    logic [7:0] data_s_out;
    logic data_valid_s;
    
    // Internal signals for assertions
    logic sclk, cs_n, mosi, miso;
endinterface

//=============================================================================
// Test Program
//=============================================================================
program test(spi_if intf);
    environment env;
    
    initial begin
        env = new(intf);
        env.gen.num_transactions = 20; // Run 20 transactions
        
        // Reset sequence
        intf.rst_n = 0;
        intf.start_m = 0;
        intf.data_m_in = 0;
        intf.data_s_in = 0;
        repeat(5) @(posedge intf.clk);
        intf.rst_n = 1;
        repeat(2) @(posedge intf.clk);
        
        // Run test
        env.run();
        
        // Wait for completion
        repeat(1000) @(posedge intf.clk);
        
        // Report results
        env.report();
        $finish;
    end
endprogram

//=============================================================================
// Top-level Testbench with Assertions
//=============================================================================
module tb_spi_loopback;
    parameter CLK_PERIOD = 20; // 50MHz clock
    parameter CLK_FREQUENCE = 50_000_000;
    parameter SPI_FREQUENCE = 5_000_000;
    parameter DATA_WIDTH = 8;
    parameter CPOL = 0;
    parameter CPHA = 0;
    
    logic clk;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Interface instantiation
    spi_if intf(clk);
    
    // DUT instantiation
    SPI_loopback #(
        .CLK_FREQUENCE(CLK_FREQUENCE),
        .SPI_FREQUENCE(SPI_FREQUENCE),
        .DATA_WIDTH(DATA_WIDTH),
        .CPOL(CPOL),
        .CPHA(CPHA)
    ) dut (
        .clk(intf.clk),
        .rst_n(intf.rst_n),
        .data_m_in(intf.data_m_in),
        .data_s_in(intf.data_s_in),
        .start_m(intf.start_m),
        .finish_m(intf.finish_m),
        .data_m_out(intf.data_m_out),
        .data_s_out(intf.data_s_out),
        .data_valid_s(intf.data_valid_s)
    );
    
    // Connect internal signals for assertions
    assign intf.sclk = dut.sclk;
    assign intf.cs_n = dut.cs_n;
    assign intf.mosi = dut.mosi;
    assign intf.miso = dut.miso;
    
    // Test program instantiation
    test t1(intf);
    
    //=========================================================================
    // ASSERTIONS
    //========================================================================
    
    // A1: CS_N should be high when idle
    property cs_idle;
        @(posedge clk) disable iff(!intf.rst_n)
        (!intf.start_m && intf.finish_m) |=> intf.cs_n;
    endproperty
    assert property(cs_idle) else $error("CS not high when idle");
    
    // A2: CS_N should go low after start
    property cs_active;
        @(posedge clk) disable iff(!intf.rst_n)
        intf.start_m |=> ##[1:5] !intf.cs_n;
    endproperty
    assert property(cs_active) else $error("CS did not go low after start");
    
    // A3: Finish pulse should occur
    property finish_pulse;
        @(posedge clk) disable iff(!intf.rst_n)
        $rose(intf.finish_m) |=> !intf.finish_m;
    endproperty
    assert property(finish_pulse) else $error("Finish is not a single pulse");
    
    // A4: Data valid should be asserted with finish
    property data_valid_with_finish;
        @(posedge clk) disable iff(!intf.rst_n)
        intf.finish_m |-> intf.data_valid_s;
    endproperty
    assert property(data_valid_with_finish) else $error("Data valid not asserted with finish");
    
    // A5: SCLK should be stable when CS is high
    property sclk_stable_when_idle;
        @(posedge clk) disable iff(!intf.rst_n)
        intf.cs_n |-> $stable(intf.sclk);
    endproperty
    assert property(sclk_stable_when_idle) else $error("SCLK toggling when idle");
    
    // A6: No start pulse during active transmission
    property no_start_during_transmission;
        @(posedge clk) disable iff(!intf.rst_n)
        (!intf.cs_n && !intf.finish_m) |-> !intf.start_m;
    endproperty
    assert property(no_start_during_transmission) 
        else $error("Start pulse during active transmission");
    
    // A7: Reset behavior - CS should be high after reset
    property reset_cs_high;
        @(posedge clk)
        !intf.rst_n |=> intf.cs_n;
    endproperty
    assert property(reset_cs_high) else $error("CS not high after reset");
    
    // Coverage
    covergroup spi_cg @(posedge clk);
      option.per_instance = 1;
    option.name = "spi_loopback_cg";
        data_m: coverpoint intf.data_m_in {
            bins zero = {0};
            bins low = {[1:63]};
            bins mid = {[64:191]};
            bins high = {[192:254]};
            bins max = {255};
        }
        data_s: coverpoint intf.data_s_in {
            bins zero = {0};
            bins low = {[1:63]};
            bins mid = {[64:191]};
            bins high = {[192:254]};
            bins max = {255};
        }
        cs_state: coverpoint intf.cs_n {
            bins active = {0};
            bins idle = {1};
        }
    endgroup
    
    spi_cg cg = new();
    
    // Waveform dump
    initial begin
        $dumpfile("spi_loopback.vcd");
        $dumpvars(0, tb_spi_loopback);
    end
    // =====================================================
// SAVE COVERAGE + PRINT SUMMARY
// =====================================================
initial $set_coverage_db_name("spi_cov.ucis");
final begin
    real fcov;                 // declare
    fcov = $get_coverage();    // then assign
    $display("\n==== COVERAGE SUMMARY ====");
    $display("Functional Coverage = %0.2f%%", fcov);
    $display("==========================\n");
end


endmodule