`timescale 1ns/1ps

module tb_axi4_read_lite;

    parameter DATA_WIDTH = 32;
    parameter ADD_WIDTH  = 4;
    parameter ADD_NUM    = 16;

    // =====================================================
    // Clock and Reset
    // =====================================================

    reg clk;
    reg rst;


    // =====================================================
    // Read Address Channel
    // =====================================================

    reg  [ADD_WIDTH-1:0] read_add;
    reg                  read_add_valid;
    wire                 read_add_ready;


    // =====================================================
    // Read Data Channel
    // =====================================================

    wire [DATA_WIDTH-1:0] read_data;
    wire                  read_data_valid;

    // Keep RRESP 1 bit for now
    wire                  read_data_resp;

    reg                   read_data_ready;


    // =====================================================
    // Write Channels
    // Not used yet
    // =====================================================

    reg  [ADD_WIDTH-1:0]  write_add;
    reg                   write_add_valid;
    wire                  write_add_ready;

    reg  [DATA_WIDTH-1:0] write_data;
    reg                   write_data_valid;
    wire                  write_data_ready;

    wire                  write_resp;
    wire                  write_resp_valid;
    reg                   write_resp_ready;


    // =====================================================
    // DUT
    // =====================================================

    axi4_lite_read #(
        .data_width(DATA_WIDTH),
        .add_width (ADD_WIDTH),
        .add_num   (ADD_NUM)
    ) dut (
        .clk(clk),
        .rst(rst),

        // Read Address Channel
        .read_add(read_add),
        .read_add_valid(read_add_valid),
        .read_add_ready(read_add_ready),

        // Read Data Channel
        .read_data(read_data),
        .read_data_valid(read_data_valid),
        .read_data_resp(read_data_resp),
        .read_data_ready(read_data_ready),

        // Write Address Channel
        .write_add(write_add),
        .write_add_valid(write_add_valid),
        .write_add_ready(write_add_ready),

        // Write Data Channel
        .write_data(write_data),
        .write_data_valid(write_data_valid),
        .write_data_ready(write_data_ready),

        // Write Response Channel
        .write_resp(write_resp),
        .write_resp_valid(write_resp_valid),
        .write_resp_ready(write_resp_ready)
    );


    // =====================================================
    // Clock Generation
    // =====================================================

    initial begin
        clk = 0;

        forever #5 clk = ~clk;
    end


    // =====================================================
    // Test
    // =====================================================

    initial begin

        // =================================================
        // Initial Values
        // =================================================

        rst = 0;

        read_add        = 0;
        read_add_valid  = 0;
        read_data_ready = 0;

        write_add        = 0;
        write_add_valid  = 0;

        write_data       = 0;
        write_data_valid = 0;

        write_resp_ready = 0;


        // =================================================
        // Initialize Memory
        // =================================================

        dut.memory[1] = 32'h11111111;
        dut.memory[2] = 32'h22222222;


        // =================================================
        // Reset
        // =================================================

        repeat (2) @(posedge clk);

        rst = 1;

        @(posedge clk);


        // =================================================
        // TRANSACTION 1
        //
        // Normal read of address 1
        // =================================================

        $display("");
        $display("==========================================");
        $display("       TRANSACTION 1 - NORMAL READ");
        $display("==========================================");


        // Drive address and VALID
        read_add       = 1;
        read_add_valid = 1;


        // -------------------------------------------------
        // Wait for address handshake
        // -------------------------------------------------
        @(posedge clk);
        while (!(read_add_valid && read_add_ready))
            @(posedge clk);


        $display(
            "T1: Address handshake PASS  ADDR=%h",
            read_add
        );


        // Address has been accepted
        read_add_valid = 0;


        // -------------------------------------------------
        // Wait for RVALID
        // -------------------------------------------------

        wait(read_data_valid == 1);


        $display(
            "T1: RVALID=%b RDATA=%h RRESP=%b",
            read_data_valid,
            read_data,
            read_data_resp
        );


        // -------------------------------------------------
        // Check data
        // -------------------------------------------------

        if (read_data == 32'h11111111)
            $display("T1: DATA PASS");
        else
            $display("T1: DATA FAIL");

        if (read_data_resp == 1'b1)
            $display("T1: RESP PASS");
        else
            $display("T1: RESP FAIL");


        // -------------------------------------------------
        // Accept the read data
        // -------------------------------------------------
        #25 
        
        read_data_ready = 1;

        @(posedge clk);
        // Wait for RVALID && RREADY
        while (!(read_data_valid && read_data_ready))
            @(posedge clk);


        $display("T1: Data handshake PASS");


        // Remove READY
        read_data_ready = 0;


        // Give DUT time to return to IDLE
        @(posedge clk);


        // =================================================
        // TRANSACTION 2
        //
        // Test read_add_reg
        // =================================================

        $display("");
        $display("==========================================");
        $display("   TRANSACTION 2 - ADDRESS REGISTER TEST");
        $display("==========================================");


        // -------------------------------------------------
        // Wait until slave is ready
        // -------------------------------------------------

        while (!read_add_ready)
            @(posedge clk);


        // -------------------------------------------------
        // Send address 1
        // -------------------------------------------------

        read_add       = 1;
        read_add_valid = 1;


        // -------------------------------------------------
        // Wait for address handshake
        // -------------------------------------------------
        @(posedge clk);
        while (!(read_add_valid && read_add_ready))
            @(posedge clk);


        $display(
            "T2: Address handshake PASS  ADDR=%h",
            read_add
        );


        // Address has been accepted
        read_add_valid = 0;


        // -------------------------------------------------
        // IMPORTANT:
        //
        // Change the address AFTER the handshake.
        //
        // DUT should still use address 1 because
        // it should have stored address 1 in read_add_reg.
        // -------------------------------------------------

        read_add = 2;


        $display(
            "T2: Changed input address to %h after handshake",
            read_add
        );


        // -------------------------------------------------
        // Wait for read data
        // -------------------------------------------------

        wait(read_data_valid == 1);


        $display(
            "T2: RVALID=%b RDATA=%h RRESP=%b",
            read_data_valid,
            read_data,
            read_data_resp
        );


        // -------------------------------------------------
        // Check address register
        //
        // Expected:
        // memory[1] = 11111111
        //
        // NOT:
        // memory[2] = 22222222
        // -------------------------------------------------

        if (read_data == 32'h11111111)

            $display(
                "T2: ADDRESS REGISTER PASS"
            );

        else

            $display(
                "T2: ADDRESS REGISTER FAIL"
            );

            if (read_data_resp == 1'b1)
                $display("T2: RESP PASS");
            else
                $display("T2: RESP FAIL");


        // =================================================
        // TRANSACTION 2 BACK-PRESSURE TEST
        // =================================================

        $display("");
        $display("==========================================");
        $display("       T2 - BACK-PRESSURE TEST");
        $display("==========================================");


        // Master refuses to accept the data
        read_data_ready = 0;


        // -------------------------------------------------
        // Keep RREADY LOW for 5 cycles
        //
        // RVALID and RDATA must remain stable.
        // -------------------------------------------------

        repeat (5) begin

            @(posedge clk);

            if (read_data_valid &&
                read_data == 32'h11111111)

                $display(
                    "Back-pressure PASS: RVALID=%b RDATA=%h",
                    read_data_valid,
                    read_data
                );

            else

                $display(
                    "Back-pressure FAIL: RVALID=%b RDATA=%h",
                    read_data_valid,
                    read_data
                );

        end


        // =================================================
        // Accept Transaction 2 Data
        // =================================================

        $display("");
        $display("Accepting Transaction 2 data");


        read_data_ready = 1;

        @(posedge clk);
        // Wait for actual data handshake
        while (!(read_data_valid && read_data_ready))
            @(posedge clk);


        $display(
            "T2: Data handshake PASS"
        );


        // Remove READY
        read_data_ready = 0;


        // -------------------------------------------------
        // Wait for DUT to return to IDLE
        // -------------------------------------------------

        @(posedge clk);


        // -------------------------------------------------
        // Check transaction completed
        // -------------------------------------------------

        if ((read_data_valid == 0) &&
            (read_add_ready == 1))

            $display(
                "T2: Transaction completed successfully"
            );

        else

            $display(
                "T2: Transaction did NOT complete correctly"
            );


        // =================================================
        // Final
        // =================================================

        #20;

        $display("");
        $display("==========================================");
        $display("          SIMULATION FINISHED");
        $display("==========================================");

        $stop;

    end

endmodule
/*

### What this TB tests

It now tests the important behavior you've implemented:

Transaction 1 — normal operation

ARVALID = 1
ARREADY = 1
     ↓
address accepted
     ↓
RVALID = 1
RDATA = 11111111
     ↓
RREADY = 1
     ↓
read complete


Transaction 2 — read_add_reg

It sends:


ARADDR = 1

then after the handshake changes the input to:


ARADDR = 2


The DUT must still return:


RDATA = memory[1] = 11111111


This specifically proves that your:

verilog
if (read_add_valid && read_add_ready)
    read_add_reg <= read_add;


is working.

Back-pressure test

It then keeps:

verilog
read_data_ready = 0;


for 5 cycles and checks that:


RVALID = 1
RDATA  = 11111111


stay stable.

*/