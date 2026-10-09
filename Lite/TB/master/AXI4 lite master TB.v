`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// tb_axi4_lite_master
//
// Standalone testbench for axi4_lite_master. The DUT's AXI4-Lite interface
// is driven by a lightweight behavioral slave model (below) instead of the
// real axi4_lite_read/axi4_lite_write modules, so the master's control
// interface and protocol behavior can be checked in isolation before it is
// hooked up to the real slave.
//
// Slave model features:
//   - Independent, programmable delays for: address-ready, data-ready,
//     read-data-valid, write-response-valid (back-pressure emulation)
//   - A reference memory array so write-then-read sequences self-check
//   - VALID-stability monitors on the master's outputs (read_add_valid,
//     write_add_valid, write_data_valid): once asserted, VALID must stay
//     high and the associated address/data must not change until READY
//     is also seen, per AXI4-Lite handshake rules
// ---------------------------------------------------------------------------

module tb_axi4_lite_master;

    parameter DATA_WIDTH = 32;
    parameter ADD_WIDTH  = 4;
    parameter ADD_NUM    = 16;

    // Clock / reset
    reg clk;
    reg rst;   // matches DUT convention: rst = 0 is reset, rst = 1 is run

    // Control interface (testbench drives, DUT drives status back)
    reg                        start_write_out;
    reg  [ADD_WIDTH  - 1 : 0]  write_add_out;
    reg  [DATA_WIDTH - 1 : 0]  write_data_out;
    wire                       write_done_out;

    reg                        start_read_out;
    reg  [ADD_WIDTH  - 1 : 0]  read_add_out;
    wire [DATA_WIDTH - 1 : 0]  read_data_out;
    wire                       read_done_out;

    // AXI4-Lite interface between DUT (master) and the slave BFM below
    wire [ADD_WIDTH  - 1 : 0]  read_add;
    reg                        read_add_ready;
    wire                       read_add_valid;

    reg  [DATA_WIDTH - 1 : 0]  read_data;
    reg                        read_data_valid;
    reg                        read_data_resp;
    wire                       read_data_ready;

    wire [ADD_WIDTH  - 1 : 0]  write_add;
    reg                        write_add_ready;
    wire                       write_add_valid;

    wire [DATA_WIDTH - 1 : 0]  write_data;
    reg                        write_data_ready;
    wire                       write_data_valid;

    reg                        write_resp;
    reg                        write_resp_valid;
    wire                       write_resp_ready;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    axi4_lite_master #(
        .data_width (DATA_WIDTH),
        .add_width  (ADD_WIDTH),
        .add_num    (ADD_NUM)
    ) dut (
        .clk (clk),
        .rst (rst),

        .start_write_out (start_write_out),
        .write_add_out   (write_add_out),
        .write_data_out  (write_data_out),
        .write_done_out  (write_done_out),

        .start_read_out  (start_read_out),
        .read_add_out    (read_add_out),
        .read_data_out   (read_data_out),
        .read_done_out   (read_done_out),

        .read_add        (read_add),
        .read_add_ready  (read_add_ready),
        .read_add_valid  (read_add_valid),

        .read_data       (read_data),
        .read_data_valid (read_data_valid),
        .read_data_resp  (read_data_resp),
        .read_data_ready (read_data_ready),

        .write_add       (write_add),
        .write_add_ready (write_add_ready),
        .write_add_valid (write_add_valid),

        .write_data       (write_data),
        .write_data_ready (write_data_ready),
        .write_data_valid (write_data_valid),

        .write_resp       (write_resp),
        .write_resp_valid (write_resp_valid),
        .write_resp_ready (write_resp_ready)
    );

    // ------------------------------------------------------------------
    // Clock: 10 ns period
    // ------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Bookkeeping
    // ------------------------------------------------------------------
    integer checks = 0;
    integer errors = 0;
    integer i;

    reg [ADD_WIDTH  - 1 : 0] addr;
    reg [DATA_WIDTH - 1 : 0] data;

    reg [DATA_WIDTH - 1 : 0] ref_mem [ADD_NUM - 1 : 0];

    // Slave-model delay knobs (in clock cycles)
    integer add_ready_delay   ;
    integer data_ready_delay  ;
    integer rdata_valid_delay ;
    integer resp_valid_delay  ;

    // Slave-model capture state
    reg [ADD_WIDTH  - 1 : 0] captured_read_add;
    reg                      read_add_captured;

    reg [ADD_WIDTH  - 1 : 0] captured_write_add;
    reg [DATA_WIDTH - 1 : 0] captured_write_data;
    reg                      write_add_captured;
    reg                      write_data_captured;

    // ------------------------------------------------------------------
    // Slave BFM — all five agents below are clocked, nonblocking-
    // assignment processes (same style as the DUT itself). This is
    // deliberate: mixing blocking-assignment testbench drivers with the
    // DUT's own nonblocking registered handshake signals creates a
    // same-edge read/write race (the agent's "is it accepted yet" check
    // can see a stale value depending on process evaluation order).
    // Using nonblocking assignment here means every process — DUT and
    // BFM alike — reads pre-edge (old) values of every signal during
    // the active region, so handshakes are detected deterministically.
    // Each captured/valid flag has exactly one owning process to avoid
    // multi-driver conflicts; other agents only read it.
    // ------------------------------------------------------------------
    reg [7:0] r_addr_cnt, r_data_cnt, w_addr_cnt, w_data_cnt, w_resp_cnt;

    // Read address channel (owns read_add_ready, read_add_captured)
    always @(posedge clk) begin
        if (!rst) begin
            read_add_ready    <= 1'b0;
            read_add_captured <= 1'b0;
            r_addr_cnt        <= 8'd0;
        end else if (read_add_captured) begin
            if (read_data_valid && read_data_ready)
                read_add_captured <= 1'b0;   // data phase done, free up for next address
        end else if (!read_add_valid) begin
            read_add_ready <= 1'b0;
            r_addr_cnt     <= 8'd0;
        end else if (!read_add_ready) begin
            if (r_addr_cnt < add_ready_delay)
                r_addr_cnt <= r_addr_cnt + 8'd1;
            else
                read_add_ready <= 1'b1;
        end else begin
            // read_add_valid && read_add_ready both true as of this edge => handshake
            captured_read_add <= read_add;
            read_add_captured <= 1'b1;
            read_add_ready    <= 1'b0;
            r_addr_cnt        <= 8'd0;
        end
    end

    // Read data channel (owns read_data/valid/resp; only reads read_add_captured)
    always @(posedge clk) begin
        if (!rst) begin
            read_data       <= {DATA_WIDTH{1'b0}};
            read_data_valid <= 1'b0;
            read_data_resp  <= 1'b0;
            r_data_cnt      <= 8'd0;
        end else if (!read_add_captured) begin
            read_data_valid <= 1'b0;
            r_data_cnt      <= 8'd0;
        end else if (!read_data_valid) begin
            if (r_data_cnt < rdata_valid_delay) begin
                r_data_cnt <= r_data_cnt + 8'd1;
            end else begin
                read_data       <= ref_mem[captured_read_add];
                read_data_resp  <= 1'b0;             // OKAY
                read_data_valid <= 1'b1;
            end
        end else if (read_data_ready) begin
            read_data_valid <= 1'b0;
        end
    end

    // Write address channel (owns write_add_ready, write_add_captured)
    always @(posedge clk) begin
        if (!rst) begin
            write_add_ready    <= 1'b0;
            write_add_captured <= 1'b0;
            w_addr_cnt         <= 8'd0;
        end else if (write_add_captured) begin
            if (write_resp_valid && write_resp_ready)
                write_add_captured <= 1'b0;  // response consumed, free up for next write
        end else if (!write_add_valid) begin
            write_add_ready <= 1'b0;
            w_addr_cnt      <= 8'd0;
        end else if (!write_add_ready) begin
            if (w_addr_cnt < add_ready_delay)
                w_addr_cnt <= w_addr_cnt + 8'd1;
            else
                write_add_ready <= 1'b1;
        end else begin
            captured_write_add  <= write_add;
            write_add_captured  <= 1'b1;
            write_add_ready     <= 1'b0;
            w_addr_cnt          <= 8'd0;
        end
    end

    // Write data channel (owns write_data_ready, write_data_captured)
    always @(posedge clk) begin
        if (!rst) begin
            write_data_ready    <= 1'b0;
            write_data_captured <= 1'b0;
            w_data_cnt           <= 8'd0;
        end else if (write_data_captured) begin
            if (write_resp_valid && write_resp_ready)
                write_data_captured <= 1'b0;
        end else if (!write_data_valid) begin
            write_data_ready <= 1'b0;
            w_data_cnt        <= 8'd0;
        end else if (!write_data_ready) begin
            if (w_data_cnt < data_ready_delay)
                w_data_cnt <= w_data_cnt + 8'd1;
            else
                write_data_ready <= 1'b1;
        end else begin
            captured_write_data <= write_data;
            write_data_captured <= 1'b1;
            write_data_ready    <= 1'b0;
            w_data_cnt           <= 8'd0;
        end
    end

    // Write response channel (owns write_resp/valid; commits to ref_mem;
    // only reads write_add_captured / write_data_captured)
    always @(posedge clk) begin
        if (!rst) begin
            write_resp       <= 1'b0;
            write_resp_valid <= 1'b0;
            w_resp_cnt        <= 8'd0;
        end else if (!(write_add_captured && write_data_captured)) begin
            write_resp_valid <= 1'b0;
            w_resp_cnt        <= 8'd0;
        end else if (!write_resp_valid) begin
            if (w_resp_cnt < resp_valid_delay) begin
                w_resp_cnt <= w_resp_cnt + 8'd1;
            end else begin
                ref_mem[captured_write_add] <= captured_write_data;
                write_resp       <= 1'b0;            // OKAY
                write_resp_valid <= 1'b1;
            end
        end else if (write_resp_ready) begin
            write_resp_valid <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // VALID-stability monitors: once the master asserts VALID and READY
    // hasn't arrived yet, VALID and the associated payload must hold on
    // the next cycle. Flags a protocol violation on the master side.
    // ------------------------------------------------------------------
    reg prev_r_add_valid, prev_r_add_ready;
    reg [ADD_WIDTH - 1 : 0] prev_r_add;

    reg prev_w_add_valid, prev_w_add_ready;
    reg [ADD_WIDTH - 1 : 0] prev_w_add;

    reg prev_w_data_valid, prev_w_data_ready;
    reg [DATA_WIDTH - 1 : 0] prev_w_data;

    always @(posedge clk) begin
        if (!rst) begin
            prev_r_add_valid  <= 1'b0;
            prev_w_add_valid  <= 1'b0;
            prev_w_data_valid <= 1'b0;
        end else begin
            if (prev_r_add_valid && !prev_r_add_ready) begin
                checks = checks + 1;
                if (read_add_valid !== 1'b1) begin
                    errors = errors + 1;
                    $display("ERROR @%0t: read_add_valid dropped before handshake", $time);
                end else if (read_add !== prev_r_add) begin
                    errors = errors + 1;
                    $display("ERROR @%0t: read_add changed while valid asserted, no handshake", $time);
                end
            end

            if (prev_w_add_valid && !prev_w_add_ready) begin
                checks = checks + 1;
                if (write_add_valid !== 1'b1) begin
                    errors = errors + 1;
                    $display("ERROR @%0t: write_add_valid dropped before handshake", $time);
                end else if (write_add !== prev_w_add) begin
                    errors = errors + 1;
                    $display("ERROR @%0t: write_add changed while valid asserted, no handshake", $time);
                end
            end

            if (prev_w_data_valid && !prev_w_data_ready) begin
                checks = checks + 1;
                if (write_data_valid !== 1'b1) begin
                    errors = errors + 1;
                    $display("ERROR @%0t: write_data_valid dropped before handshake", $time);
                end else if (write_data !== prev_w_data) begin
                    errors = errors + 1;
                    $display("ERROR @%0t: write_data changed while valid asserted, no handshake", $time);
                end
            end

            prev_r_add_valid  <= read_add_valid;
            prev_r_add_ready  <= read_add_ready;
            prev_r_add        <= read_add;

            prev_w_add_valid  <= write_add_valid;
            prev_w_add_ready  <= write_add_ready;
            prev_w_add        <= write_add;

            prev_w_data_valid <= write_data_valid;
            prev_w_data_ready <= write_data_ready;
            prev_w_data       <= write_data;
        end
    end

    // ------------------------------------------------------------------
    // Directed-test tasks (drive the control interface, self-check)
    // ------------------------------------------------------------------
    task automatic do_write(input [ADD_WIDTH - 1 : 0] a, input [DATA_WIDTH - 1 : 0] d);
        begin
            write_add_out   = a;
            write_data_out  = d;
            start_write_out = 1'b1;
            @(posedge clk);
            // Nonblocking clear: the DUT's own posedge block samples
            // start_write_out on this very edge, so a blocking clear here
            // would race it (evaluation order between the two processes
            // is undefined at the same time step, and the DUT can miss
            // the pulse). A nonblocking assignment defers to the NBA
            // region, so the DUT deterministically still sees '1' on
            // this edge, and start_write_out settles to '0' only for the
            // edge after.
            start_write_out <= 1'b0;
            while (!write_done_out) @(posedge clk);
            $display("WRITE @%0t: addr %0d <= 0x%08h", $time, a, d);
        end
    endtask

    task automatic do_read(input [ADD_WIDTH - 1 : 0] a, input [DATA_WIDTH - 1 : 0] expected);
        begin
            read_add_out   = a;
            start_read_out = 1'b1;
            @(posedge clk);
            start_read_out <= 1'b0;  // nonblocking clear — see do_write for why
            while (!read_done_out) @(posedge clk);

            checks = checks + 1;
            if (read_data_out !== expected) begin
                errors = errors + 1;
                $display("ERROR @%0t: read addr %0d expected 0x%08h got 0x%08h",
                          $time, a, expected, read_data_out);
            end else begin
                $display("READ  @%0t: addr %0d => 0x%08h  (match)", $time, a, read_data_out);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("tb_axi4_lite_master.vcd");
        $dumpvars(0, tb_axi4_lite_master);

        start_write_out   = 1'b0;
        write_add_out     = {ADD_WIDTH{1'b0}};
        write_data_out    = {DATA_WIDTH{1'b0}};
        start_read_out    = 1'b0;
        read_add_out      = {ADD_WIDTH{1'b0}};

        add_ready_delay   = 0;
        data_ready_delay  = 0;
        rdata_valid_delay = 0;
        resp_valid_delay  = 0;

        rst = 1'b0;
        repeat (4) @(posedge clk);
        rst = 1'b1;
        @(posedge clk);

        $display("=== Test 1: back-to-back write/read, zero slave delay ===");
        do_write(4'd0, 32'hAAAA_0001);
        do_read (4'd0, 32'hAAAA_0001);
        do_write(4'd5, 32'h1234_5678);
        do_read (4'd5, 32'h1234_5678);

        $display("=== Test 2: slave imposes address-ready delay ===");
        add_ready_delay = 3;
        do_write(4'd1, 32'hDEAD_BEEF);
        do_read (4'd1, 32'hDEAD_BEEF);
        add_ready_delay = 0;

        $display("=== Test 3: slave imposes data-ready delay ===");
        data_ready_delay = 3;
        do_write(4'd6, 32'hFEED_FACE);
        do_read (4'd6, 32'hFEED_FACE);
        data_ready_delay = 0;

        $display("=== Test 4: slave imposes read-data-valid / write-resp-valid delay ===");
        rdata_valid_delay = 4;
        resp_valid_delay  = 4;
        do_write(4'd2, 32'h0BAD_F00D);
        do_read (4'd2, 32'h0BAD_F00D);
        rdata_valid_delay = 0;
        resp_valid_delay  = 0;

        $display("=== Test 5: write to every address, read back in reverse order ===");
        for (i = 0; i < ADD_NUM; i = i + 1)
            do_write(i[ADD_WIDTH-1:0], 32'h1000_0000 + i);
        for (i = ADD_NUM - 1; i >= 0; i = i - 1)
            do_read(i[ADD_WIDTH-1:0], 32'h1000_0000 + i);

        $display("=== Test 6: randomized transactions with random slave delays ===");
        for (i = 0; i < 50; i = i + 1) begin
            addr = $unsigned($random) % ADD_NUM;
            data = $random;

            add_ready_delay   = $unsigned($random) % 4;
            data_ready_delay  = $unsigned($random) % 4;
            rdata_valid_delay = $unsigned($random) % 4;
            resp_valid_delay  = $unsigned($random) % 4;

            do_write(addr, data);
            do_read (addr, data);
        end
        add_ready_delay   = 0;
        data_ready_delay  = 0;
        rdata_valid_delay = 0;
        resp_valid_delay  = 0;

        $display("=====================================================");
        $display("Total checks: %0d   Errors: %0d", checks, errors);
        if (errors == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: TESTS FAILED");
        $display("=====================================================");

        $finish;
    end

endmodule