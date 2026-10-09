`timescale 1ns/1ps

// ==========================================================================
// System-level testbench: axi4_lite_master + axi4_lite_slave connected
// back-to-back over the full AXI4-Lite protocol. The testbench drives ONLY
// the master's simple control interface (start_write_out / start_read_out)
// -- it never touches the AXI channels directly -- so this exercises the
// complete master <-> slave handshake, the shared memory, and both state
// machines together.
// ==========================================================================

module tb_axi4_lite_system;

    parameter DATA_WIDTH = 32;
    parameter ADD_WIDTH  = 4;
    parameter ADD_NUM    = 16;
    parameter CLK_PERIOD = 10;
    parameter TIMEOUT_CYCLES = 100;

    reg  clk;
    reg  rst;

    // ---- Control interface (testbench <-> master) ----
    reg                       start_write_out;
    reg  [ADD_WIDTH-1:0]      write_add_out;
    reg  [DATA_WIDTH-1:0]     write_data_out;
    wire                      write_done_out;

    reg                       start_read_out;
    reg  [ADD_WIDTH-1:0]      read_add_out;
    wire [DATA_WIDTH-1:0]     read_data_out;
    wire                      read_done_out;

    // ---- Master <-> slave AXI4-Lite channels (internal wiring only) ----
    wire [ADD_WIDTH-1:0]      read_add;
    wire                      read_add_valid;
    wire                      read_add_ready;

    wire [DATA_WIDTH-1:0]     read_data;
    wire                      read_data_valid;
    wire                      read_data_resp;
    wire                      read_data_ready;

    wire [ADD_WIDTH-1:0]      write_add;
    wire                      write_add_valid;
    wire                      write_add_ready;

    wire [DATA_WIDTH-1:0]     write_data;
    wire                      write_data_valid;
    wire                      write_data_ready;

    wire                      write_resp;
    wire                      write_resp_valid;
    wire                      write_resp_ready;

    integer pass_count;
    integer fail_count;

    // ------------------------------------------------------------------
    // DUT: full system
    // ------------------------------------------------------------------
    axi4_lite_master #(
        .data_width (DATA_WIDTH),
        .add_width  (ADD_WIDTH),
        .add_num    (ADD_NUM)
    ) master (
        .clk              (clk),
        .rst              (rst),

        .start_write_out  (start_write_out),
        .write_add_out    (write_add_out),
        .write_data_out   (write_data_out),
        .write_done_out   (write_done_out),

        .start_read_out   (start_read_out),
        .read_add_out     (read_add_out),
        .read_data_out    (read_data_out),
        .read_done_out    (read_done_out),

        .read_add         (read_add),
        .read_add_ready   (read_add_ready),
        .read_add_valid   (read_add_valid),

        .read_data        (read_data),
        .read_data_valid  (read_data_valid),
        .read_data_resp   (read_data_resp),
        .read_data_ready  (read_data_ready),

        .write_add        (write_add),
        .write_add_ready  (write_add_ready),
        .write_add_valid  (write_add_valid),

        .write_data       (write_data),
        .write_data_ready (write_data_ready),
        .write_data_valid (write_data_valid),

        .write_resp       (write_resp),
        .write_resp_valid (write_resp_valid),
        .write_resp_ready (write_resp_ready)
    );

    axi4_lite_slave #(
        .data_width (DATA_WIDTH),
        .add_width  (ADD_WIDTH),
        .add_num    (ADD_NUM)
    ) slave (
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
        .write_resp_ready (write_resp_ready),

        .read_add         (read_add),
        .read_add_valid   (read_add_valid),
        .read_add_ready   (read_add_ready),

        .read_data        (read_data),
        .read_data_valid  (read_data_valid),
        .read_data_resp   (read_data_resp),
        .read_data_ready  (read_data_ready)
    );

    // ------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task do_reset;
        begin
            rst              = 0;   // active-low
            start_write_out  = 0;
            write_add_out    = 0;
            write_data_out   = 0;
            start_read_out   = 0;
            read_add_out     = 0;
            repeat (3) @(posedge clk);
            rst = 1;
            @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // Drivers (control-interface only -- system-level, black-box)
    // ------------------------------------------------------------------
    task automatic master_write(input [ADD_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        integer n;
        begin
            @(negedge clk);
            write_add_out   = addr;
            write_data_out  = data;
            start_write_out = 1;
            @(negedge clk);
            start_write_out = 0;

            n = 0;
            while (!write_done_out && n < TIMEOUT_CYCLES) begin
                @(negedge clk);
                n = n + 1;
            end

            if (n >= TIMEOUT_CYCLES) begin
                $display("FAIL: master_write addr=%0d data=%0d -- write_done_out timeout", addr, data);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: master_write addr=%0d data=%0d (done in %0d cycles)", addr, data, n);
                pass_count = pass_count + 1;
            end

            @(negedge clk);
        end
    endtask

    task automatic master_read(input [ADD_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] expected);
        integer n;
        begin
            @(negedge clk);
            read_add_out   = addr;
            start_read_out = 1;
            @(negedge clk);
            start_read_out = 0;

            n = 0;
            while (!read_done_out && n < TIMEOUT_CYCLES) begin
                @(negedge clk);
                n = n + 1;
            end

            if (n >= TIMEOUT_CYCLES) begin
                $display("FAIL: master_read addr=%0d -- read_done_out timeout", addr);
                fail_count = fail_count + 1;
            end else if (read_data_out !== expected) begin
                $display("FAIL: master_read addr=%0d -- got %0d expected %0d", addr, read_data_out, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: master_read addr=%0d data=%0d (done in %0d cycles)", addr, read_data_out, n);
                pass_count = pass_count + 1;
            end

            @(negedge clk);
        end
    endtask

    // Fire start_write_out/start_read_out back-to-back with no idle gap
    // between the two pulses, to check the master doesn't drop/misfire
    // a request issued right after the previous one's done pulse.
    task automatic back_to_back_write_then_read(input [ADD_WIDTH-1:0] waddr, input [DATA_WIDTH-1:0] wdata,
                                                 input [ADD_WIDTH-1:0] raddr, input [DATA_WIDTH-1:0] expected);
        integer n;
        begin
            @(negedge clk);
            write_add_out   = waddr;
            write_data_out  = wdata;
            start_write_out = 1;
            @(negedge clk);
            start_write_out = 0;

            n = 0;
            while (!write_done_out && n < TIMEOUT_CYCLES) begin @(negedge clk); n = n + 1; end
            if (n >= TIMEOUT_CYCLES) begin
                $display("FAIL: back_to_back write phase timeout addr=%0d", waddr);
                fail_count = fail_count + 1;
            end

            // Issue the read on the very next negedge, no extra idle cycle
            read_add_out   = raddr;
            start_read_out = 1;
            @(negedge clk);
            start_read_out = 0;

            n = 0;
            while (!read_done_out && n < TIMEOUT_CYCLES) begin @(negedge clk); n = n + 1; end
            if (n >= TIMEOUT_CYCLES) begin
                $display("FAIL: back_to_back read phase timeout addr=%0d", raddr);
                fail_count = fail_count + 1;
            end else if (read_data_out !== expected) begin
                $display("FAIL: back_to_back read addr=%0d -- got %0d expected %0d", raddr, read_data_out, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: back_to_back write addr=%0d then read addr=%0d data=%0d", waddr, raddr, read_data_out);
                pass_count = pass_count + 1;
            end

            @(negedge clk);
        end
    endtask

    // Fire start_write_out and start_read_out in the SAME cycle, to
    // different (or the same) addresses, and confirm the master's two
    // independent FSMs (busy_write / busy_read) actually run concurrently
    // rather than one blocking or corrupting the other. Each finishes
    // independently -- write may finish before/after/same-cycle as read --
    // so this waits for both done pulses separately before checking.
    task automatic concurrent_write_read(input [ADD_WIDTH-1:0] waddr, input [DATA_WIDTH-1:0] wdata,
                                          input [ADD_WIDTH-1:0] raddr, input [DATA_WIDTH-1:0] expected_read);
        integer n;
        reg write_done_seen;
        reg read_done_seen;
        reg [DATA_WIDTH-1:0] captured_read_data;
        begin
            write_done_seen = 0;
            read_done_seen  = 0;

            @(negedge clk);
            write_add_out   = waddr;
            write_data_out  = wdata;
            start_write_out = 1;
            read_add_out    = raddr;
            start_read_out  = 1;

            @(negedge clk);
            start_write_out = 0;
            start_read_out  = 0;

            n = 0;
            while (!(write_done_seen && read_done_seen) && n < TIMEOUT_CYCLES) begin
                if (write_done_out && !write_done_seen)
                    write_done_seen = 1;
                if (read_done_out && !read_done_seen) begin
                    read_done_seen = 1;
                    captured_read_data = read_data_out;
                end
                @(negedge clk);
                n = n + 1;
            end

            if (n >= TIMEOUT_CYCLES) begin
                $display("FAIL: concurrent_write_read waddr=%0d raddr=%0d -- timeout (write_done=%0d read_done=%0d)",
                          waddr, raddr, write_done_seen, read_done_seen);
                fail_count = fail_count + 1;
            end else if (captured_read_data !== expected_read) begin
                $display("FAIL: concurrent_write_read waddr=%0d raddr=%0d -- read got %0d expected %0d",
                          waddr, raddr, captured_read_data, expected_read);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: concurrent_write_read waddr=%0d wdata=%0d || raddr=%0d read_data=%0d",
                          waddr, wdata, raddr, captured_read_data);
                pass_count = pass_count + 1;
            end

            @(negedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------------
    integer i;
    reg [DATA_WIDTH-1:0] shadow_mem [0:ADD_NUM-1];

    initial begin
        pass_count = 0;
        fail_count = 0;

        do_reset;

        // 1) Single write/read sanity check
        master_write(4'd0, 32'hDEAD_BEEF);
        master_read (4'd0, 32'hDEAD_BEEF);

        // 2) Full address-space sweep: write every location, then verify
        //    every location, so a stale/aliased address bug would show up.
        for (i = 0; i < ADD_NUM; i = i + 1) begin
            shadow_mem[i] = 32'hC000_0000 + i;
            master_write(i[ADD_WIDTH-1:0], shadow_mem[i]);
        end
        for (i = 0; i < ADD_NUM; i = i + 1) begin
            master_read(i[ADD_WIDTH-1:0], shadow_mem[i]);
        end

        // 3) Overwrite: last write to an address wins
        master_write(4'd6, 32'h1111_1111);
        master_write(4'd6, 32'h2222_2222);
        master_read (4'd6, 32'h2222_2222);

        // 4) Interleaved writes/reads across different addresses
        master_write(4'd1, 32'hAAAA_0001);
        master_write(4'd2, 32'hAAAA_0002);
        master_read (4'd1, 32'hAAAA_0001);
        master_write(4'd3, 32'hAAAA_0003);
        master_read (4'd2, 32'hAAAA_0002);
        master_read (4'd3, 32'hAAAA_0003);

        // 5) Back-to-back write->read with no idle gap between requests
        back_to_back_write_then_read(4'd11, 32'hFEED_0011, 4'd11, 32'hFEED_0011);
        back_to_back_write_then_read(4'd12, 32'hFEED_0012, 4'd0,  shadow_mem[0]);

        // 6) Repeated read of the same address (no intervening write)
        master_read(4'd11, 32'hFEED_0011);
        master_read(4'd11, 32'hFEED_0011);

        // 7) Boundary addresses (0 and ADD_NUM-1)
        master_write((ADD_NUM-1), 32'hB0DE_FACE);
        master_read ((ADD_NUM-1), 32'hB0DE_FACE);
        master_write(4'd0, 32'h0BAD_0BAD);
        master_read (4'd0, 32'h0BAD_0BAD);

        // 8) True concurrent write+read, DIFFERENT addresses, started the
        //    same cycle: the read (to addr 9) must be unaffected by a
        //    simultaneous write to addr 8.
        concurrent_write_read(4'd8, 32'h9999_0008, 4'd9, shadow_mem[9]);

        // 9) True concurrent write+read to the SAME address, started the
        //    same cycle. Per the shared-memory comment in the top module
        //    ("same-cycle read/write to the same address returns the OLD
        //    value"), the read is expected to return the value that was
        //    in that slot BEFORE this write, not the new write data.
        master_write(4'd4, 32'h4444_0000);          // known baseline value at addr 4
        concurrent_write_read(4'd4, 32'h4444_FFFF, 4'd4, 32'h4444_0000);
        master_read(4'd4, 32'h4444_FFFF);            // confirm the write DID land afterward

        @(posedge clk);
        $display("--------------------------------------------------");
        $display("TOTAL: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: FAILURES PRESENT");
        $display("--------------------------------------------------");
        $finish;
    end

    // Safety watchdog in case a task hangs
    initial begin
        #(CLK_PERIOD * 8000);
        $display("FAIL: global watchdog timeout -- simulation did not finish");
        $finish;
    end

endmodule