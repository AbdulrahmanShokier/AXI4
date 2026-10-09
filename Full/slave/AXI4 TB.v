`timescale 1ns/1ps
//=============================================================================
// tb_axi4_system : system-level testbench, axi4_master <-> axi4_slave
//
//  - The TB drives ONLY the master's user interface (start_*, *_out). It never
//    touches the AXI channels; those are wired master <-> slave internally.
//  - rst is ACTIVE-LOW, burst length field: beats = length + 1
//  - Inputs driven on negedge, DUT outputs sampled at posedge / negedge.
//  - ref_mem is an independent golden model; slave.memory is checked against it.
//  - Concurrent read/write tests use DISJOINT regions (same-address races
//    are undefined for a burst slave).
//=============================================================================
module tb_axi4_system;

    parameter DATA_WIDTH = 32;
    parameter ADD_WIDTH  = 4;
    parameter LEN_WIDTH  = 4;
    parameter ADD_NUM    = 16;

    //-------------------------------------------------------------------
    // Signals
    //-------------------------------------------------------------------
    reg                    clk;
    reg                    rst;

    // user side : write
    reg                    start_write_out;
    reg  [ADD_WIDTH-1:0]   write_add_out;
    reg  [LEN_WIDTH-1:0]   write_length_out;
    reg  [DATA_WIDTH-1:0]  write_data_out;
    reg                    write_data_valid_out;
    wire                   write_data_ready_out;
    wire                   write_busy_out;
    wire                   write_done_out;
    wire                   write_error_out;

    // user side : read
    reg                    start_read_out;
    reg  [ADD_WIDTH-1:0]   read_add_out;
    reg  [LEN_WIDTH-1:0]   read_length_out;
    wire [DATA_WIDTH-1:0]  read_data_out;
    wire                   read_data_valid_out;
    reg                    read_data_ready_out;
    wire                   read_data_last_out;
    wire                   read_busy_out;
    wire                   read_done_out;
    wire                   read_error_out;

    // AXI wiring (master <-> slave, observed only)
    wire [ADD_WIDTH-1:0]   write_add;
    wire                   write_add_valid;
    wire                   write_add_ready;
    wire [LEN_WIDTH-1:0]   write_add_length;
    wire [DATA_WIDTH-1:0]  write_data;
    wire                   write_data_valid;
    wire                   write_data_ready;
    wire                   write_data_last;
    wire                   write_resp;
    wire                   write_resp_valid;
    wire                   write_resp_ready;

    wire [ADD_WIDTH-1:0]   read_add;
    wire                   read_add_valid;
    wire                   read_add_ready;
    wire [LEN_WIDTH-1:0]   read_add_length;
    wire [DATA_WIDTH-1:0]  read_data;
    wire                   read_data_valid;
    wire                   read_data_resp;
    wire                   read_data_ready;
    wire                   read_data_last;

    //-------------------------------------------------------------------
    // DUTs
    //-------------------------------------------------------------------
    axi4_master #(
        .data_width (DATA_WIDTH),
        .add_width  (ADD_WIDTH),
        .len_width  (LEN_WIDTH)
    ) master (
        .clk                  (clk),
        .rst                  (rst),

        .start_write_out      (start_write_out),
        .write_add_out        (write_add_out),
        .write_length_out     (write_length_out),
        .write_data_out       (write_data_out),
        .write_data_valid_out (write_data_valid_out),
        .write_data_ready_out (write_data_ready_out),
        .write_busy_out       (write_busy_out),
        .write_done_out       (write_done_out),
        .write_error_out      (write_error_out),

        .start_read_out       (start_read_out),
        .read_add_out         (read_add_out),
        .read_length_out      (read_length_out),
        .read_data_out        (read_data_out),
        .read_data_valid_out  (read_data_valid_out),
        .read_data_ready_out  (read_data_ready_out),
        .read_data_last_out   (read_data_last_out),
        .read_busy_out        (read_busy_out),
        .read_done_out        (read_done_out),
        .read_error_out       (read_error_out),

        .write_add            (write_add),
        .write_add_valid      (write_add_valid),
        .write_add_ready      (write_add_ready),
        .write_add_length     (write_add_length),
        .write_data           (write_data),
        .write_data_valid     (write_data_valid),
        .write_data_ready     (write_data_ready),
        .write_data_last      (write_data_last),
        .write_resp           (write_resp),
        .write_resp_valid     (write_resp_valid),
        .write_resp_ready     (write_resp_ready),

        .read_add             (read_add),
        .read_add_valid       (read_add_valid),
        .read_add_ready       (read_add_ready),
        .read_add_length      (read_add_length),
        .read_data            (read_data),
        .read_data_valid      (read_data_valid),
        .read_data_resp       (read_data_resp),
        .read_data_ready      (read_data_ready),
        .read_data_last       (read_data_last)
    );

    axi4_slave #(
        .data_width (DATA_WIDTH),
        .add_width  (ADD_WIDTH),
        .len_width  (LEN_WIDTH),
        .add_num    (ADD_NUM)
    ) slave (
        .clk              (clk),
        .rst              (rst),

        .write_add        (write_add),
        .write_add_valid  (write_add_valid),
        .write_add_ready  (write_add_ready),
        .write_add_length (write_add_length),
        .write_data       (write_data),
        .write_data_valid (write_data_valid),
        .write_data_ready (write_data_ready),
        .write_data_last  (write_data_last),
        .write_resp       (write_resp),
        .write_resp_valid (write_resp_valid),
        .write_resp_ready (write_resp_ready),

        .read_add         (read_add),
        .read_add_valid   (read_add_valid),
        .read_add_ready   (read_add_ready),
        .read_add_length  (read_add_length),
        .read_data        (read_data),
        .read_data_valid  (read_data_valid),
        .read_data_resp   (read_data_resp),
        .read_data_ready  (read_data_ready),
        .read_data_last   (read_data_last)
    );

    //-------------------------------------------------------------------
    // Clock, dump, watchdog
    //-------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("axi4_system_tb.vcd");
        $dumpvars(0, tb_axi4_system);
    end

    initial begin
        #5000000;
        $display("TIMEOUT - system stuck");
        $finish;
    end

    //-------------------------------------------------------------------
    // Bookkeeping
    //-------------------------------------------------------------------
    integer errors;
    integer checks;
    integer i;
    integer burst_id;

    reg [DATA_WIDTH-1:0] ref_mem [0:ADD_NUM-1];   // golden memory
    reg [DATA_WIDTH-1:0] old_mem [0:ADD_NUM-1];   // memory snapshot before an overlap test
    reg                  ovl_en;                  // 1: a read beat may return old OR new data

    // Seedable RNG.  Run with  +SEED=<n>  to change the random sequence.
    integer rseed;
    function integer rnd;
        input integer n;
        begin
            rnd = ($random(rseed) & 32'h7FFFFFFF) % n;
        end
    endfunction

    task automatic check;
        input          cond;
        input [8*40:1] msg;
        begin
            checks = checks + 1;
            if (cond)
                $display("  PASS: %0s", msg);
            else begin
                $display("  FAIL: %0s  (t=%0t)", msg, $time);
                errors = errors + 1;
            end
        end
    endtask

    function [DATA_WIDTH-1:0] data_of;
        input [31:0] seed;
        input integer beat;
        begin
            data_of = seed * 32'h9E3779B1 + beat * 32'h01010101 + 32'h5A5A0000;
        end
    endfunction

    //-------------------------------------------------------------------
    // Monitors (observe the internal AXI wires, run all the time)
    //-------------------------------------------------------------------
    integer mem_wr_cnt;     // slave memory writes (global)
    integer w_hs_cnt;       // W handshakes (global)

    always @(posedge clk) begin
        if (slave.mem_wr_en)                          mem_wr_cnt <= mem_wr_cnt + 1;
        if (rst && write_data_valid && write_data_ready) w_hs_cnt <= w_hs_cnt + 1;
    end

    reg                     p_awv, p_awr;  reg [ADD_WIDTH-1:0]  p_aw;  reg [LEN_WIDTH-1:0] p_awl;
    reg                     p_wv,  p_wr;   reg [DATA_WIDTH-1:0] p_w;   reg                  p_wl;
    reg                     p_bv,  p_br;   reg                  p_b;
    reg                     p_arv, p_arr;  reg [ADD_WIDTH-1:0]  p_ar;  reg [LEN_WIDTH-1:0] p_arl;
    reg                     p_rv,  p_rr;   reg [DATA_WIDTH-1:0] p_r;   reg p_rl, p_rresp;
    reg                     p_wdone, p_rdone;
    reg                     mon_en;

    always @(posedge clk) begin
        if (mon_en && rst) begin
            // VALID stays high and payload stable until READY (all 5 channels)
            if (p_awv && !p_awr && (!write_add_valid || write_add !== p_aw || write_add_length !== p_awl)) begin
                $display("  FAIL: AW not stable under back-pressure (t=%0t)", $time); errors = errors + 1;
            end
            if (p_wv && !p_wr && (!write_data_valid || write_data !== p_w || write_data_last !== p_wl)) begin
                $display("  FAIL: W not stable under back-pressure (t=%0t)", $time); errors = errors + 1;
            end
            if (p_bv && !p_br && (!write_resp_valid || write_resp !== p_b)) begin
                $display("  FAIL: B not stable under back-pressure (t=%0t)", $time); errors = errors + 1;
            end
            if (p_arv && !p_arr && (!read_add_valid || read_add !== p_ar || read_add_length !== p_arl)) begin
                $display("  FAIL: AR not stable under back-pressure (t=%0t)", $time); errors = errors + 1;
            end
            if (p_rv && !p_rr && (!read_data_valid || read_data !== p_r ||
                                  read_data_last !== p_rl || read_data_resp !== p_rresp)) begin
                $display("  FAIL: R not stable under back-pressure (t=%0t)", $time); errors = errors + 1;
            end
            // static protocol rules
            if (write_add_ready && write_data_ready) begin
                $display("  FAIL: AWREADY and WREADY high together (t=%0t)", $time); errors = errors + 1;
            end
            if (write_add_valid && write_data_valid) begin
                $display("  FAIL: AWVALID and WVALID high together (t=%0t)", $time); errors = errors + 1;
            end
            if (p_wdone && write_done_out) begin
                $display("  FAIL: write_done_out wider than one cycle (t=%0t)", $time); errors = errors + 1;
            end
            if (p_rdone && read_done_out) begin
                $display("  FAIL: read_done_out wider than one cycle (t=%0t)", $time); errors = errors + 1;
            end
            if (write_error_out || read_error_out) begin
                $display("  FAIL: unexpected error flag (w=%b r=%b) (t=%0t)",
                         write_error_out, read_error_out, $time);
                errors = errors + 1;
            end
        end
        p_awv <= write_add_valid;  p_awr <= write_add_ready; p_aw <= write_add; p_awl <= write_add_length;
        p_wv  <= write_data_valid; p_wr  <= write_data_ready; p_w <= write_data; p_wl <= write_data_last;
        p_bv  <= write_resp_valid; p_br  <= write_resp_ready; p_b <= write_resp;
        p_arv <= read_add_valid;   p_arr <= read_add_ready;  p_ar <= read_add; p_arl <= read_add_length;
        p_rv  <= read_data_valid;  p_rr  <= read_data_ready; p_r <= read_data;
        p_rl  <= read_data_last;   p_rresp <= read_data_resp;
        p_wdone <= write_done_out; p_rdone <= read_done_out;
    end

    //-------------------------------------------------------------------
    // Helpers
    //-------------------------------------------------------------------
    task apply_reset;
        begin
            @(negedge clk);
            rst                  = 0;
            start_write_out      = 0;  write_add_out   = 0;  write_length_out = 0;
            write_data_out       = 0;  write_data_valid_out = 0;
            start_read_out       = 0;  read_add_out    = 0;  read_length_out  = 0;
            read_data_ready_out  = 0;
            repeat (2) @(posedge clk);
            #1;
            check(write_busy_out == 0,      "reset: write_busy low");
            check(write_done_out == 0,      "reset: write_done low");
            check(write_error_out == 0,     "reset: write_error low");
            check(write_add_valid == 0,     "reset: AWVALID low");
            check(write_data_valid == 0,    "reset: WVALID low");
            check(write_resp_ready == 0,    "reset: BREADY low");
            check(write_add_ready == 1,     "reset: AWREADY high");
            check(write_data_ready == 0,    "reset: WREADY low");
            check(write_resp_valid == 0,    "reset: BVALID low");
            check(slave.mem_wr_en == 0,     "reset: mem_wr_en low");
            check(read_busy_out == 0,       "reset: read_busy low");
            check(read_done_out == 0,       "reset: read_done low");
            check(read_error_out == 0,      "reset: read_error low");
            check(read_add_valid == 0,      "reset: ARVALID low");
            check(read_add_ready == 1,      "reset: ARREADY high");
            check(read_data_ready == 0,     "reset: RREADY low");
            check(read_data_valid == 0,     "reset: RVALID low");
            check(read_data_valid_out == 0, "reset: user RVALID low");
            @(negedge clk);
            rst = 1;
        end
    endtask

    // copy slave memory into the golden model (after a reset mid-burst)
    task resync_ref;
        integer m;
        begin
            for (m = 0; m < ADD_NUM; m = m + 1) ref_mem[m] = slave.memory[m];
        end
    endtask

    task automatic compare_mem;
        input [8*24:1] name;
        integer m, bad;
        begin
            bad = 0;
            for (m = 0; m < ADD_NUM; m = m + 1)
                if (slave.memory[m] !== ref_mem[m]) begin
                    $display("  FAIL: memory[%0d]=%h expected %h", m, slave.memory[m], ref_mem[m]);
                    bad = bad + 1;
                end
            check(bad == 0, "slave memory matches golden");
            errors = errors + bad;
        end
    endtask

    //-------------------------------------------------------------------
    // WRITE transaction through the master
    //   src_dly : cycles before the first beat is offered
    //   gap     : idle cycles between beats from the source
    //   poke    : 1 -> pulse start again while busy (address and data
    //             phase); must be ignored
    //-------------------------------------------------------------------
    task automatic write_txn;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         src_dly;
        input integer         gap;
        input                 poke;
        input [8*24:1]        name;

        integer b, cyc, cnt0, wh0;
        reg [31:0] seed;
        begin
            $display("");
            $display("-- WRITE %0s : addr=%0d len=%0d src_dly=%0d gap=%0d poke=%0d",
                     name, addr, len, src_dly, gap, poke);

            burst_id = burst_id + 1;
            seed     = burst_id;
            for (b = 0; b <= len; b = b + 1)
                ref_mem[(addr + b) % ADD_NUM] = data_of(seed, b);

            // ---- start ----
            @(negedge clk);
            while (write_busy_out) @(negedge clk);
            cnt0 = mem_wr_cnt;
            wh0  = w_hs_cnt;
            write_add_out    = addr;
            write_length_out = len;
            start_write_out  = 1;
            @(negedge clk);
            start_write_out  = 0;
            write_add_out    = ~addr;       // must have been latched
            write_length_out = ~len;
            check(write_busy_out == 1, "start accepted, busy high");

            if (poke) begin
                write_add_out    = addr ^ 4'h5;
                write_length_out = len  ^ 4'h3;
                start_write_out  = 1;
                @(negedge clk);
                start_write_out  = 0;
                write_add_out    = ~addr;
                write_length_out = ~len;
            end

            // ---- data from the outside source ----
            repeat (src_dly) @(negedge clk);
            for (b = 0; b <= len; b = b + 1) begin
                write_data_out       = data_of(seed, b);
                write_data_valid_out = 1;
                @(posedge clk);
                while (!write_data_ready_out) @(posedge clk);
                @(negedge clk);
                write_data_valid_out = 0;
                write_data_out       = ~data_of(seed, b);   // must not be re-sampled
                if (poke && b == 0 && len != 0) begin
                    write_add_out    = addr ^ 4'h5;
                    write_length_out = len  ^ 4'h3;
                    start_write_out  = 1;
                    @(negedge clk);
                    start_write_out  = 0;
                    write_add_out    = ~addr;
                    write_length_out = ~len;
                end
                if (b < len) repeat (gap) @(negedge clk);
            end

            // ---- wait for done ----
            cyc = 0;
            while (!write_done_out && cyc < 2000) begin
                @(negedge clk);
                cyc = cyc + 1;
            end
            check(write_done_out == 1,           "write_done pulse seen");
            check(write_busy_out == 1,           "busy still high at done");
            check(write_error_out === 1'b0,      "write_error low (BRESP okay)");
            check(w_hs_cnt - wh0 == len + 1,     "slave accepted len+1 beats");
            @(negedge clk);
            check(write_busy_out == 0,           "busy low after done");
            check(write_done_out == 0,           "done low after pulse");
            check(write_add_ready  == 1,         "slave AWREADY back high (idle)");
            check(write_data_ready == 0,         "slave WREADY low after burst");
            check(write_resp_valid == 0,         "slave BVALID low after burst");
            repeat (2) @(negedge clk);
            check(slave.mem_wr_en == 0,          "no stray memory write");
            check(mem_wr_cnt - cnt0 == len + 1,  "one mem write per beat");
        end
    endtask

    //-------------------------------------------------------------------
    // READ transaction through the master
    //   stall : cycles the sink holds ready low before every beat
    //           (<0 : sink ready is high the whole time)
    //   poke  : 1 -> pulse start again while busy; must be ignored
    //-------------------------------------------------------------------
    task automatic read_txn;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         stall;
        input                 poke;
        input [8*24:1]        name;

        integer beat, k, cyc;
        reg [DATA_WIDTH-1:0] held, expected;
        reg stable;
        begin
            $display("");
            $display("-- READ  %0s : addr=%0d len=%0d stall=%0d poke=%0d",
                     name, addr, len, stall, poke);

            // ---- start ----
            @(negedge clk);
            while (read_busy_out) @(negedge clk);
            read_add_out    = addr;
            read_length_out = len;
            start_read_out  = 1;
            @(negedge clk);
            start_read_out  = 0;
            read_add_out    = ~addr;        // must have been latched
            read_length_out = ~len;
            check(read_busy_out == 1, "start accepted, busy high");

            if (poke) begin
                read_add_out    = addr ^ 4'h5;
                read_length_out = len  ^ 4'h3;
                start_read_out  = 1;
                @(negedge clk);
                start_read_out  = 0;
                read_add_out    = ~addr;
                read_length_out = ~len;
            end

            // ---- data to the outside sink ----
            if (stall < 0) begin
                read_data_ready_out = 1;
                for (beat = 0; beat <= len; beat = beat + 1) begin
                    @(posedge clk);
                    while (!read_data_valid_out) @(posedge clk);
                    expected = ref_mem[(addr + beat) % ADD_NUM];
                    if (read_data_out === expected ||
                        (ovl_en && read_data_out === old_mem[(addr + beat) % ADD_NUM]))
                        $display("  PASS: beat %0d RDATA=%h", beat, read_data_out);
                    else begin
                        $display("  FAIL: beat %0d RDATA=%h expected %h", beat, read_data_out, expected);
                        errors = errors + 1;
                    end
                    checks = checks + 1;
                    check(read_data_last_out == (beat == len), "RLAST only on last beat");
                end
                @(negedge clk);
                read_data_ready_out = 0;
            end
            else begin
                for (beat = 0; beat <= len; beat = beat + 1) begin
                    while (!read_data_valid_out) @(negedge clk);

                    expected = ref_mem[(addr + beat) % ADD_NUM];
                    held     = read_data_out;
                    stable   = 1;
                    for (k = 0; k < stall; k = k + 1) begin
                        @(negedge clk);
                        if (!read_data_valid_out || read_data_out !== held) stable = 0;
                    end
                    if (stall > 0) check(stable, "back-pressure: RVALID/RDATA stable");

                    read_data_ready_out = 1;
                    if (read_data_out === expected ||
                        (ovl_en && read_data_out === old_mem[(addr + beat) % ADD_NUM]))
                        $display("  PASS: beat %0d RDATA=%h", beat, read_data_out);
                    else begin
                        $display("  FAIL: beat %0d RDATA=%h expected %h", beat, read_data_out, expected);
                        errors = errors + 1;
                    end
                    checks = checks + 1;
                    check(read_data_last_out == (beat == len), "RLAST only on last beat");

                    @(posedge clk);
                    @(negedge clk);
                    read_data_ready_out = 0;
                    if (poke && beat == 0 && len != 0) begin
                        read_add_out    = addr ^ 4'h5;
                        read_length_out = len  ^ 4'h3;
                        start_read_out  = 1;
                        @(negedge clk);
                        start_read_out  = 0;
                        read_add_out    = ~addr;
                        read_length_out = ~len;
                    end
                end
            end

            // ---- wait for done ----
            cyc = 0;
            while (!read_done_out && cyc < 2000) begin
                @(negedge clk);
                cyc = cyc + 1;
            end
            check(read_done_out == 1,            "read_done pulse seen");
            check(read_busy_out == 1,            "busy still high at done");
            check(read_data_valid_out == 0,      "user RVALID low at done");
            check(read_error_out === 1'b0,       "read_error low (RRESP/RLAST okay)");
            @(negedge clk);
            check(read_busy_out == 0,            "busy low after done");
            check(read_done_out == 0,            "done low after pulse");
            k = 0;
            while (!read_add_ready && k < 5) begin
                @(negedge clk);
                k = k + 1;
            end
            check(read_add_ready == 1,           "slave ARREADY back high (idle)");
        end
    endtask

    //-------------------------------------------------------------------
    // Test sequence
    //-------------------------------------------------------------------
    integer r, ra, la, rb, lr;
    integer s_src, s_gap, s_stall, s_poke, s_dly, m;

    initial begin
        errors = 0; checks = 0; burst_id = 0; mon_en = 0;
        ovl_en = 0;
        if (!$value$plusargs("SEED=%d", rseed)) rseed = 1;
        $display("Random seed = %0d  (override with +SEED=<n>)", rseed);
        mem_wr_cnt = 0; w_hs_cnt = 0;
        p_awv = 0; p_awr = 0; p_aw = 0; p_awl = 0;
        p_wv  = 0; p_wr  = 0; p_w  = 0; p_wl  = 0;
        p_bv  = 0; p_br  = 0; p_b  = 0;
        p_arv = 0; p_arr = 0; p_ar = 0; p_arl = 0;
        p_rv  = 0; p_rr  = 0; p_r  = 0; p_rl  = 0; p_rresp = 0;
        p_wdone = 0; p_rdone = 0;

        rst = 0;
        start_write_out = 0; write_add_out = 0; write_length_out = 0;
        write_data_out = 0;  write_data_valid_out = 0;
        start_read_out = 0;  read_add_out = 0; read_length_out = 0;
        read_data_ready_out = 0;

        for (i = 0; i < ADD_NUM; i = i + 1) begin
            slave.memory[i] = 32'hA000_0000 + i;
            ref_mem[i]      = 32'hA000_0000 + i;
        end

        $display("\n===== Reset =====");
        apply_reset;
        mon_en = 1;

        //---------------------------------------------------------------
        $display("\n===== Preloaded memory, read only =====");
        read_txn(4'd3,  4'd0,  0, 0, "R1 single beat");
        read_txn(4'd4,  4'd3,  0, 0, "R2 burst x4");
        read_txn(4'd8,  4'd3,  3, 0, "R3 burst x4 + stall");
        read_txn(4'd10, 4'd4, -1, 0, "R4 RREADY always high");

        //---------------------------------------------------------------
        $display("\n===== Writes =====");
        write_txn(4'd1,  4'd0,  0, 0, 0, "W1 single beat");        compare_mem("W1");
        write_txn(4'd4,  4'd3,  0, 0, 0, "W2 burst x4");           compare_mem("W2");
        write_txn(4'd3,  4'd3,  5, 0, 0, "W3 late first beat");    compare_mem("W3");
        write_txn(4'd12, 4'd3,  0, 2, 0, "W4 gaps between beats"); compare_mem("W4");
        write_txn(4'd9,  4'd4,  3, 1, 0, "W5 late + gaps");        compare_mem("W5");
        write_txn(4'd14, 4'd3,  0, 0, 0, "W6 addr wrap");          compare_mem("W6");
        write_txn(4'd0,  4'd15, 0, 0, 0, "W7 burst x16");          compare_mem("W7");
        write_txn(4'd5,  4'd15, 0, 1, 0, "W8 x16 wrap + gaps");    compare_mem("W8");
        write_txn(4'd12, 4'd0,  0, 0, 0, "W9a back-to-back");
        write_txn(4'd13, 4'd0,  0, 0, 0, "W9b back-to-back");      compare_mem("W9");
        write_txn(4'd7,  4'd2,  0, 0, 1, "W10 start while busy");  compare_mem("W10");

        //---------------------------------------------------------------
        $display("\n===== Reads =====");
        read_txn(4'd14, 4'd3,  0, 0, "R5 addr wrap");
        read_txn(4'd0,  4'd15, 0, 0, "R6 burst x16");
        read_txn(4'd9,  4'd15, 1, 0, "R7 x16 wrap + stalls");
        read_txn(4'd3,  4'd0,  0, 0, "R8a back-to-back");
        read_txn(4'd9,  4'd0,  0, 0, "R8b back-to-back");
        read_txn(4'd5,  4'd2,  0, 1, "R9 start while busy");

        //---------------------------------------------------------------
        $display("\n===== Write then read back (full master -> slave -> master path) =====");
        write_txn(4'd2,  4'd5,  0, 0, 0, "WR1 write");
        read_txn (4'd2,  4'd5,  0, 0,    "WR1 read back");
        write_txn(4'd13, 4'd5,  1, 0, 0, "WR2 write (wraps)");
        read_txn (4'd13, 4'd5,  2, 0,    "WR2 read back");
        write_txn(4'd7,  4'd0,  0, 0, 0, "WR3 write one");
        write_txn(4'd7,  4'd0,  0, 0, 0, "WR3 overwrite same addr");
        read_txn (4'd7,  4'd0,  0, 0,    "WR3 sees latest value");
        write_txn(4'd0,  4'd15, 0, 0, 0, "WR4 full write");
        read_txn (4'd0,  4'd15, 0, 0,    "WR4 full read");
        read_txn (4'd9,  4'd15, 0, 0,    "WR5 full read wrap");
        compare_mem("WR");

        //---------------------------------------------------------------
        $display("\n===== Write and read at the same time (disjoint regions) =====");
        fork
            write_txn(4'd0, 4'd3, 0, 0, 0, "C1 write 0..3");
            read_txn (4'd8, 4'd3, 0, 0,    "C1 read 8..11");
        join
        compare_mem("C1");
        fork
            write_txn(4'd4,  4'd5, 1, 1, 0, "C2 write 4..9");
            read_txn (4'd12, 4'd5, 2, 0,    "C2 read 12..1");
        join
        compare_mem("C2");
        fork
            write_txn(4'd8, 4'd7, 6, 0, 0, "C3 write 8..15");
            read_txn (4'd0, 4'd7, -1, 0,   "C3 read 0..7");
        join
        compare_mem("C3");
        read_txn(4'd8, 4'd7, 0, 0, "C3 read back 8..15");

        //---------------------------------------------------------------
        // Same-address overlap: write and read hit the SAME region at once.
        // Outcome of each read beat depends on timing, so a beat may return the
        // OLD or the NEW value (never anything else).  The write result must be
        // unaffected, and the following clean read must see the new data.
        //---------------------------------------------------------------
        $display("\n===== Same-address read/write overlap =====");
        // read start delay swept so the read starts before / with / after the write
        for (r = 0; r < 10; r = r + 1) begin
            for (m = 0; m < ADD_NUM; m = m + 1) old_mem[m] = ref_mem[m];
            ovl_en = 1;
            fork
                write_txn(4'd4, 4'd7, 0, 0, 0, "OV write 4..11");
                begin
                    repeat (r) @(negedge clk);
                    read_txn(4'd4, 4'd7, 0, 0, "OV read  4..11");
                end
            join
            ovl_en = 0;
            compare_mem("OV");
            read_txn(4'd4, 4'd7, 0, 0, "OV clean read back");
        end
        // partial overlap, wrap-around, with stalls / gaps
        for (r = 0; r < 6; r = r + 1) begin
            for (m = 0; m < ADD_NUM; m = m + 1) old_mem[m] = ref_mem[m];
            ovl_en = 1;
            fork
                write_txn(4'd12, 4'd5, 1, 1, 0, "OV2 write 12..1");
                begin
                    repeat (r) @(negedge clk);
                    read_txn(4'd14, 4'd5, r % 3, 0, "OV2 read  14..3");
                end
            join
            ovl_en = 0;
            compare_mem("OV2");
            read_txn(4'd12, 4'd5, 0, 0, "OV2 clean read back");
        end
        // single-address collision
        for (r = 0; r < 6; r = r + 1) begin
            for (m = 0; m < ADD_NUM; m = m + 1) old_mem[m] = ref_mem[m];
            ovl_en = 1;
            fork
                write_txn(4'd9, 4'd0, 0, 0, 0, "OV3 write 9");
                begin
                    repeat (r) @(negedge clk);
                    read_txn(4'd9, 4'd0, 0, 0, "OV3 read  9");
                end
            join
            ovl_en = 0;
            compare_mem("OV3");
        end
        // random overlapping bursts
        for (r = 0; r < 40; r = r + 1) begin
            ra = rnd(ADD_NUM); la = rnd(ADD_NUM); lr = rnd(ADD_NUM);
            rb = (ra + rnd(ADD_NUM)) % ADD_NUM;
            s_src = rnd(4); s_gap = rnd(3); s_stall = rnd(5) - 1; s_dly = rnd(8);
            for (m = 0; m < ADD_NUM; m = m + 1) old_mem[m] = ref_mem[m];
            ovl_en = 1;
            fork
                write_txn(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], s_src, s_gap, 1'b0, "OVR write");
                begin
                    repeat (s_dly) @(negedge clk);
                    read_txn(rb[ADD_WIDTH-1:0], lr[LEN_WIDTH-1:0], s_stall, 1'b0, "OVR read");
                end
            join
            ovl_en = 0;
            compare_mem("OVR");
        end

        //---------------------------------------------------------------
        $display("\n===== Reset in the middle of a write burst =====");
        @(negedge clk);
        write_add_out = 4'd5; write_length_out = 4'd7; start_write_out = 1;
        @(negedge clk);
        start_write_out = 0;
        write_data_out = 32'h1111_1111; write_data_valid_out = 1;
        repeat (4) @(negedge clk);
        apply_reset;
        resync_ref;
        write_txn(4'd3, 4'd3, 0, 0, 0, "RST1 write after reset");
        compare_mem("RST1");
        read_txn (4'd3, 4'd3, 0, 0,    "RST1 read after reset");

        $display("\n===== Reset in the middle of a read burst =====");
        @(negedge clk);
        read_add_out = 4'd2; read_length_out = 4'd9; start_read_out = 1;
        @(negedge clk);
        start_read_out = 0;
        read_data_ready_out = 0;
        while (!read_data_valid_out) @(negedge clk);
        repeat (2) @(negedge clk);
        apply_reset;
        read_txn (4'd2, 4'd9, 0, 0,    "RST2 read after reset");
        write_txn(4'd6, 4'd2, 0, 0, 0, "RST2 write after reset");
        compare_mem("RST2");

        //---------------------------------------------------------------
        $display("\n===== Randomized sequential transactions =====");
        for (r = 0; r < 40; r = r + 1) begin
            ra = rnd(ADD_NUM);
            la = rnd(ADD_NUM);
            s_src = rnd(4); s_gap = rnd(3);
            s_stall = rnd(5) - 1; s_poke = rnd(2);
            write_txn(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], s_src, s_gap, s_poke[0], "RND write");
            compare_mem("RND");
            s_poke = rnd(2);
            read_txn (ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], s_stall, s_poke[0], "RND read back");
        end

        $display("\n===== Randomized concurrent transactions (disjoint, <=8 beats) =====");
        for (r = 0; r < 40; r = r + 1) begin
            ra = rnd(ADD_NUM);
            la = rnd(8);
            rb = (ra + 8) % ADD_NUM;
            lr = rnd(8);
            s_src = rnd(4); s_gap = rnd(3); s_stall = rnd(5) - 1;
            fork
                write_txn(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], s_src, s_gap, 1'b0, "RNDC write");
                read_txn (rb[ADD_WIDTH-1:0], lr[LEN_WIDTH-1:0], s_stall, 1'b0,      "RNDC read");
            join
            compare_mem("RNDC");
        end

        //---------------------------------------------------------------
        #50;
        $display("\n==================================================");
        if (errors == 0)
            $display("   SIMULATION FINISHED - ALL PASS (%0d checks)", checks);
        else
            $display("   SIMULATION FINISHED - %0d FAILURE(S) (%0d checks)", errors, checks);
        $display("==================================================\n");
        $finish;
    end

endmodule