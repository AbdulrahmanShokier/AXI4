`timescale 1ns/1ps
//=============================================================================
// Testbench: tb_axi4_lite
// Exercises the top-level axi4_lite_slave (write channel + read channel +
// one shared memory), driving each handshake (VALID/READY) and self-checking
// data, responses and timing.
//
// Notes on the DUT:
//  - "rst" is ACTIVE-LOW (state resets while rst == 0, runs while rst == 1).
//  - Both channels now share ONE memory array inside axi4_lite_slave, so a
//    write made through the write channel is directly observable through
//    the read channel (see the "shared memory" test section below), and
//    the testbench can preload/peek that single array via dut.memory[].
//=============================================================================
module tb_axi4_lite;

    //-------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------
    localparam DATA_WIDTH = 32;
    localparam ADD_WIDTH  = 4;
    localparam ADD_NUM    = 16;
    localparam CLK_PERIOD = 10;

    //-------------------------------------------------------------------
    // WRITE channel signals
    //-------------------------------------------------------------------
    reg                    clk;
    reg                    rst;

    reg  [ADD_WIDTH-1:0]   write_add;
    reg                    write_add_valid;
    wire                   write_add_ready;

    reg  [DATA_WIDTH-1:0]  write_data;
    reg                    write_data_valid;
    wire                   write_data_ready;

    wire                   write_resp;
    wire                   write_resp_valid;
    reg                    write_resp_ready;

    //-------------------------------------------------------------------
    // READ channel signals
    //-------------------------------------------------------------------
    reg  [ADD_WIDTH-1:0]   read_add;
    reg                    read_add_valid;
    wire                   read_add_ready;

    wire [DATA_WIDTH-1:0]  read_data;
    wire                   read_data_valid;
    wire                   read_data_resp;
    reg                    read_data_ready;

    //-------------------------------------------------------------------
    // Bookkeeping
    //-------------------------------------------------------------------
    integer errors;
    integer checks;
    integer i;
    reg [DATA_WIDTH-1:0] rand_data;

    //-------------------------------------------------------------------
    // DUT instantiation (single top-level slave, shared memory inside)
    //-------------------------------------------------------------------
    axi4_lite_slave #(
        .data_width (DATA_WIDTH),
        .add_width  (ADD_WIDTH),
        .add_num    (ADD_NUM)
    ) dut (
        .clk               (clk),
        .rst               (rst),

        .write_add         (write_add),
        .write_add_valid   (write_add_valid),
        .write_add_ready   (write_add_ready),
        .write_data        (write_data),
        .write_data_valid  (write_data_valid),
        .write_data_ready  (write_data_ready),
        .write_resp        (write_resp),
        .write_resp_valid  (write_resp_valid),
        .write_resp_ready  (write_resp_ready),

        .read_add          (read_add),
        .read_add_valid    (read_add_valid),
        .read_add_ready    (read_add_ready),
        .read_data         (read_data),
        .read_data_valid   (read_data_valid),
        .read_data_resp    (read_data_resp),
        .read_data_ready   (read_data_ready)
    );

    //-------------------------------------------------------------------
    // Clock
    //-------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //-------------------------------------------------------------------
    // Waveform dump (optional, view with gtkwave)
    //-------------------------------------------------------------------
    initial begin
        $dumpfile("axi4_lite_tb.vcd");
        $dumpvars(0, tb_axi4_lite);
    end

    //-------------------------------------------------------------------
    // Reset task (rst is active-LOW)
    //-------------------------------------------------------------------
    task apply_reset;
        begin
            rst              = 1'b0;
            write_add        = 0;
            write_add_valid  = 1'b0;
            write_data       = 0;
            write_data_valid = 1'b0;
            write_resp_ready = 1'b0;
            read_add         = 0;
            read_add_valid   = 1'b0;
            read_data_ready  = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b1;
            @(posedge clk);
        end
    endtask

    //-------------------------------------------------------------------
    // WRITE transaction: drives ADDR+DATA, waits for BRESP, checks memory
    //-------------------------------------------------------------------
    task write_transaction;
        input [ADD_WIDTH-1:0]  addr;
        input [DATA_WIDTH-1:0] data;
        begin
            wait (write_add_ready && write_data_ready);
            @(negedge clk);
            write_add        = addr;
            write_add_valid  = 1'b1;
            write_data       = data;
            write_data_valid = 1'b1;
            write_resp_ready = 1'b1;

            @(posedge clk);   // address & data captured here

            @(negedge clk);
            write_add_valid  = 1'b0;
            write_data_valid = 1'b0;

            wait (write_resp_valid);
            checks = checks + 1;
            if (write_resp !== 1'b1) begin
                errors = errors + 1;
                $display("[%0t] ERROR write addr=%0d : expected OKAY resp, got %0b",
                          $time, addr, write_resp);
            end

            @(posedge clk);
            @(negedge clk);
            write_resp_ready = 1'b0;

            wait (write_add_ready && write_data_ready);

            // Hierarchical peek to confirm the shared memory actually updated
            if (dut.memory[addr] !== data) begin
                errors = errors + 1;
                $display("[%0t] ERROR write addr=%0d : memory=%0h expected=%0h",
                          $time, addr, dut.memory[addr], data);
            end else begin
                $display("[%0t] PASS  write addr=%0d data=%0h", $time, addr, data);
            end
        end
    endtask

    //-------------------------------------------------------------------
    // READ transaction: drives ADDR, waits for RVALID, checks data & resp
    //-------------------------------------------------------------------
    task read_transaction;
        input [ADD_WIDTH-1:0]  addr;
        input [DATA_WIDTH-1:0] expected;
        begin
            wait (read_add_ready);
            @(negedge clk);
            read_add       = addr;
            read_add_valid = 1'b1;

            @(posedge clk);   // address captured here

            @(negedge clk);
            read_add_valid  = 1'b0;
            read_data_ready = 1'b1;

            wait (read_data_valid);
            checks = checks + 1;
            if (read_data !== expected) begin
                errors = errors + 1;
                $display("[%0t] ERROR read  addr=%0d : data=%0h expected=%0h",
                          $time, addr, read_data, expected);
            end else if (read_data_resp !== 1'b1) begin
                errors = errors + 1;
                $display("[%0t] ERROR read  addr=%0d : resp=%0b expected=1",
                          $time, addr, read_data_resp);
            end else begin
                $display("[%0t] PASS  read  addr=%0d data=%0h", $time, addr, read_data);
            end

            @(posedge clk);
            @(negedge clk);
            read_data_ready = 1'b0;
            wait (read_add_ready);
        end
    endtask

    //-------------------------------------------------------------------
    // WRITE transaction with back-pressure: withholds write_resp_ready for
    // `delay_cycles` clocks after the slave asserts write_resp_valid, and
    // checks that write_resp_valid / write_resp stay steady (do not drop
    // or change) while READY is withheld -- i.e. the slave isn't allowed
    // to silently retract or corrupt VALID data before the master accepts it.
    //-------------------------------------------------------------------
    task write_transaction_bp;
        input [ADD_WIDTH-1:0]  addr;
        input [DATA_WIDTH-1:0] data;
        input [7:0]            delay_cycles;
        integer j;
        begin
            wait (write_add_ready && write_data_ready);
            @(negedge clk);
            write_add        = addr;
            write_add_valid  = 1'b1;
            write_data       = data;
            write_data_valid = 1'b1;
            write_resp_ready = 1'b0;   // withhold READY on the response channel

            @(posedge clk);   // address & data captured here

            @(negedge clk);
            write_add_valid  = 1'b0;
            write_data_valid = 1'b0;

            wait (write_resp_valid);   // slave has asserted VALID

            for (j = 0; j < delay_cycles; j = j + 1) begin
                @(posedge clk);
                checks = checks + 1;
                if (write_resp_valid !== 1'b1) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR write(bp) addr=%0d : write_resp_valid dropped while READY was low (cycle %0d)",
                              $time, addr, j);
                end else if (write_resp !== 1'b1) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR write(bp) addr=%0d : write_resp changed while READY was low (cycle %0d)",
                              $time, addr, j);
                end
            end

            @(negedge clk);
            write_resp_ready = 1'b1;

            @(posedge clk);
            @(negedge clk);
            write_resp_ready = 1'b0;

            wait (write_add_ready && write_data_ready);

            checks = checks + 1;
            if (dut.memory[addr] !== data) begin
                errors = errors + 1;
                $display("[%0t] ERROR write(bp) addr=%0d : memory=%0h expected=%0h",
                          $time, addr, dut.memory[addr], data);
            end else begin
                $display("[%0t] PASS  write(bp) addr=%0d data=%0h (held READY low %0d cycles)",
                          $time, addr, data, delay_cycles);
            end
        end
    endtask

    //-------------------------------------------------------------------
    // READ transaction with back-pressure: withholds read_data_ready for
    // `delay_cycles` clocks after the slave asserts read_data_valid, and
    // checks that read_data_valid / read_data / read_data_resp stay steady
    // while READY is withheld.
    //-------------------------------------------------------------------
    task read_transaction_bp;
        input [ADD_WIDTH-1:0]  addr;
        input [DATA_WIDTH-1:0] expected;
        input [7:0]            delay_cycles;
        integer j;
        begin
            wait (read_add_ready);
            @(negedge clk);
            read_add        = addr;
            read_add_valid  = 1'b1;
            read_data_ready = 1'b0;   // withhold READY on the read-data channel

            @(posedge clk);   // address captured here

            @(negedge clk);
            read_add_valid = 1'b0;

            wait (read_data_valid);   // slave has asserted VALID

            for (j = 0; j < delay_cycles; j = j + 1) begin
                @(posedge clk);
                checks = checks + 1;
                if (read_data_valid !== 1'b1) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR read(bp)  addr=%0d : read_data_valid dropped while READY was low (cycle %0d)",
                              $time, addr, j);
                end else if (read_data !== expected) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR read(bp)  addr=%0d : data changed to %0h (expected %0h) while READY was low (cycle %0d)",
                              $time, addr, read_data, expected, j);
                end
            end

            checks = checks + 1;
            if (read_data !== expected) begin
                errors = errors + 1;
                $display("[%0t] ERROR read(bp)  addr=%0d : data=%0h expected=%0h",
                          $time, addr, read_data, expected);
            end else if (read_data_resp !== 1'b1) begin
                errors = errors + 1;
                $display("[%0t] ERROR read(bp)  addr=%0d : resp=%0b expected=1",
                          $time, addr, read_data_resp);
            end else begin
                $display("[%0t] PASS  read(bp)  addr=%0d data=%0h (held READY low %0d cycles)",
                          $time, addr, read_data, delay_cycles);
            end

            @(negedge clk);
            read_data_ready = 1'b1;

            @(posedge clk);
            @(negedge clk);
            read_data_ready = 1'b0;
            wait (read_add_ready);
        end
    endtask

    //-------------------------------------------------------------------
    // Stimulus
    //-------------------------------------------------------------------
    initial begin
        errors = 0;
        checks = 0;

        // Preload the shared memory directly (hierarchical poke) so the
        // read-only directed tests below have known values to check against
        for (i = 0; i < ADD_NUM; i = i + 1)
            dut.memory[i] = 32'hA000_0000 + i;

        apply_reset;

        $display("\n===== Directed WRITE tests =====");
        write_transaction(4'd0,  32'hAAAA_0000);
        write_transaction(4'd5,  32'hBEEF_0001);
        write_transaction(4'd15, 32'hDEAD_BEEF);
        write_transaction(4'd1,  32'h1234_5678);

        $display("\n===== Directed READ tests =====");
        read_transaction(4'd0,  32'hAAAA_0000); // overwritten by the write test above
        read_transaction(4'd5,  32'hBEEF_0001); // overwritten by the write test above
        read_transaction(4'd15, 32'hDEAD_BEEF); // overwritten by the write test above
        read_transaction(4'd3,  32'hA000_0003); // untouched, still the preloaded value
        read_transaction(4'd3,  32'hA000_0003); // re-read same address

        $display("\n===== Shared-memory tests: write on one channel, read on the other =====");
        write_transaction(4'd9,  32'hFEED_FACE);
        read_transaction (4'd9,  32'hFEED_FACE);   // must see the write channel's data
        write_transaction(4'd2,  32'h0BAD_CAFE);
        read_transaction (4'd2,  32'h0BAD_CAFE);
        // interleave: write addr 6, then immediately write addr 6 again with
        // a new value, then confirm the read channel sees the LATEST value
        write_transaction(4'd6,  32'h1111_1111);
        write_transaction(4'd6,  32'h2222_2222);
        read_transaction (4'd6,  32'h2222_2222);

        $display("\n===== Back-pressure tests (master withholds READY) =====");
        // Master delays asserting write_resp_ready for a few cycles after
        // the slave raises write_resp_valid -- the slave must hold VALID
        // and the response value steady until READY finally arrives.
        write_transaction_bp(4'd4,  32'hB0BA_1234, 8'd3);
        read_transaction_bp (4'd4,  32'hB0BA_1234, 8'd3);
        write_transaction_bp(4'd11, 32'h5555_AAAA, 8'd6);
        read_transaction_bp (4'd11, 32'h5555_AAAA, 8'd6);
        // Zero-delay case should behave exactly like the plain tasks
        write_transaction_bp(4'd8,  32'h0000_DEAD, 8'd0);
        read_transaction_bp (4'd8,  32'h0000_DEAD, 8'd0);

        $display("\n===== Randomized WRITE tests (8 addresses) =====");
        for (i = 0; i < 8; i = i + 1) begin
            rand_data = $random;
            write_transaction(i[ADD_WIDTH-1:0], rand_data);
        end

        $display("\n===== Randomized READ-back tests (same 8 addresses, other channel) =====");
        // Re-uses the values just written above and reads them back through
        // the read channel, proving the shared memory holds under repeated
        // random writes and not just the directed cases.
        for (i = 0; i < 8; i = i + 1)
            read_transaction(i[ADD_WIDTH-1:0], dut.memory[i]);

        $display("\n===== Randomized READ tests (all 16 addresses, freshly preloaded) =====");
        for (i = 0; i < ADD_NUM; i = i + 1)
            dut.memory[i] = $random;
        for (i = 0; i < ADD_NUM; i = i + 1)
            read_transaction(i[ADD_WIDTH-1:0], dut.memory[i]);

        $display("\n===== Reset-during-transaction recovery test =====");
        @(negedge clk);
        read_add       = 4'd2;
        read_add_valid = 1'b1;
        @(posedge clk);          // address gets captured mid-flight
        apply_reset;             // yank reset in the middle of the transfer
        read_transaction(4'd2, dut.memory[2]);  // must recover cleanly

        //---------------------------------------------------------------
        $display("\n=================================================");
        if (errors == 0)
            $display("ALL %0d CHECKS PASSED", checks);
        else
            $display("%0d OF %0d CHECKS FAILED", errors, checks);
        $display("=================================================\n");

        #(CLK_PERIOD*4);
        $finish;
    end

    //-------------------------------------------------------------------
    // Safety timeout, in case a handshake never completes
    //-------------------------------------------------------------------
    initial begin
        #100000;
        $display("ERROR: TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule