`timescale 1ns/1ps
//=============================================================================
// tb_axi4_slave : self-checking testbench for the whole AXI4 slave
//   (axi4_write + axi4_read + shared memory).
//
//  - rst is ACTIVE-LOW
//  - burst length field: beats = length + 1
//  - inputs driven on negedge, DUT outputs sampled at posedge / negedge
//  - ref_mem is an independent golden model of the shared memory
//  - write and read channels are also run CONCURRENTLY on disjoint regions
//=============================================================================
module tb_axi4_slave;

    parameter DATA_WIDTH = 32;
    parameter ADD_WIDTH  = 4;
    parameter LEN_WIDTH  = 4;
    parameter ADD_NUM    = 16;

    //-------------------------------------------------------------------
    // Signals
    //-------------------------------------------------------------------
    reg                    clk;
    reg                    rst;

    reg  [ADD_WIDTH-1:0]   write_add;
    reg                    write_add_valid;
    wire                   write_add_ready;
    reg  [LEN_WIDTH-1:0]   write_add_length;

    reg  [DATA_WIDTH-1:0]  write_data;
    reg                    write_data_valid;
    wire                   write_data_ready;
    reg                    write_data_last;

    wire                   write_resp;
    wire                   write_resp_valid;
    reg                    write_resp_ready;

    reg  [ADD_WIDTH-1:0]   read_add;
    reg                    read_add_valid;
    wire                   read_add_ready;
    reg  [LEN_WIDTH-1:0]   read_add_length;

    wire [DATA_WIDTH-1:0]  read_data;
    wire                   read_data_valid;
    wire                   read_data_resp;
    reg                    read_data_ready;
    wire                   read_data_last;

    //-------------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------------
    axi4_slave #(
        .data_width (DATA_WIDTH),
        .add_width  (ADD_WIDTH),
        .len_width  (LEN_WIDTH),
        .add_num    (ADD_NUM)
    ) dut (
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
        $dumpfile("axi4_slave_tb.vcd");
        $dumpvars(0, tb_axi4_slave);
    end

    initial begin
        #2000000;
        $display("TIMEOUT - DUT stuck");
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
    reg [DATA_WIDTH-1:0] old_mem [0:ADD_NUM-1];   // snapshot for same-address overlap test
    integer pat_mode;       // 0 = hashed data, 1 = corner patterns, 2 = walking ones
    reg     ovl_en;         // overlap test: a read may return the old OR the new value
    reg     busy_w;         // AWREADY must stay low while a pipelined AW is waiting
    reg     busy_r;         // ARREADY must stay low while a pipelined AR is waiting

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
            case (pat_mode)
                1: case (beat % 4)
                       0: data_of = 32'hFFFF_FFFF;
                       1: data_of = 32'h0000_0000;
                       2: data_of = 32'hAAAA_AAAA;
                       default: data_of = 32'h5555_5555;
                   endcase
                2: data_of = 32'h1 << (beat % 32);
                default: data_of = seed * 32'h9E3779B1 + beat * 32'h01010101 + 32'h5A5A0000;
            endcase
        end
    endfunction

    //-------------------------------------------------------------------
    // Monitors (run all the time)
    //-------------------------------------------------------------------
    integer w_beats;        // W handshakes, cleared by write_burst
    integer mem_wr_cnt;     // cycles with mem_wr_en (global)

    always @(posedge clk) begin
        if (rst && write_data_valid && write_data_ready) w_beats    <= w_beats + 1;
        if (dut.mem_wr_en)                               mem_wr_cnt <= mem_wr_cnt + 1;
    end

    // VALID must stay high and payload stable until READY (B and R channels)
    reg        p_bvalid, p_bready, p_bresp;
    reg        p_rvalid, p_rready, p_rlast, p_rresp;
    reg [DATA_WIDTH-1:0] p_rdata;
    reg        mon_en;
    reg        p_rst;

    always @(posedge clk) begin
        if (mon_en && rst && p_rst) begin   // p_rst: previous edge was not a reset edge
            if (p_bvalid && !p_bready) begin
                if (!write_resp_valid || write_resp !== p_bresp) begin
                    $display("  FAIL: B channel not stable under back-pressure (t=%0t)", $time);
                    errors = errors + 1;
                end
            end
            if (p_rvalid && !p_rready) begin
                if (!read_data_valid || read_data !== p_rdata ||
                    read_data_last !== p_rlast || read_data_resp !== p_rresp) begin
                    $display("  FAIL: R channel not stable under back-pressure (t=%0t)", $time);
                    errors = errors + 1;
                end
            end
            // static protocol rules
            if (write_add_ready && write_data_ready) begin
                $display("  FAIL: AWREADY and WREADY high together (t=%0t)", $time);
                errors = errors + 1;
            end
            if (read_add_ready && read_data_valid) begin
                $display("  FAIL: ARREADY high while RVALID (t=%0t)", $time);
                errors = errors + 1;
            end
            if (busy_w && write_add_ready) begin
                $display("  FAIL: AWREADY high while a burst is in flight (t=%0t)", $time);
                errors = errors + 1;
            end
            if (busy_r && read_add_ready) begin
                $display("  FAIL: ARREADY high while a burst is in flight (t=%0t)", $time);
                errors = errors + 1;
            end
            if (write_add_ready && write_resp_valid && !p_bvalid) begin
                $display("  FAIL: AWREADY high while BVALID (t=%0t)", $time);
                errors = errors + 1;
            end
        end
        p_rst    <= rst;
        p_bvalid <= write_resp_valid; p_bready <= write_resp_ready; p_bresp <= write_resp;
        p_rvalid <= read_data_valid;  p_rready <= read_data_ready;  p_rdata <= read_data;
        p_rlast  <= read_data_last;   p_rresp  <= read_data_resp;
    end

    //-------------------------------------------------------------------
    // Reset task
    //-------------------------------------------------------------------
    task apply_reset;
        begin
            @(negedge clk);
            rst              = 0;
            write_add        = 0;  write_add_valid  = 0;  write_add_length = 0;
            write_data       = 0;  write_data_valid = 0;  write_data_last  = 0;
            write_resp_ready = 0;
            read_add         = 0;  read_add_valid   = 0;  read_add_length  = 0;
            read_data_ready  = 0;
            repeat (2) @(posedge clk);
            #1;
            check(write_add_ready  == 1, "reset: AWREADY high");
            check(write_data_ready == 0, "reset: WREADY low");
            check(write_resp_valid == 0, "reset: BVALID low");
            check(dut.mem_wr_en    == 0, "reset: mem_wr_en low");
            check(read_add_ready   == 1, "reset: ARREADY high");
            check(read_data_valid  == 0, "reset: RVALID low");
            @(negedge clk);
            rst = 1;
        end
    endtask

    // copy the DUT memory into the golden model (after a reset mid-burst)
    task resync_ref;
        integer m;
        begin
            for (m = 0; m < ADD_NUM; m = m + 1) ref_mem[m] = dut.memory[m];
        end
    endtask

    task compare_mem;
        input [8*24:1] name;
        integer m, bad;
        begin
            bad = 0;
            for (m = 0; m < ADD_NUM; m = m + 1)
                if (dut.memory[m] !== ref_mem[m]) begin
                    $display("  FAIL: memory[%0d]=%h expected %h", m, dut.memory[m], ref_mem[m]);
                    bad = bad + 1;
                end
            check(bad == 0, "memory contents match golden");
            errors = errors + bad;
        end
    endtask

    //-------------------------------------------------------------------
    // WRITE burst
    //   aw_dly     : cycles before AWVALID
    //   w_dly      : cycles between AW handshake and first WVALID
    //   gap        : idle cycles between W beats (<0: random 0..3 per beat)
    //   resp_stall : cycles BREADY is held low after BVALID (<0: BREADY high early)
    //   After the AW handshake the address/length inputs are corrupted
    //   (must have been latched).
    //-------------------------------------------------------------------
    task write_burst;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         aw_dly;
        input integer         w_dly;
        input integer         gap;
        input integer         resp_stall;
        input [8*24:1]        name;

        integer b, n, j, cnt0;
        reg [31:0] seed;
        reg        stable;
        begin
            $display("");
            $display("-- WRITE %0s : addr=%0d len=%0d aw_dly=%0d w_dly=%0d gap=%0d stall=%0d",
                     name, addr, len, aw_dly, w_dly, gap, resp_stall);

            burst_id = burst_id + 1;
            seed     = burst_id;
            for (j = 0; j <= len; j = j + 1)
                ref_mem[(addr + j) % ADD_NUM] = data_of(seed, j);

            cnt0   = mem_wr_cnt;
            w_beats = 0;

            // ---- AW ----
            repeat (aw_dly) @(negedge clk);
            @(negedge clk);
            while (!write_add_ready) @(negedge clk);
            write_add        = addr;
            write_add_length = len;
            write_add_valid  = 1;
            @(posedge clk);                       // handshake
            @(negedge clk);
            write_add_valid  = 0;
            write_add        = ~addr;             // must be latched
            write_add_length = ~len;
            check(write_add_ready == 0, "AW handshake, AWREADY drops");

            if (resp_stall < 0) write_resp_ready = 1;

            // ---- W ----
            repeat (w_dly) @(negedge clk);
            for (b = 0; b <= len; b = b + 1) begin
                write_data       = data_of(seed, b);
                write_data_valid = 1;
                write_data_last  = (b == len);
                @(posedge clk);
                while (!write_data_ready) @(posedge clk);
                @(negedge clk);
                write_data_valid = 0;
                write_data_last  = 0;
                write_data       = ~data_of(seed, b);   // must not be re-sampled
                if (b < len) repeat ((gap < 0) ? ($urandom % 4) : gap) @(negedge clk);
            end

            // ---- B ----
            if (resp_stall < 0) begin
                // BREADY already high; BVALID is up now, handshake on next posedge
                while (!write_resp_valid) @(negedge clk);
                check(w_beats == len + 1, "BVALID only after all beats");
                check(write_resp == 1'b1, "BRESP okay");
                @(posedge clk);
                @(negedge clk);
                write_resp_ready = 0;
            end
            else begin
                while (!write_resp_valid) @(negedge clk);
                check(w_beats == len + 1, "BVALID only after all beats");
                check(write_resp == 1'b1, "BRESP okay");
                stable = 1;
                for (n = 0; n < resp_stall; n = n + 1) begin
                    @(negedge clk);
                    if (!write_resp_valid || write_resp !== 1'b1) stable = 0;
                end
                if (resp_stall > 0) check(stable, "back-pressure: BVALID/BRESP stable");
                write_resp_ready = 1;
                @(posedge clk);
                @(negedge clk);
                write_resp_ready = 0;
            end

            // ---- completion ----
            check(write_resp_valid == 0, "BVALID low after handshake");
            check(write_data_ready == 0, "WREADY low after burst");
            check(write_add_ready  == 1, "AWREADY back high (idle)");
            repeat (2) @(negedge clk);
            check(dut.mem_wr_en == 0,              "no stray memory write");
            check(mem_wr_cnt - cnt0 == len + 1,    "one mem write per beat");
        end
    endtask

    //-------------------------------------------------------------------
    // READ burst
    //   ar_dly : cycles before ARVALID
    //   stall  : cycles RREADY is held low before every beat (<0: random 0..3 per beat)
    //-------------------------------------------------------------------
    task read_burst;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         ar_dly;
        input integer         stall;
        input [8*24:1]        name;

        integer beat, k, st;
        reg [DATA_WIDTH-1:0] held, expected;
        reg stable;
        begin
            $display("");
            $display("-- READ  %0s : addr=%0d len=%0d ar_dly=%0d stall=%0d",
                     name, addr, len, ar_dly, stall);

            repeat (ar_dly) @(negedge clk);
            @(negedge clk);
            while (!read_add_ready) @(negedge clk);
            read_add        = addr;
            read_add_length = len;
            read_add_valid  = 1;
            @(posedge clk);                       // handshake
            @(negedge clk);
            read_add_valid  = 0;
            read_add        = ~addr;              // must be latched
            read_add_length = ~len;
            check(read_add_ready == 0, "AR handshake, ARREADY drops");

            for (beat = 0; beat <= len; beat = beat + 1) begin
                while (!read_data_valid) @(negedge clk);

                expected = ref_mem[(addr + beat) % ADD_NUM];
                held     = read_data;
                stable   = 1;
                st       = (stall < 0) ? ($urandom % 4) : stall;
                for (k = 0; k < st; k = k + 1) begin
                    @(negedge clk);
                    if (!read_data_valid || read_data !== held) stable = 0;
                end
                if (st > 0) check(stable, "back-pressure: RVALID/RDATA stable");

                read_data_ready = 1;
                if (read_data === expected ||
                    (ovl_en && read_data === old_mem[(addr + beat) % ADD_NUM]))
                    $display("  PASS: beat %0d RDATA=%h", beat, read_data);
                else begin
                    $display("  FAIL: beat %0d RDATA=%h expected %h", beat, read_data, expected);
                    errors = errors + 1;
                end
                checks = checks + 1;
                check(read_data_resp == 1'b1,         "RRESP okay");
                check(read_data_last == (beat == len), "RLAST only on last beat");
                check(read_add_ready == 0,            "ARREADY low during burst");

                @(posedge clk);                   // data handshake
                @(negedge clk);
                read_data_ready = 0;
            end

            check(read_data_valid == 0, "RVALID low after last beat");
            k = 0;
            while (!read_add_ready && k < 5) begin
                @(negedge clk);
                k = k + 1;
            end
            check(read_add_ready == 1, "ARREADY back high (idle)");
        end
    endtask


    //-------------------------------------------------------------------
    // Extra task: AW handshake + n W beats, no B handling (for reset tests)
    //-------------------------------------------------------------------
    task raw_write;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         nbeats;
        integer b;
        begin
            @(negedge clk);
            while (!write_add_ready) @(negedge clk);
            write_add = addr; write_add_length = len; write_add_valid = 1;
            @(posedge clk);
            @(negedge clk);
            write_add_valid = 0; write_add = ~addr; write_add_length = ~len;
            for (b = 0; b < nbeats; b = b + 1) begin
                write_data = 32'hC0DE_0000 + b; write_data_valid = 1; write_data_last = (b == len);
                @(posedge clk);
                while (!write_data_ready) @(posedge clk);
                @(negedge clk);
                write_data_valid = 0; write_data_last = 0;
            end
        end
    endtask

    // reset held for exactly one clock edge
    task short_reset;
        begin
            @(negedge clk);
            rst = 0;
            write_add_valid = 0; write_data_valid = 0; write_data_last = 0; write_resp_ready = 0;
            read_add_valid  = 0; read_data_ready = 0;
            @(posedge clk);
            #1;
            check(write_add_ready  == 1, "1-cycle reset: AWREADY high");
            check(write_data_ready == 0, "1-cycle reset: WREADY low");
            check(write_resp_valid == 0, "1-cycle reset: BVALID low");
            check(read_add_ready   == 1, "1-cycle reset: ARREADY high");
            check(read_data_valid  == 0, "1-cycle reset: RVALID low");
            @(negedge clk);
            rst = 1;
        end
    endtask

    // nothing may happen while the bus is idle
    task idle_watch;
        input integer n;
        integer q, bad;
        begin
            bad = 0;
            for (q = 0; q < n; q = q + 1) begin
                @(negedge clk);
                if (write_resp_valid || read_data_valid || write_data_ready ||
                    dut.mem_wr_en || !write_add_ready || !read_add_ready) bad = bad + 1;
            end
            check(bad == 0, "bus quiet while idle");
        end
    endtask

    //-------------------------------------------------------------------
    // Extra task: WVALID raised BEFORE the AW handshake.
    //   WREADY must stay low and nothing may be written until AW is accepted;
    //   the waiting beat is then taken as beat 0.
    //-------------------------------------------------------------------
    task write_burst_early_w;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         early;
        input [8*24:1]        name;

        integer b, j, q, cnt0;
        reg [31:0] seed;
        begin
            $display("");
            $display("-- WRITE %0s : addr=%0d len=%0d WVALID %0d cycles before AW", name, addr, len, early);
            burst_id = burst_id + 1;
            seed     = burst_id;
            for (j = 0; j <= len; j = j + 1)
                ref_mem[(addr + j) % ADD_NUM] = data_of(seed, j);
            cnt0    = mem_wr_cnt;
            w_beats = 0;

            @(negedge clk);
            while (!write_add_ready) @(negedge clk);
            write_data       = data_of(seed, 0);
            write_data_valid = 1;
            write_data_last  = (len == 0);
            for (q = 0; q < early; q = q + 1) begin
                @(negedge clk);
                check(write_data_ready == 0, "WREADY low before AW accepted");
                check(dut.mem_wr_en    == 0, "no memory write before AW");
            end
            check(w_beats == 0, "no W beat accepted before AW");

            write_add = addr; write_add_length = len; write_add_valid = 1;
            @(posedge clk);
            @(negedge clk);
            write_add_valid = 0; write_add = ~addr; write_add_length = ~len;

            for (b = 0; b <= len; b = b + 1) begin
                write_data       = data_of(seed, b);
                write_data_valid = 1;
                write_data_last  = (b == len);
                @(posedge clk);
                while (!write_data_ready) @(posedge clk);
                @(negedge clk);
                write_data_valid = 0; write_data_last = 0;
                write_data = ~data_of(seed, b);
            end

            while (!write_resp_valid) @(negedge clk);
            check(w_beats == len + 1, "BVALID only after all beats");
            write_resp_ready = 1;
            @(posedge clk);
            @(negedge clk);
            write_resp_ready = 0;
            check(write_add_ready == 1, "AWREADY back high (idle)");
            repeat (2) @(negedge clk);
            check(mem_wr_cnt - cnt0 == len + 1, "one mem write per beat");
        end
    endtask

    //-------------------------------------------------------------------
    // Extra task: AWVALID of burst 2 is raised and HELD while burst 1 is in
    //   flight. AWREADY must stay low until burst 1's B handshake, then burst 2
    //   must be accepted and complete correctly.
    //-------------------------------------------------------------------
    task write_pipelined;
        input [ADD_WIDTH-1:0] a1;
        input [LEN_WIDTH-1:0] l1;
        input [ADD_WIDTH-1:0] a2;
        input [LEN_WIDTH-1:0] l2;
        input integer         resp_stall;
        input [8*24:1]        name;

        integer p, b, n, j, cnt0;
        reg [ADD_WIDTH-1:0] a_p;
        reg [LEN_WIDTH-1:0] l_p;
        reg [31:0] seed1, seed2, seed_p;
        begin
            $display("");
            $display("-- WRITE %0s : (%0d,len %0d) then held AW (%0d,len %0d)", name, a1, l1, a2, l2);
            burst_id = burst_id + 1; seed1 = burst_id;
            burst_id = burst_id + 1; seed2 = burst_id;
            for (j = 0; j <= l1; j = j + 1) ref_mem[(a1 + j) % ADD_NUM] = data_of(seed1, j);
            for (j = 0; j <= l2; j = j + 1) ref_mem[(a2 + j) % ADD_NUM] = data_of(seed2, j);
            cnt0 = mem_wr_cnt;

            for (p = 0; p < 2; p = p + 1) begin
                a_p    = p ? a2 : a1;
                l_p    = p ? l2 : l1;
                seed_p = p ? seed2 : seed1;

                if (p == 0) begin
                    @(negedge clk);
                    while (!write_add_ready) @(negedge clk);
                    write_add = a_p; write_add_length = l_p; write_add_valid = 1;
                    @(posedge clk);
                    @(negedge clk);
                    // present the next AW right away and keep it up
                    write_add = a2; write_add_length = l2; write_add_valid = 1;
                    busy_w = 1;
                end
                else begin
                    @(posedge clk);                       // held AW handshake
                    while (!write_add_ready) @(posedge clk);
                    @(negedge clk);
                    write_add_valid = 0; write_add = ~a2; write_add_length = ~l2;
                end
                w_beats = 0;

                for (b = 0; b <= l_p; b = b + 1) begin
                    write_data = data_of(seed_p, b); write_data_valid = 1; write_data_last = (b == l_p);
                    @(posedge clk);
                    while (!write_data_ready) @(posedge clk);
                    @(negedge clk);
                    write_data_valid = 0; write_data_last = 0; write_data = ~data_of(seed_p, b);
                end

                while (!write_resp_valid) @(negedge clk);
                check(w_beats == l_p + 1, "BVALID only after all beats");
                for (n = 0; n < resp_stall; n = n + 1) @(negedge clk);
                write_resp_ready = 1;
                @(posedge clk);
                @(negedge clk);
                write_resp_ready = 0;
                if (p == 0) busy_w = 0;
            end
            check(write_add_ready == 1, "AWREADY back high (idle)");
            repeat (2) @(negedge clk);
            check(mem_wr_cnt - cnt0 == l1 + l2 + 2, "one mem write per beat (both bursts)");
        end
    endtask

    //-------------------------------------------------------------------
    // Extra task: ARVALID of burst 2 held while burst 1 is being read.
    //-------------------------------------------------------------------
    task read_pipelined;
        input [ADD_WIDTH-1:0] a1;
        input [LEN_WIDTH-1:0] l1;
        input [ADD_WIDTH-1:0] a2;
        input [LEN_WIDTH-1:0] l2;
        input integer         stall;
        input [8*24:1]        name;

        integer p, beat, k;
        reg [ADD_WIDTH-1:0] a_p;
        reg [LEN_WIDTH-1:0] l_p;
        begin
            $display("");
            $display("-- READ  %0s : (%0d,len %0d) then held AR (%0d,len %0d)", name, a1, l1, a2, l2);
            for (p = 0; p < 2; p = p + 1) begin
                a_p = p ? a2 : a1;
                l_p = p ? l2 : l1;

                if (p == 0) begin
                    @(negedge clk);
                    while (!read_add_ready) @(negedge clk);
                    read_add = a_p; read_add_length = l_p; read_add_valid = 1;
                    @(posedge clk);
                    @(negedge clk);
                    read_add = a2; read_add_length = l2; read_add_valid = 1;   // held
                    busy_r = 1;
                end
                else begin
                    @(posedge clk);
                    while (!read_add_ready) @(posedge clk);
                    @(negedge clk);
                    read_add_valid = 0; read_add = ~a2; read_add_length = ~l2;
                end

                for (beat = 0; beat <= l_p; beat = beat + 1) begin
                    while (!read_data_valid) @(negedge clk);
                    for (k = 0; k < stall; k = k + 1) @(negedge clk);
                    read_data_ready = 1;
                    if (read_data === ref_mem[(a_p + beat) % ADD_NUM])
                        $display("  PASS: beat %0d RDATA=%h", beat, read_data);
                    else begin
                        $display("  FAIL: beat %0d RDATA=%h expected %h", beat, read_data,
                                 ref_mem[(a_p + beat) % ADD_NUM]);
                        errors = errors + 1;
                    end
                    checks = checks + 1;
                    check(read_data_last == (beat == l_p), "RLAST only on last beat");
                    @(posedge clk);
                    @(negedge clk);
                    read_data_ready = 0;
                end
                if (p == 0) busy_r = 0;
            end
            check(read_data_valid == 0, "RVALID low after last beat");
        end
    endtask

    //-------------------------------------------------------------------
    // Test sequence
    //-------------------------------------------------------------------
    integer r, ra, la, rb, lr;
    integer s_w, s_g, s_b, s_r, s_ar;
    integer m;

    initial begin
        errors = 0; checks = 0; burst_id = 0;
        w_beats = 0; mem_wr_cnt = 0; mon_en = 0;
        pat_mode = 0; ovl_en = 0; busy_w = 0; busy_r = 0;
        p_bvalid = 0; p_bready = 0; p_bresp = 0; p_rst = 0;
        p_rvalid = 0; p_rready = 0; p_rdata = 0; p_rlast = 0; p_rresp = 0;

        rst = 0;
        write_add = 0; write_add_valid = 0; write_add_length = 0;
        write_data = 0; write_data_valid = 0; write_data_last = 0;
        write_resp_ready = 0;
        read_add = 0; read_add_valid = 0; read_add_length = 0;
        read_data_ready = 0;

        for (i = 0; i < ADD_NUM; i = i + 1) begin
            dut.memory[i] = 32'hA000_0000 + i;
            ref_mem[i]    = 32'hA000_0000 + i;
        end

        $display("\n===== Reset =====");
        apply_reset;
        mon_en = 1;

        //---------------------------------------------------------------
        $display("\n===== Preloaded memory, read only =====");
        read_burst(4'd3,  4'd0,  0, 0, "R1 single beat");
        read_burst(4'd4,  4'd3,  0, 0, "R2 burst x4");
        read_burst(4'd8,  4'd3,  0, 3, "R3 burst x4 + stall");

        //---------------------------------------------------------------
        $display("\n===== Write bursts (checked against golden memory) =====");
        write_burst(4'd1,  4'd0,  0, 0, 0,  0, "W1 single beat");       compare_mem("W1");
        write_burst(4'd6,  4'd2,  0, 0, 0,  5, "W2 resp stall");        compare_mem("W2");
        write_burst(4'd4,  4'd3,  0, 0, 0,  0, "W3 burst x4");          compare_mem("W3");
        write_burst(4'd8,  4'd3,  4, 0, 0,  0, "W4 late AW");           compare_mem("W4");
        write_burst(4'd2,  4'd3,  0, 5, 0,  0, "W5 late W");            compare_mem("W5");
        write_burst(4'd10, 4'd3,  0, 0, 2,  0, "W6 W gaps");            compare_mem("W6");
        write_burst(4'd3,  4'd1,  0, 0, 0, -1, "W7 early BREADY");      compare_mem("W7");
        write_burst(4'd14, 4'd3,  0, 0, 0,  0, "W8 addr wrap");         compare_mem("W8");
        write_burst(4'd0,  4'd15, 0, 0, 0,  0, "W9 burst x16");         compare_mem("W9");
        write_burst(4'd5,  4'd15, 0, 0, 1,  3, "W10 x16 wrap+gaps");    compare_mem("W10");
        write_burst(4'd9,  4'd4,  3, 1, 1,  2, "W11 mixed");            compare_mem("W11");
        write_burst(4'd12, 4'd0,  0, 0, 0,  0, "W12a back-to-back");
        write_burst(4'd13, 4'd0,  0, 0, 0,  0, "W12b back-to-back");    compare_mem("W12");

        //---------------------------------------------------------------
        $display("\n===== Write then read back through the read channel =====");
        write_burst(4'd2,  4'd5,  0, 0, 0,  0, "WR1 write");
        read_burst (4'd2,  4'd5,  0, 0,          "WR1 read back");
        write_burst(4'd13, 4'd5,  0, 1, 0,  1, "WR2 write (wraps)");
        read_burst (4'd13, 4'd5,  1, 2,          "WR2 read back");
        write_burst(4'd7,  4'd0,  0, 0, 0,  0, "WR3 write one");
        write_burst(4'd7,  4'd0,  0, 0, 0,  0, "WR3 overwrite same addr");
        read_burst (4'd7,  4'd0,  0, 0,          "WR3 sees latest value");
        write_burst(4'd0,  4'd15, 0, 0, 0,  0, "WR4 full write");
        read_burst (4'd0,  4'd15, 0, 0,          "WR4 full read");
        read_burst (4'd9,  4'd15, 0, 1,          "WR5 full read wrap");
        compare_mem("WR");

        //---------------------------------------------------------------
        $display("\n===== Read/write concurrently (disjoint regions) =====");
        // write 0..3 while reading 8..11
        fork
            write_burst(4'd0, 4'd3, 0, 0, 0, 0, "C1 write 0..3");
            read_burst (4'd8, 4'd3, 0, 0,       "C1 read 8..11");
        join
        compare_mem("C1");
        // both with back-pressure / gaps, write 4..9 read 12..1 (wrap)
        fork
            write_burst(4'd4,  4'd5, 1, 1, 1, 3, "C2 write 4..9");
            read_burst (4'd12, 4'd5, 0, 2,       "C2 read 12..1");
        join
        compare_mem("C2");
        // read started long before write
        fork
            write_burst(4'd8, 4'd7, 6, 0, 0, 0, "C3 write 8..15");
            read_burst (4'd0, 4'd7, 0, 1,       "C3 read 0..7");
        join
        compare_mem("C3");
        // read of a region, then the region just written is read back
        read_burst(4'd8, 4'd7, 0, 0, "C3 read back 8..15");

        //---------------------------------------------------------------
        $display("\n===== Reset in the middle of a write burst =====");
        @(negedge clk);
        write_add = 4'd5; write_add_length = 4'd7; write_add_valid = 1;
        @(posedge clk);
        @(negedge clk);
        write_add_valid = 0;
        write_data = 32'h1111_1111; write_data_valid = 1; write_data_last = 0;
        repeat (3) begin
            @(posedge clk);
            while (!write_data_ready) @(posedge clk);
            @(negedge clk);
            write_data = write_data + 32'h1111_1111;
        end
        apply_reset;
        resync_ref;
        write_burst(4'd3, 4'd3, 0, 0, 0, 0, "RST1 write after reset");
        compare_mem("RST1");
        read_burst (4'd3, 4'd3, 0, 0,        "RST1 read after reset");

        $display("\n===== Reset in the middle of a read burst =====");
        @(negedge clk);
        read_add = 4'd2; read_add_length = 4'd9; read_add_valid = 1;
        @(posedge clk);
        @(negedge clk);
        read_add_valid = 0;
        read_data_ready = 0;
        while (!read_data_valid) @(negedge clk);
        repeat (2) @(negedge clk);
        apply_reset;
        read_burst (4'd2, 4'd9, 0, 0, "RST2 read after reset");
        write_burst(4'd6, 4'd2, 0, 0, 0, 0, "RST2 write after reset");
        compare_mem("RST2");

        //---------------------------------------------------------------
        $display("\n===== Randomized sequential bursts =====");
        for (r = 0; r < 25; r = r + 1) begin
            ra = $urandom % ADD_NUM;
            la = $urandom % ADD_NUM;
            s_w = $urandom % 3; s_g = $urandom % 3; s_b = ($urandom % 4) - 1; s_ar = $urandom % 3;
            s_r = $urandom % 3;
            write_burst(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], $urandom % 3, s_w, s_g, s_b, "RND write");
            compare_mem("RND");
            read_burst (ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], s_ar, s_r, "RND read back");
        end

        $display("\n===== Randomized concurrent bursts (disjoint, <=8 beats each) =====");
        for (r = 0; r < 25; r = r + 1) begin
            ra = $urandom % ADD_NUM;
            la = $urandom % 8;
            rb = (ra + 8) % ADD_NUM;
            lr = $urandom % 8;
            s_w = $urandom % 3; s_g = $urandom % 3; s_b = ($urandom % 4) - 1;
            s_ar = $urandom % 4; s_r = $urandom % 3;
            fork
                write_burst(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], $urandom % 3, s_w, s_g, s_b, "RNDC write");
                read_burst (rb[ADD_WIDTH-1:0], lr[LEN_WIDTH-1:0], s_ar, s_r, "RNDC read");
            join
            compare_mem("RNDC");
        end


        //---------------------------------------------------------------
        $display("\n===== EXTRA: idle bus =====");
        idle_watch(20);

        $display("\n===== EXTRA: WVALID before AW =====");
        write_burst_early_w(4'd3,  4'd0, 3, "E1 early W, 1 beat");  compare_mem("E1");
        write_burst_early_w(4'd10, 4'd4, 5, "E2 early W, 5 beats"); compare_mem("E2");
        write_burst_early_w(4'd14, 4'd3, 1, "E3 early W, wrap");    compare_mem("E3");

        $display("\n===== EXTRA: AW / AR held while previous burst in flight =====");
        write_pipelined(4'd0, 4'd3, 4'd8,  4'd3, 0, "P1 AW held");        compare_mem("P1");
        write_pipelined(4'd5, 4'd0, 4'd5,  4'd0, 2, "P2 AW held, same");  compare_mem("P2");
        write_pipelined(4'd12,4'd5, 4'd2,  4'd9, 3, "P3 AW held, wrap");  compare_mem("P3");
        read_pipelined (4'd0, 4'd3, 4'd8,  4'd3, 0, "P4 AR held");
        read_pipelined (4'd6, 4'd0, 4'd6,  4'd0, 2, "P5 AR held, same");
        read_pipelined (4'd13,4'd5, 4'd1,  4'd9, 1, "P6 AR held, wrap");

        $display("\n===== EXTRA: data patterns and address extremes =====");
        pat_mode = 1;
        write_burst(4'd0,  4'd15, 0, 0, 0, 0, "D1 corner patterns");  compare_mem("D1");
        read_burst (4'd0,  4'd15, 0, 0,        "D1 read back");
        pat_mode = 2;
        write_burst(4'd0,  4'd15, 0, 0, 0, 0, "D2 walking ones");     compare_mem("D2");
        read_burst (4'd0,  4'd15, 0, 1,        "D2 read back");
        pat_mode = 0;
        write_burst(4'd15, 4'd0,  0, 0, 0, 0, "D3 last address");     compare_mem("D3");
        read_burst (4'd15, 4'd0,  0, 0,        "D3 read back");
        write_burst(4'd15, 4'd15, 0, 0, 0, 0, "D4 full wrap from 15"); compare_mem("D4");
        read_burst (4'd15, 4'd15, 0, 0,        "D4 read back");

        $display("\n===== EXTRA: concurrent read/write on the SAME addresses =====");
        // a read beat may return the old or the new value, but nothing else
        for (m = 0; m < ADD_NUM; m = m + 1) old_mem[m] = ref_mem[m];
        ovl_en = 1;
        fork
            write_burst(4'd4, 4'd7, 0, 0, 0, 0, "O1 write 4..11");
            read_burst (4'd4, 4'd7, 0, 0,       "O1 read  4..11");
        join
        ovl_en = 0;
        compare_mem("O1");
        for (m = 0; m < ADD_NUM; m = m + 1) old_mem[m] = ref_mem[m];
        ovl_en = 1;
        fork
            write_burst(4'd0, 4'd15, 2, 0, 1, 2, "O2 write 0..15");
            read_burst (4'd8, 4'd15, 0, 1,       "O2 read  8..7");
        join
        ovl_en = 0;
        compare_mem("O2");
        read_burst(4'd0, 4'd15, 0, 0, "O2 final read back");

        $display("\n===== EXTRA: resets =====");
        // reset while BVALID is stalled
        raw_write(4'd9, 4'd1, 2);
        while (!write_resp_valid) @(negedge clk);
        repeat (3) @(negedge clk);
        apply_reset;
        resync_ref;
        idle_watch(5);
        write_burst(4'd9, 4'd1, 0, 0, 0, 0, "X1 write after B-stall rst"); compare_mem("X1");
        read_burst (4'd9, 4'd1, 0, 0,        "X1 read back");
        // one-cycle reset in the middle of a write burst
        raw_write(4'd2, 4'd7, 3);
        short_reset;
        resync_ref;
        write_burst(4'd2, 4'd7, 0, 0, 0, 0, "X2 write after 1-cyc rst"); compare_mem("X2");
        read_burst (4'd2, 4'd7, 0, 0,        "X2 read back");
        // one-cycle reset in the middle of a read burst (RREADY low, RVALID up)
        @(negedge clk);
        read_add = 4'd1; read_add_length = 4'd5; read_add_valid = 1;
        @(posedge clk);
        @(negedge clk);
        read_add_valid = 0;
        while (!read_data_valid) @(negedge clk);
        short_reset;
        read_burst (4'd1, 4'd5, 0, 0, "X3 read after 1-cyc rst");
        // reset while idle
        apply_reset;
        idle_watch(5);
        write_burst(4'd7, 4'd2, 0, 0, 0, 0, "X4 write after idle rst"); compare_mem("X4");
        read_burst (4'd7, 4'd2, 0, 0,        "X4 read back");

        $display("\n===== EXTRA: random per-beat gaps / stalls =====");
        for (r = 0; r < 60; r = r + 1) begin
            ra = $urandom % ADD_NUM;
            la = $urandom % ADD_NUM;
            write_burst(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], $urandom % 4, $urandom % 4, -1,
                        ($urandom % 5) - 1, "RNDG write");
            compare_mem("RNDG");
            read_burst (ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], $urandom % 4, -1, "RNDG read back");
        end

        $display("\n===== EXTRA: random concurrent, per-beat randomness =====");
        for (r = 0; r < 60; r = r + 1) begin
            ra = $urandom % ADD_NUM;
            la = $urandom % 8;
            rb = (ra + 8) % ADD_NUM;
            lr = $urandom % 8;
            fork
                write_burst(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], $urandom % 4, $urandom % 4, -1,
                            ($urandom % 5) - 1, "RNDX write");
                read_burst (rb[ADD_WIDTH-1:0], lr[LEN_WIDTH-1:0], $urandom % 4, -1, "RNDX read");
            join
            compare_mem("RNDX");
        end

        $display("\n===== EXTRA: random held AW / AR =====");
        for (r = 0; r < 30; r = r + 1) begin
            ra = $urandom % ADD_NUM; la = $urandom % ADD_NUM;
            rb = $urandom % ADD_NUM; lr = $urandom % ADD_NUM;
            write_pipelined(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], rb[ADD_WIDTH-1:0], lr[LEN_WIDTH-1:0],
                            $urandom % 3, "RNDP write");
            compare_mem("RNDP");
            read_pipelined (ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], rb[ADD_WIDTH-1:0], lr[LEN_WIDTH-1:0],
                            $urandom % 3, "RNDP read");
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