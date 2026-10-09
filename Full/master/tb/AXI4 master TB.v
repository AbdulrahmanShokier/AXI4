`timescale 1ns/1ps
//=============================================================================
// tb_axi4_master : self-checking testbench for axi4_master ONLY
//
//  - The master is connected to a behavioral burst slave (BFM below), not to
//    the real axi4_slave, so the master is checked in isolation.
//  - rst is ACTIVE-LOW, burst length field: beats = length + 1
//  - User-side inputs are driven on negedge, DUT outputs are sampled at
//    posedge / negedge.
//  - BFM knobs (all in clock cycles):
//      aw_dly / w_dly / b_dly : AWREADY delay, WREADY delay per beat, BVALID delay
//      ar_dly / r_dly         : ARREADY delay, RVALID delay per beat
//      bresp_val              : BRESP value the BFM returns (1 = OK)
//      bad_rresp_beat         : beat that returns RRESP = 0   (-1 = none)
//      bad_rlast_beat         : beat whose RLAST is inverted  (-1 = none)
//  - ref_mem is the golden memory, bfm_mem is the BFM's own memory.
//=============================================================================
module tb_axi4_master;

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

    // AXI side : write (master <-> BFM)
    wire [ADD_WIDTH-1:0]   write_add;
    wire                   write_add_valid;
    reg                    write_add_ready;
    wire [LEN_WIDTH-1:0]   write_add_length;
    wire [DATA_WIDTH-1:0]  write_data;
    wire                   write_data_valid;
    reg                    write_data_ready;
    wire                   write_data_last;
    reg                    write_resp;
    reg                    write_resp_valid;
    wire                   write_resp_ready;

    // AXI side : read (master <-> BFM)
    wire [ADD_WIDTH-1:0]   read_add;
    wire                   read_add_valid;
    reg                    read_add_ready;
    wire [LEN_WIDTH-1:0]   read_add_length;
    reg  [DATA_WIDTH-1:0]  read_data;
    reg                    read_data_valid;
    reg                    read_data_resp;
    wire                   read_data_ready;
    reg                    read_data_last;

    //-------------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------------
    axi4_master #(
        .data_width (DATA_WIDTH),
        .add_width  (ADD_WIDTH),
        .len_width  (LEN_WIDTH)
    ) dut (
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

    //-------------------------------------------------------------------
    // Clock, dump, watchdog
    //-------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("axi4_master_tb.vcd");
        $dumpvars(0, tb_axi4_master);
    end

    initial begin
        #5000000;
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
    reg [DATA_WIDTH-1:0] bfm_mem [0:ADD_NUM-1];   // BFM memory

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
    // BFM knobs
    //-------------------------------------------------------------------
    integer aw_dly, w_dly, b_dly, ar_dly, r_dly;
    reg     bresp_val;
    integer bad_rresp_beat, bad_rlast_beat;

    //-------------------------------------------------------------------
    // BFM : write side (AW -> W -> B)
    //-------------------------------------------------------------------
    reg [1:0]               wb_state;
    reg [ADD_WIDTH-1:0]     bw_addr;
    reg [LEN_WIDTH-1:0]     bw_len;
    integer                 bw_beat;
    integer                 w_beats_seen;
    integer                 wcnt;

    always @(posedge clk) begin
        if (!rst) begin
            write_add_ready  <= 1'b0;
            write_data_ready <= 1'b0;
            write_resp_valid <= 1'b0;
            write_resp       <= 1'b0;
            wb_state         <= 2'd0;
            wcnt             <= 0;
            bw_beat          <= 0;
            w_beats_seen     <= 0;
        end
        else begin
            case (wb_state)

            // ---------------- AW ----------------
            2'd0: begin
                if (write_add_valid && write_add_ready) begin
                    bw_addr         <= write_add;
                    bw_len          <= write_add_length;
                    bw_beat         <= 0;
                    w_beats_seen    <= 0;
                    write_add_ready <= 1'b0;
                    wcnt            <= 0;
                    wb_state        <= 2'd1;
                end
                else if (write_add_valid) begin
                    if (wcnt >= aw_dly) write_add_ready <= 1'b1;
                    else                wcnt <= wcnt + 1;
                end
            end

            // ---------------- W -----------------
            2'd1: begin
                if (write_data_valid && write_data_ready) begin
                    bfm_mem[(bw_addr + bw_beat) % ADD_NUM] <= write_data;
                    w_beats_seen     <= w_beats_seen + 1;
                    write_data_ready <= 1'b0;
                    wcnt             <= 0;
                    if (write_data_last !== (bw_beat == bw_len)) begin
                        $display("  FAIL: BFM saw WLAST=%b at beat %0d (len=%0d) (t=%0t)",
                                 write_data_last, bw_beat, bw_len, $time);
                        errors = errors + 1;
                    end
                    if (bw_beat == bw_len) wb_state <= 2'd2;
                    else                   bw_beat  <= bw_beat + 1;
                end
                else if (!write_data_ready) begin
                    if (wcnt >= w_dly) write_data_ready <= 1'b1;
                    else               wcnt <= wcnt + 1;
                end
            end

            // ---------------- B -----------------
            2'd2: begin
                if (!write_resp_valid) begin
                    if (wcnt >= b_dly) begin
                        write_resp_valid <= 1'b1;
                        write_resp       <= bresp_val;
                    end
                    else wcnt <= wcnt + 1;
                end
                else if (write_resp_ready) begin
                    write_resp_valid <= 1'b0;
                    write_resp       <= 1'b0;
                    wcnt             <= 0;
                    wb_state         <= 2'd0;
                end
            end

            default: wb_state <= 2'd0;
            endcase
        end
    end

    //-------------------------------------------------------------------
    // BFM : read side (AR -> R)
    //-------------------------------------------------------------------
    reg                     rb_state;
    reg [ADD_WIDTH-1:0]     br_addr;
    reg [LEN_WIDTH-1:0]     br_len;
    integer                 br_beat;
    integer                 rcnt;

    always @(posedge clk) begin
        if (!rst) begin
            read_add_ready  <= 1'b0;
            read_data       <= {DATA_WIDTH{1'b0}};
            read_data_valid <= 1'b0;
            read_data_resp  <= 1'b0;
            read_data_last  <= 1'b0;
            rb_state        <= 1'b0;
            rcnt            <= 0;
            br_beat         <= 0;
        end
        else begin
            case (rb_state)

            // ---------------- AR ----------------
            1'b0: begin
                if (read_add_valid && read_add_ready) begin
                    br_addr        <= read_add;
                    br_len         <= read_add_length;
                    br_beat        <= 0;
                    read_add_ready <= 1'b0;
                    rcnt           <= 0;
                    rb_state       <= 1'b1;
                end
                else if (read_add_valid) begin
                    if (rcnt >= ar_dly) read_add_ready <= 1'b1;
                    else                rcnt <= rcnt + 1;
                end
            end

            // ---------------- R -----------------
            1'b1: begin
                if (!read_data_valid) begin
                    if (rcnt >= r_dly) begin
                        read_data       <= bfm_mem[(br_addr + br_beat) % ADD_NUM];
                        read_data_resp  <= (br_beat != bad_rresp_beat);
                        read_data_last  <= (br_beat == br_len) ^ (br_beat == bad_rlast_beat);
                        read_data_valid <= 1'b1;
                    end
                    else rcnt <= rcnt + 1;
                end
                else if (read_data_ready) begin
                    read_data_valid <= 1'b0;
                    read_data_last  <= 1'b0;
                    read_data_resp  <= 1'b0;
                    rcnt            <= 0;
                    if (br_beat == br_len) rb_state <= 1'b0;
                    else                   br_beat  <= br_beat + 1;
                end
            end
            endcase
        end
    end

    //-------------------------------------------------------------------
    // Protocol monitors on the master outputs (run all the time)
    //   VALID must stay high and payload stable until READY
    //   done must be a single-cycle pulse
    //-------------------------------------------------------------------
    reg                     p_awv, p_awr;  reg [ADD_WIDTH-1:0]  p_aw;  reg [LEN_WIDTH-1:0] p_awl;
    reg                     p_wv,  p_wr;   reg [DATA_WIDTH-1:0] p_w;   reg                  p_wl;
    reg                     p_arv, p_arr;  reg [ADD_WIDTH-1:0]  p_ar;  reg [LEN_WIDTH-1:0] p_arl;
    reg                     p_wdone, p_rdone;
    reg                     mon_en;

    always @(posedge clk) begin
        if (mon_en && rst) begin
            if (p_awv && !p_awr) begin
                if (!write_add_valid || write_add !== p_aw || write_add_length !== p_awl) begin
                    $display("  FAIL: AW channel not stable under back-pressure (t=%0t)", $time);
                    errors = errors + 1;
                end
            end
            if (p_wv && !p_wr) begin
                if (!write_data_valid || write_data !== p_w || write_data_last !== p_wl) begin
                    $display("  FAIL: W channel not stable under back-pressure (t=%0t)", $time);
                    errors = errors + 1;
                end
            end
            if (p_arv && !p_arr) begin
                if (!read_add_valid || read_add !== p_ar || read_add_length !== p_arl) begin
                    $display("  FAIL: AR channel not stable under back-pressure (t=%0t)", $time);
                    errors = errors + 1;
                end
            end
            if (p_wdone && write_done_out) begin
                $display("  FAIL: write_done_out wider than one cycle (t=%0t)", $time);
                errors = errors + 1;
            end
            if (p_rdone && read_done_out) begin
                $display("  FAIL: read_done_out wider than one cycle (t=%0t)", $time);
                errors = errors + 1;
            end
            if (write_add_valid && write_data_valid) begin
                $display("  FAIL: AWVALID and WVALID high together (t=%0t)", $time);
                errors = errors + 1;
            end
        end
        p_awv <= write_add_valid;  p_awr <= write_add_ready;
        p_aw  <= write_add;        p_awl <= write_add_length;
        p_wv  <= write_data_valid; p_wr  <= write_data_ready;
        p_w   <= write_data;       p_wl  <= write_data_last;
        p_arv <= read_add_valid;   p_arr <= read_add_ready;
        p_ar  <= read_add;         p_arl <= read_add_length;
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
            check(read_busy_out == 0,       "reset: read_busy low");
            check(read_done_out == 0,       "reset: read_done low");
            check(read_error_out == 0,      "reset: read_error low");
            check(read_add_valid == 0,      "reset: ARVALID low");
            check(read_data_ready == 0,     "reset: RREADY low");
            check(read_data_valid_out == 0, "reset: user RVALID low");
            @(negedge clk);
            rst = 1;
        end
    endtask

    task resync_ref;
        integer m;
        begin
            for (m = 0; m < ADD_NUM; m = m + 1) ref_mem[m] = bfm_mem[m];
        end
    endtask

    task automatic compare_mem;
        input [8*24:1] name;
        integer m, bad;
        begin
            bad = 0;
            for (m = 0; m < ADD_NUM; m = m + 1)
                if (bfm_mem[m] !== ref_mem[m]) begin
                    $display("  FAIL: memory[%0d]=%h expected %h", m, bfm_mem[m], ref_mem[m]);
                    bad = bad + 1;
                end
            check(bad == 0, "BFM memory matches golden");
            errors = errors + bad;
        end
    endtask

    //-------------------------------------------------------------------
    // WRITE transaction through the master
    //   src_dly : cycles before the first beat is offered
    //   gap     : idle cycles between beats from the source
    //   poke    : 1 -> pulse start again while busy, in the address and the
    //             data phase (must be ignored)
    //   exp_err : expected value of write_error_out at done
    //-------------------------------------------------------------------
    task automatic write_txn;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         src_dly;
        input integer         gap;
        input                 poke;
        input                 exp_err;
        input [8*24:1]        name;

        integer b, cyc;
        reg [31:0] seed;
        begin
            $display("");
            $display("-- WRITE %0s : addr=%0d len=%0d src_dly=%0d gap=%0d | aw=%0d w=%0d b=%0d",
                     name, addr, len, src_dly, gap, aw_dly, w_dly, b_dly);

            burst_id = burst_id + 1;
            seed     = burst_id;
            for (b = 0; b <= len; b = b + 1)
                ref_mem[(addr + b) % ADD_NUM] = data_of(seed, b);

            // ---- start ----
            @(negedge clk);
            while (write_busy_out) @(negedge clk);
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
            check(write_done_out == 1,                    "write_done pulse seen");
            check(write_busy_out == 1,                    "busy still high at done");
            check(write_error_out === exp_err,            "write_error as expected");
            check(w_beats_seen == len + 1,                "slave got len+1 beats");
            check(bw_addr == addr,                        "slave got the right address");
            check(bw_len  == len,                         "slave got the right length");
            @(negedge clk);
            check(write_busy_out == 0,                    "busy low after done");
            check(write_done_out == 0,                    "done low after pulse");
        end
    endtask

    //-------------------------------------------------------------------
    // READ transaction through the master
    //   stall   : cycles the sink holds ready low before every beat
    //             (<0 : sink ready is high the whole time)
    //   poke    : 1 -> pulse start again while busy, in the address and the
    //             data phase (must be ignored)
    //   exp_err : expected value of read_error_out at done
    //             (when 1 the RLAST output check is skipped)
    //-------------------------------------------------------------------
    task automatic read_txn;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         stall;
        input                 poke;
        input                 exp_err;
        input [8*24:1]        name;

        integer beat, k, cyc;
        reg [DATA_WIDTH-1:0] held, expected;
        reg stable;
        begin
            $display("");
            $display("-- READ  %0s : addr=%0d len=%0d stall=%0d | ar=%0d r=%0d",
                     name, addr, len, stall, ar_dly, r_dly);

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
                    if (read_data_out === expected)
                        $display("  PASS: beat %0d RDATA=%h", beat, read_data_out);
                    else begin
                        $display("  FAIL: beat %0d RDATA=%h expected %h", beat, read_data_out, expected);
                        errors = errors + 1;
                    end
                    checks = checks + 1;
                    if (!exp_err)
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
                    if (read_data_out === expected)
                        $display("  PASS: beat %0d RDATA=%h", beat, read_data_out);
                    else begin
                        $display("  FAIL: beat %0d RDATA=%h expected %h", beat, read_data_out, expected);
                        errors = errors + 1;
                    end
                    checks = checks + 1;
                    if (!exp_err)
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
            check(read_done_out == 1,                     "read_done pulse seen");
            check(read_busy_out == 1,                     "busy still high at done");
            check(read_data_valid_out == 0,               "user RVALID low at done");
            check(read_error_out === exp_err,             "read_error as expected");
            check(br_addr == addr,                        "slave got the right address");
            check(br_len  == len,                         "slave got the right length");
            @(negedge clk);
            check(read_busy_out == 0,                     "busy low after done");
            check(read_done_out == 0,                     "done low after pulse");
        end
    endtask

    //-------------------------------------------------------------------
    // Test sequence
    //-------------------------------------------------------------------
    integer r, ra, la, rb, lr;
    integer s_src, s_gap, s_stall, s_poke;

    task set_delays;
        input integer a_aw, a_w, a_b, a_ar, a_r;
        begin
            aw_dly = a_aw; w_dly = a_w; b_dly = a_b; ar_dly = a_ar; r_dly = a_r;
        end
    endtask

    initial begin
        errors = 0; checks = 0; burst_id = 0; mon_en = 0;
        p_awv = 0; p_awr = 0; p_aw = 0; p_awl = 0;
        p_wv  = 0; p_wr  = 0; p_w  = 0; p_wl  = 0;
        p_arv = 0; p_arr = 0; p_ar = 0; p_arl = 0;
        p_wdone = 0; p_rdone = 0;

        set_delays(0, 0, 0, 0, 0);
        bresp_val = 1;
        bad_rresp_beat = -1;
        bad_rlast_beat = -1;

        rst = 0;
        start_write_out = 0; write_add_out = 0; write_length_out = 0;
        write_data_out = 0;  write_data_valid_out = 0;
        start_read_out = 0;  read_add_out = 0; read_length_out = 0;
        read_data_ready_out = 0;

        for (i = 0; i < ADD_NUM; i = i + 1) begin
            bfm_mem[i] = 32'hA000_0000 + i;
            ref_mem[i] = 32'hA000_0000 + i;
        end

        $display("\n===== Reset =====");
        apply_reset;
        mon_en = 1;

        //---------------------------------------------------------------
        $display("\n===== Reads from preloaded memory =====");
        read_txn(4'd3,  4'd0,  0, 0, 0, "R1 single beat");
        read_txn(4'd4,  4'd3,  0, 0, 0, "R2 burst x4");

        //---------------------------------------------------------------
        $display("\n===== Writes, slave side delays =====");
        write_txn(4'd1,  4'd0,  0, 0, 0, 0, "W1 single beat");        compare_mem("W1");
        write_txn(4'd4,  4'd3,  0, 0, 0, 0, "W2 burst x4");           compare_mem("W2");
        set_delays(3, 0, 0, 0, 0);
        write_txn(4'd8,  4'd3,  0, 0, 0, 0, "W3 slow AWREADY");       compare_mem("W3");
        set_delays(0, 3, 0, 0, 0);
        write_txn(4'd2,  4'd3,  0, 0, 0, 0, "W4 slow WREADY");        compare_mem("W4");
        set_delays(0, 0, 4, 0, 0);
        write_txn(4'd6,  4'd2,  0, 0, 0, 0, "W5 slow BVALID");        compare_mem("W5");
        set_delays(2, 2, 2, 0, 0);
        write_txn(4'd10, 4'd4,  0, 0, 0, 0, "W6 all slow");           compare_mem("W6");
        set_delays(0, 0, 0, 0, 0);

        $display("\n===== Writes, source side behaviour =====");
        write_txn(4'd3,  4'd3,  5, 0, 0, 0, "W7 late first beat");    compare_mem("W7");
        write_txn(4'd12, 4'd3,  0, 2, 0, 0, "W8 gaps between beats"); compare_mem("W8");
        write_txn(4'd9,  4'd4,  3, 1, 0, 0, "W9 late + gaps");        compare_mem("W9");

        $display("\n===== Writes, length / address corners =====");
        write_txn(4'd14, 4'd3,  0, 0, 0, 0, "W10 addr wrap");         compare_mem("W10");
        write_txn(4'd0,  4'd15, 0, 0, 0, 0, "W11 burst x16");         compare_mem("W11");
        write_txn(4'd5,  4'd15, 0, 1, 0, 0, "W12 x16 wrap + gaps");   compare_mem("W12");
        write_txn(4'd12, 4'd0,  0, 0, 0, 0, "W13a back-to-back");
        write_txn(4'd13, 4'd0,  0, 0, 0, 0, "W13b back-to-back");     compare_mem("W13");

        $display("\n===== Write: start while busy is ignored =====");
        write_txn(4'd7,  4'd2,  0, 0, 1, 0, "W14 start while busy");   compare_mem("W14");

        $display("\n===== Write: bad BRESP raises error =====");
        bresp_val = 0;
        write_txn(4'd2,  4'd1,  0, 0, 0, 1, "W15 bad BRESP");
        bresp_val = 1;
        write_txn(4'd2,  4'd1,  0, 0, 0, 0, "W16 error cleared");     compare_mem("W16");

        //---------------------------------------------------------------
        $display("\n===== Reads, slave side delays =====");
        read_txn(4'd1,  4'd0,  0, 0, 0, "R3 single beat");
        set_delays(0, 0, 0, 3, 0);
        read_txn(4'd4,  4'd3,  0, 0, 0, "R4 slow ARREADY");
        set_delays(0, 0, 0, 0, 3);
        read_txn(4'd8,  4'd3,  0, 0, 0, "R5 slow RVALID");
        set_delays(0, 0, 0, 2, 2);
        read_txn(4'd2,  4'd4,  0, 0, 0, "R6 both slow");
        set_delays(0, 0, 0, 0, 0);

        $display("\n===== Reads, sink side behaviour =====");
        read_txn(4'd4,  4'd3,  3, 0, 0, "R7 sink stalls");
        read_txn(4'd6,  4'd5,  1, 0, 0, "R8 short stalls");
        read_txn(4'd10, 4'd4, -1, 0, 0, "R9 RREADY always high");
        set_delays(0, 0, 0, 0, 2);
        read_txn(4'd0,  4'd5, -1, 0, 0, "R10 RREADY high + slow R");
        set_delays(0, 0, 0, 0, 0);

        $display("\n===== Reads, length / address corners =====");
        read_txn(4'd14, 4'd3,  0, 0, 0, "R11 addr wrap");
        read_txn(4'd0,  4'd15, 0, 0, 0, "R12 burst x16");
        read_txn(4'd9,  4'd15, 1, 0, 0, "R13 x16 wrap + stalls");
        read_txn(4'd3,  4'd0,  0, 0, 0, "R14a back-to-back");
        read_txn(4'd9,  4'd0,  0, 0, 0, "R14b back-to-back");

        $display("\n===== Read: start while busy is ignored =====");
        read_txn(4'd5,  4'd2,  0, 1, 0, "R15 start while busy");

        $display("\n===== Read: bad RRESP / bad RLAST raise error =====");
        bad_rresp_beat = 1;
        read_txn(4'd4,  4'd3,  0, 0, 1, "R16 bad RRESP on beat 1");
        bad_rresp_beat = -1;
        bad_rlast_beat = 2;
        read_txn(4'd4,  4'd3,  0, 0, 1, "R17 bad RLAST on beat 2");
        bad_rlast_beat = 3;
        read_txn(4'd4,  4'd3,  0, 0, 1, "R18 RLAST missing");
        bad_rlast_beat = -1;
        read_txn(4'd4,  4'd3,  0, 0, 0, "R19 error cleared");

        //---------------------------------------------------------------
        $display("\n===== Write and read at the same time =====");
        fork
            write_txn(4'd0, 4'd3, 0, 0, 0, 0, "C1 write 0..3");
            read_txn (4'd8, 4'd3, 0, 0, 0,    "C1 read 8..11");
        join
        compare_mem("C1");
        set_delays(1, 2, 1, 2, 1);
        fork
            write_txn(4'd4,  4'd5, 1, 1, 0, 0, "C2 write 4..9");
            read_txn (4'd12, 4'd5, 2, 0, 0,    "C2 read 12..1");
        join
        compare_mem("C2");
        set_delays(0, 0, 0, 0, 0);

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
        write_txn(4'd3, 4'd3, 0, 0, 0, 0, "RST1 write after reset");
        compare_mem("RST1");
        read_txn (4'd3, 4'd3, 0, 0, 0,    "RST1 read after reset");

        $display("\n===== Reset in the middle of a read burst =====");
        @(negedge clk);
        read_add_out = 4'd2; read_length_out = 4'd9; start_read_out = 1;
        @(negedge clk);
        start_read_out = 0;
        read_data_ready_out = 0;
        while (!read_data_valid_out) @(negedge clk);
        repeat (2) @(negedge clk);
        apply_reset;
        read_txn (4'd2, 4'd9, 0, 0, 0,    "RST2 read after reset");
        write_txn(4'd6, 4'd2, 0, 0, 0, 0, "RST2 write after reset");
        compare_mem("RST2");

        //---------------------------------------------------------------
        $display("\n===== Randomized sequential transactions =====");
        for (r = 0; r < 40; r = r + 1) begin
            ra = $urandom % ADD_NUM;
            la = $urandom % ADD_NUM;
            set_delays($urandom % 4, $urandom % 4, $urandom % 4, $urandom % 4, $urandom % 4);
            s_src = $urandom % 4; s_gap = $urandom % 3;
            s_stall = ($urandom % 5) - 1; s_poke = $urandom % 2;
            write_txn(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], s_src, s_gap, s_poke[0], 0, "RND write");
            compare_mem("RND");
            s_poke = $urandom % 2;
            read_txn (ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], s_stall, s_poke[0], 0, "RND read back");
        end

        $display("\n===== Randomized concurrent transactions (disjoint, <=8 beats) =====");
        for (r = 0; r < 40; r = r + 1) begin
            ra = $urandom % ADD_NUM;
            la = $urandom % 8;
            rb = (ra + 8) % ADD_NUM;
            lr = $urandom % 8;
            set_delays($urandom % 4, $urandom % 4, $urandom % 4, $urandom % 4, $urandom % 4);
            s_src = $urandom % 4; s_gap = $urandom % 3; s_stall = ($urandom % 5) - 1;
            fork
                write_txn(ra[ADD_WIDTH-1:0], la[LEN_WIDTH-1:0], s_src, s_gap, 1'b0, 1'b0, "RNDC write");
                read_txn (rb[ADD_WIDTH-1:0], lr[LEN_WIDTH-1:0], s_stall, 1'b0, 1'b0, "RNDC read");
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