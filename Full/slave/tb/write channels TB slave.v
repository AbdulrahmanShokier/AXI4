`timescale 1ns/1ps

module tb_axi4_write;

    parameter DATA_WIDTH = 32;
    parameter ADD_WIDTH  = 4;
    parameter LEN_WIDTH  = 4;
    parameter ADD_NUM    = 16;

    // =====================================================
    // Signals
    // =====================================================
    reg                    clk;
    reg                    rst;                // active low

    // Write address channel
    reg  [ADD_WIDTH-1:0]   write_add;
    reg                    write_add_valid;
    wire                   write_add_ready;
    reg  [LEN_WIDTH-1:0]   write_add_length;   // beats = length + 1

    // Write data channel
    reg  [DATA_WIDTH-1:0]  write_data;
    reg                    write_data_valid;
    wire                   write_data_ready;
    reg                    write_data_last;

    // Write response channel
    wire                   write_resp;
    wire                   write_resp_valid;
    reg                    write_resp_ready;

    // Memory interface (memory lives in the TB)
    wire                   mem_wr_en;
    wire [ADD_WIDTH-1:0]   mem_wr_addr;
    wire [DATA_WIDTH-1:0]  mem_wr_data;

    integer errors;
    integer i;

    // =====================================================
    // Memory model + golden copy
    // =====================================================
    reg [DATA_WIDTH-1:0] memory [0:ADD_NUM-1];
    reg [DATA_WIDTH-1:0] golden [0:ADD_NUM-1];

    always @(posedge clk)
        if (mem_wr_en)
            memory[mem_wr_addr] <= mem_wr_data;

    // =====================================================
    // DUT
    // =====================================================
    axi4_write #(
        .data_width(DATA_WIDTH),
        .add_width (ADD_WIDTH),
        .len_width (LEN_WIDTH)
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
        .mem_wr_en        (mem_wr_en),
        .mem_wr_addr      (mem_wr_addr),
        .mem_wr_data      (mem_wr_data)
    );

    // =====================================================
    // Clock + watchdog
    // =====================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        #200000;
        $display("TIMEOUT - DUT stuck");
        $stop;
    end

    // =====================================================
    // Helpers
    // =====================================================
    task check;
        input          cond;
        input [8*40:1] msg;
        begin
            if (cond)
                $display("  PASS: %0s", msg);
            else begin
                $display("  FAIL: %0s", msg);
                errors = errors + 1;
            end
        end
    endtask

    // Deterministic per-burst, per-beat data pattern
    function [DATA_WIDTH-1:0] data_of;
        input [31:0] seed;
        input integer beat;
        begin
            data_of = seed * 32'h9E3779B1 + beat * 32'h01010101;
        end
    endfunction

    // =====================================================
    // Monitors
    // =====================================================
    integer beats_accepted;     // W handshakes seen in current burst
    integer mem_wr_count;       // memory writes seen in current burst
    integer burst_id;
    integer cur_len;
    reg     in_burst;
    reg     aw_done;            // AW handshake completed
    reg     resp_done;          // B handshake completed

    always @(posedge clk) begin
        if (rst && write_data_valid && write_data_ready)
            beats_accepted <= beats_accepted + 1;
        if (mem_wr_en)
            mem_wr_count <= mem_wr_count + 1;
    end

    // Protocol rules checked every cycle during a burst
    always @(negedge clk) begin
        if (in_burst) begin
            if (!aw_done && write_data_ready) begin
                $display("  FAIL: WREADY high before AW accepted (t=%0t)", $time);
                errors = errors + 1;
            end
            if (aw_done && !resp_done && write_add_ready) begin
                $display("  FAIL: AWREADY high during burst (t=%0t)", $time);
                errors = errors + 1;
            end
            if (aw_done && beats_accepted == cur_len + 1 && write_data_ready) begin
                $display("  FAIL: WREADY high after last beat (t=%0t)", $time);
                errors = errors + 1;
            end
        end
    end

    // -----------------------------------------------------
    // One full burst write.
    //   addr_delay : cycles before AWVALID is raised
    //   data_delay : cycles before first WVALID is raised
    //   data_gap   : idle cycles between W beats
    //   resp_stall : cycles BREADY is held low after BVALID rises
    //                (<0: BREADY held high from the start)
    //   scramble   : after the AW handshake, corrupt the inputs
    //                [0] -> write_add, [1] -> write_add_length
    // Signals are driven on negedge, sampled around posedge.
    // -----------------------------------------------------
    task write_burst;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         addr_delay;
        input integer         data_delay;
        input integer         data_gap;
        input integer         resp_stall;
        input [1:0]           scramble;
        input [8*24:1]        name;

        integer              j, k, bad;
        reg [31:0]           seed;
        begin
            $display("");
            $display("------------------------------------------");
            $display(" %0s : addr=%0d len=%0d aw_dly=%0d w_dly=%0d gap=%0d stall=%0d",
                     name, addr, len, addr_delay, data_delay, data_gap, resp_stall);
            $display("------------------------------------------");

            burst_id = burst_id + 1;
            seed     = burst_id;
            for (j = 0; j <= len; j = j + 1)
                golden[(addr + j) % ADD_NUM] = data_of(seed, j);

            @(negedge clk);
            cur_len        = len;
            beats_accepted = 0;
            mem_wr_count   = 0;
            aw_done        = 0;
            resp_done      = 0;
            in_burst       = 1;

            fork
                // ---------------- AW channel ----------------
                begin : aw_thread
                    repeat (addr_delay) @(negedge clk);
                    write_add        = addr;
                    write_add_length = len;
                    write_add_valid  = 1;
                    @(posedge clk);
                    while (!write_add_ready) @(posedge clk);
                    #1 write_add_valid = 0;
                    aw_done = 1;
                    check(write_add_ready == 0, "AW handshake, AWREADY drops");
                    if (scramble[0]) write_add        = ~addr;
                    if (scramble[1]) write_add_length = ~len;
                end

                // ---------------- W channel -----------------
                begin : w_thread
                    integer b;
                    repeat (data_delay) @(negedge clk);
                    for (b = 0; b <= len; b = b + 1) begin
                        if (b > 0) begin
                            @(negedge clk);
                            repeat (data_gap) @(negedge clk);
                        end
                        write_data       = data_of(seed, b);
                        write_data_valid = 1;
                        write_data_last  = (b == len);
                        @(posedge clk);
                        while (!write_data_ready) @(posedge clk);
                        #1 write_data_valid = 0;
                        write_data_last  = 0;
                        write_data       = ~data_of(seed, b);   // must not be re-sampled
                    end
                end

                // ---------------- B channel -----------------
                begin : b_thread
                    integer n;
                    reg     stable;
                    if (resp_stall < 0) begin
                        write_resp_ready = 1;
                        @(posedge clk);
                        while (!write_resp_valid) @(posedge clk);
                        check(beats_accepted == len + 1, "BVALID only after all beats");
                        check(write_resp == 1'b1,        "BRESP");
                        #1 write_resp_ready = 0;
                        resp_done = 1;
                    end
                    else begin
                        @(negedge clk);
                        while (!write_resp_valid) @(negedge clk);
                        check(beats_accepted == len + 1, "BVALID only after all beats");
                        stable = 1;
                        for (n = 0; n < resp_stall; n = n + 1) begin
                            @(negedge clk);
                            if (!write_resp_valid || write_resp !== 1'b1)
                                stable = 0;
                        end
                        if (resp_stall > 0)
                            check(stable, "back-pressure: BVALID/BRESP stable");
                        write_resp_ready = 1;
                        check(write_resp == 1'b1, "BRESP");
                        @(posedge clk);
                        #1 write_resp_ready = 0;
                        resp_done = 1;
                    end
                end
            join

            // ---- completion ----
            @(negedge clk);
            check(write_resp_valid == 0, "BVALID low after handshake");
            check(write_data_ready == 0, "WREADY low after burst");

            k = 0;
            while (!write_add_ready && k < 5) begin
                @(negedge clk);
                k = k + 1;
            end
            check(write_add_ready == 1, "AWREADY back high (idle)");

            repeat (2) @(negedge clk);
            check(mem_wr_en == 0,                "no stray memory write");
            check(mem_wr_count == len + 1,       "one mem write per beat");

            bad = 0;
            for (j = 0; j < ADD_NUM; j = j + 1)
                if (memory[j] !== golden[j]) begin
                    $display("  FAIL: memory[%0d]=%h expected %h", j, memory[j], golden[j]);
                    bad = bad + 1;
                end
            check(bad == 0, "memory contents match expected");
            errors = errors + bad;

            in_burst = 0;
        end
    endtask

    // =====================================================
    // Test sequence
    // =====================================================
    initial begin
        errors         = 0;
        burst_id       = 0;
        beats_accepted = 0;
        mem_wr_count   = 0;
        cur_len        = 0;
        in_burst       = 0;
        aw_done        = 0;
        resp_done      = 0;

        rst              = 0;
        write_add        = 0;
        write_add_valid  = 0;
        write_add_length = 0;
        write_data       = 0;
        write_data_valid = 0;
        write_data_last  = 0;
        write_resp_ready = 0;

        for (i = 0; i < ADD_NUM; i = i + 1) begin
            memory[i] = 32'hDEAD_0000 + i;
            golden[i] = 32'hDEAD_0000 + i;
        end

        repeat (2) @(posedge clk);
        #1;
        $display("");
        $display(" Reset state");
        check(write_add_ready  == 1, "AWREADY high in reset");
        check(write_data_ready == 0, "WREADY low in reset");
        check(write_resp_valid == 0, "BVALID low in reset");
        check(mem_wr_en        == 0, "mem_wr_en low in reset");
        rst = 1;
        @(posedge clk);

        //                addr   len    aw_dly w_dly gap stall scr   name
        // T1: single beat
        write_burst(4'd1,  4'd0,  0, 0, 0,  0, 2'b00, "T1 single beat");
        // T2: addr+len latch, response back-pressure
        write_burst(4'd6,  4'd2,  0, 0, 0,  5, 2'b11, "T2 latch + resp stall");
        // T3: 4-beat burst
        write_burst(4'd4,  4'd3,  0, 0, 0,  0, 2'b00, "T3 burst x4");
        // T4: data first, address 4 cycles late
        write_burst(4'd8,  4'd3,  4, 0, 0,  0, 2'b00, "T4 data first");
        // T5: address first, data 5 cycles late
        write_burst(4'd2,  4'd3,  0, 5, 0,  0, 2'b00, "T5 addr first");
        // T6: gaps between W beats
        write_burst(4'd10, 4'd3,  0, 0, 2,  0, 2'b00, "T6 W gaps");
        // T7: BREADY held high before BVALID
        write_burst(4'd3,  4'd1,  0, 0, 0, -1, 2'b00, "T7 early BREADY");
        // T8: address wrap-around (14,15,0,1)
        write_burst(4'd14, 4'd3,  0, 0, 0,  0, 2'b00, "T8 addr wrap");
        // T9: max burst (16 beats)
        write_burst(4'd0,  4'd15, 0, 0, 0,  0, 2'b00, "T9 burst x16");
        // T10: max burst, wrapping, gaps + stall
        write_burst(4'd5,  4'd15, 0, 0, 1,  3, 2'b00, "T10 x16 wrap+gaps");
        // T11: everything at once
        write_burst(4'd9,  4'd4,  3, 1, 1,  2, 2'b11, "T11 mixed");
        // T12: back-to-back single beats
        write_burst(4'd12, 4'd0,  0, 0, 0,  0, 2'b00, "T12a back-to-back");
        write_burst(4'd13, 4'd0,  0, 0, 0,  0, 2'b00, "T12b back-to-back");

        #20;
        $display("");
        $display("==========================================");
        if (errors == 0)
            $display("   SIMULATION FINISHED - ALL PASS");
        else
            $display("   SIMULATION FINISHED - %0d FAILURE(S)", errors);
        $display("==========================================");
        $stop;
    end

endmodule