`timescale 1ns/1ps

//=====================================================================
// Testbench for axi4_lite write channel
// Scenarios:
//   1) Normal operation      - address & data valid together, no stall
//   2) Data first            - data arrives, address arrives later
//   3) Address first         - address arrives, data arrives later
//   4) Address & data together, with a stall before write_resp_ready
//=====================================================================

module axi4_lite_write_tb;

    parameter DATA_WIDTH = 32;
    parameter ADD_WIDTH  = 4;
    parameter ADD_NUM    = 16;
    parameter CLK_PERIOD = 10;

    reg                        clk;
    reg                        rst;

    reg  [ADD_WIDTH-1:0]       write_add;
    reg                        write_add_valid;
    wire                       write_add_ready;

    reg  [DATA_WIDTH-1:0]      write_data;
    reg                        write_data_valid;
    wire                       write_data_ready;

    wire                       write_resp;
    wire                       write_resp_valid;
    reg                        write_resp_ready;

    integer errors   = 0;
    integer test_num = 0;

    //-----------------------------------------------------------------
    // DUT
    //-----------------------------------------------------------------
    axi4_lite_write #(
        .data_width (DATA_WIDTH),
        .add_width  (ADD_WIDTH),
        .add_num    (ADD_NUM)
    ) dut (
        .clk              (clk),
        .rst              (rst),
        .write_add        (write_add),
        .write_add_valid  (write_add_valid),
        .write_add_ready  (write_add_ready),
        .write_data       (write_data),
        .write_data_valid (write_data_valid),
        .write_data_ready (write_data_ready),
        .write_resp       (write_resp),
        .write_resp_valid (write_resp_valid),
        .write_resp_ready (write_resp_ready)
    );

    //-----------------------------------------------------------------
    // Clock
    //-----------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //-----------------------------------------------------------------
    // Watchdog - kills the sim instead of hanging forever on a stuck FSM
    //-----------------------------------------------------------------
    initial begin
        #(CLK_PERIOD * 2000);
        $display("[FAIL] Watchdog timeout - simulation hung at time %0t", $time);
        errors = errors + 1;
        $finish;
    end

    //-----------------------------------------------------------------
    // Address channel driver
    // Waits wait_cycles clock edges before asserting write_add_valid,
    // holds valid until write_add_ready is sampled high, then drops it.
    //-----------------------------------------------------------------
    task automatic write_addr_ch(input [ADD_WIDTH-1:0] addr, input integer wait_cycles);
        integer i;
        begin
            for (i = 0; i < wait_cycles; i = i + 1) @(posedge clk);
            @(negedge clk);
            write_add       = addr;
            write_add_valid = 1;
            @(posedge clk);
            while (!write_add_ready) @(posedge clk);
            @(negedge clk);
            write_add_valid = 0;
        end
    endtask

    //-----------------------------------------------------------------
    // Data channel driver - same shape as the address driver
    //-----------------------------------------------------------------
    task automatic write_data_ch(input [DATA_WIDTH-1:0] data, input integer wait_cycles);
        integer i;
        begin
            for (i = 0; i < wait_cycles; i = i + 1) @(posedge clk);
            @(negedge clk);
            write_data       = data;
            write_data_valid = 1;
            @(posedge clk);
            while (!write_data_ready) @(posedge clk);
            @(negedge clk);
            write_data_valid = 0;
        end
    endtask

    //-----------------------------------------------------------------
    // Response channel driver
    // Waits for write_resp_valid to go high, then stalls stall_cycles
    // clock edges before asserting write_resp_ready for one cycle.
    //-----------------------------------------------------------------
    task automatic accept_response(input integer stall_cycles);
        integer i;
        begin
            // Guard against a stale write_resp_valid left over from the
            // previous transaction (it can take one extra cycle to drop
            // after the FSM shows idle) - wait it out before waiting for
            // the real, fresh assertion.
            while (write_resp_valid) @(posedge clk);
            while (!write_resp_valid) @(posedge clk);
            for (i = 0; i < stall_cycles; i = i + 1) @(posedge clk);
            @(negedge clk);
            write_resp_ready = 1;
            @(posedge clk);
            @(negedge clk);
            write_resp_ready = 0;
        end
    endtask

    //-----------------------------------------------------------------
    // Scoreboard check - reads the DUT memory hierarchically
    //-----------------------------------------------------------------
    task automatic check_memory(input [ADD_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] expected);
        begin
            if (dut.memory[addr] !== expected) begin
                errors = errors + 1;
                $display("[FAIL] Test %0d: memory[%0d] = %h, expected %h at time %0t",
                          test_num, addr, dut.memory[addr], expected, $time);
            end else begin
                $display("[PASS] Test %0d: memory[%0d] = %h as expected",
                          test_num, addr, dut.memory[addr]);
            end
        end
    endtask

    // Confirms the FSM actually returned to idle and both readies are
    // back up before the next test starts driving new transfers.
    task automatic check_idle_and_ready;
        begin
            if (dut.current_state !== 2'b00) begin
                errors = errors + 1;
                $display("[FAIL] Test %0d: FSM not back in idle (state=%b) at time %0t",
                          test_num, dut.current_state, $time);
            end
            if (!write_add_ready || !write_data_ready) begin
                errors = errors + 1;
                $display("[FAIL] Test %0d: readies not both high after transaction at time %0t",
                          test_num, $time);
            end
            if (write_resp_valid) begin
                errors = errors + 1;
                $display("[FAIL] Test %0d: write_resp_valid still asserted after transaction at time %0t",
                          test_num, $time);
            end
        end
    endtask

    //-----------------------------------------------------------------
    // Stimulus
    //-----------------------------------------------------------------
    initial begin
        // $dumpfile("axi4_lite_write_tb.vcd");
        // $dumpvars(0, axi4_lite_write_tb);

        write_add        = 0;
        write_add_valid  = 0;
        write_data       = 0;
        write_data_valid = 0;
        write_resp_ready = 0;

        rst = 0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1;

        //---------------------------------------------------------
        // Test 1: normal operation - address & data together, no stall
        //---------------------------------------------------------
        test_num = 1;
        fork
            write_addr_ch(4'h3, 0);
            write_data_ch(32'hAAAA_5555, 0);
            accept_response(0);
        join
        check_memory(4'h3, 32'hAAAA_5555);
        repeat (2) @(posedge clk);
        check_idle_and_ready;

        //---------------------------------------------------------
        // Test 2: data first, address arrives 3 cycles later
        //---------------------------------------------------------
        test_num = 2;
        fork
            write_addr_ch(4'h7, 3);
            write_data_ch(32'h1234_5678, 0);
            accept_response(0);
        join
        check_memory(4'h7, 32'h1234_5678);
        repeat (2) @(posedge clk);
        check_idle_and_ready;

        //---------------------------------------------------------
        // Test 3: address first, data arrives 3 cycles later
        //---------------------------------------------------------
        test_num = 3;
        fork
            write_addr_ch(4'hA, 0);
            write_data_ch(32'hDEAD_BEEF, 3);
            accept_response(0);
        join
        check_memory(4'hA, 32'hDEAD_BEEF);
        repeat (2) @(posedge clk);
        check_idle_and_ready;

        //---------------------------------------------------------
        // Test 4: address & data together, response stalled 4 cycles
        //---------------------------------------------------------
        test_num = 4;
        fork
            write_addr_ch(4'h1, 0);
            write_data_ch(32'hCAFE_BABE, 0);
            accept_response(4);
        join
        check_memory(4'h1, 32'hCAFE_BABE);
        repeat (2) @(posedge clk);
        check_idle_and_ready;

        //---------------------------------------------------------
        // Summary
        //---------------------------------------------------------
        repeat (2) @(posedge clk);
        if (errors == 0)
            $display("\n===== ALL TESTS PASSED =====");
        else
            $display("\n===== %0d ERROR(S) FOUND =====", errors);

        $finish;
    end

endmodule