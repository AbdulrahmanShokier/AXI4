`timescale 1ns/1ps

module tb_axi4_read;

    parameter DATA_WIDTH = 32;
    parameter ADD_WIDTH  = 4;
    parameter LEN_WIDTH  = 4;
    parameter ADD_NUM    = 16;

    // =====================================================
    // Signals
    // =====================================================
    reg                    clk;
    reg                    rst;                // active low

    // Read address channel
    reg  [ADD_WIDTH-1:0]   read_add;
    reg                    read_add_valid;
    wire                   read_add_ready;
    reg  [LEN_WIDTH-1:0]   read_add_length;    // beats = length + 1

    // Read data channel
    wire [DATA_WIDTH-1:0]  read_data;
    wire                   read_data_valid;
    wire                   read_data_resp;
    reg                    read_data_ready;
    wire                   read_data_last;

    // Memory interface (memory now lives in the TB)
    wire [ADD_WIDTH-1:0]   mem_rd_addr;
    wire [DATA_WIDTH-1:0]  mem_rd_data;

    integer errors;
    integer i;

    // =====================================================
    // Memory model (combinational read)
    // =====================================================
    reg [DATA_WIDTH-1:0] memory [0:ADD_NUM-1];
    assign mem_rd_data = memory[mem_rd_addr];

    // =====================================================
    // DUT
    // =====================================================
    axi4_read #(
        .data_width(DATA_WIDTH),
        .add_width (ADD_WIDTH),
        .len_width (LEN_WIDTH)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .read_add        (read_add),
        .read_add_valid  (read_add_valid),
        .read_add_ready  (read_add_ready),
        .read_add_length (read_add_length),
        .read_data       (read_data),
        .read_data_valid (read_data_valid),
        .read_data_resp  (read_data_resp),
        .read_data_ready (read_data_ready),
        .read_data_last  (read_data_last),
        .mem_rd_addr     (mem_rd_addr),
        .mem_rd_data     (mem_rd_data)
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

    // -----------------------------------------------------
    // One full burst read.
    //   stall    : cycles RREADY is held low before every beat
    //              (RVALID/RDATA must stay stable meanwhile)
    //   scramble : after the AR handshake, corrupt the inputs
    //              [0] -> read_add, [1] -> read_add_length
    //              (DUT must have latched them)
    // Signals are driven on negedge, sampled around posedge.
    // -----------------------------------------------------
    task read_burst;
        input [ADD_WIDTH-1:0] addr;
        input [LEN_WIDTH-1:0] len;
        input integer         stall;
        input [1:0]           scramble;
        input [8*24:1]        name;

        integer              beat, k;
        reg [DATA_WIDTH-1:0] held;
        reg [DATA_WIDTH-1:0] expected;
        reg                  stable;
        begin
            $display("");
            $display("------------------------------------------");
            $display(" %0s : addr=%0d len=%0d stall=%0d", name, addr, len, stall);
            $display("------------------------------------------");

            // ---- address phase ----
            @(negedge clk);
            while (!read_add_ready) @(negedge clk);

            read_add        = addr;
            read_add_length = len;
            read_add_valid  = 1;

            @(posedge clk);          // handshake edge (ready was high)
            #1;
            read_add_valid = 0;

            check(read_add_ready == 0, "AR handshake, ARREADY drops");

            if (scramble[0]) read_add        = ~addr;
            if (scramble[1]) read_add_length = ~len;

            // ---- data phase ----
            for (beat = 0; beat <= len; beat = beat + 1) begin

                @(negedge clk);
                while (!read_data_valid) @(negedge clk);

                expected = memory[(addr + beat) % ADD_NUM];
                held     = read_data;
                stable   = 1;

                // back-pressure: RREADY low, everything must hold
                for (k = 0; k < stall; k = k + 1) begin
                    @(negedge clk);
                    if (!read_data_valid || read_data !== held)
                        stable = 0;
                end
                if (stall > 0)
                    check(stable, "back-pressure: RVALID/RDATA stable");

                // accept the beat
                read_data_ready = 1;

                if (read_data === expected)
                    $display("  PASS: beat %0d RDATA=%h", beat, read_data);
                else begin
                    $display("  FAIL: beat %0d RDATA=%h expected %h",
                             beat, read_data, expected);
                    errors = errors + 1;
                end

                check(read_data_resp == 1'b1,                      "RRESP");
                check(read_data_last == (beat == len),             "RLAST");
                check(read_add_ready == 0,                         "ARREADY low during burst");

                @(posedge clk);      // data handshake edge
                #1;
                read_data_ready = 0;
            end

            // ---- completion ----
            @(negedge clk);
            check(read_data_valid == 0, "RVALID low after last beat");

            k = 0;
            while (!read_add_ready && k < 5) begin
                @(negedge clk);
                k = k + 1;
            end
            check(read_add_ready == 1, "ARREADY back high (idle)");
        end
    endtask

    // =====================================================
    // Test sequence
    // =====================================================
    initial begin
        errors = 0;

        rst             = 0;
        read_add        = 0;
        read_add_valid  = 0;
        read_add_length = 0;
        read_data_ready = 0;

        // memory[i] = i replicated per nibble: 00000000, 11111111, 22222222 ...
        for (i = 0; i < ADD_NUM; i = i + 1)
            memory[i] = i * 32'h11111111;

        repeat (2) @(posedge clk);
        #1 rst = 1;
        @(posedge clk);

        // T1: single beat (len = 0), no stall
        read_burst(4'd1, 4'd0, 0, 2'b00, "T1 single beat");

        // T2: address register test + back-pressure, single beat
        read_burst(4'd1, 4'd0, 5, 2'b01, "T2 addr latch + stall");

        // T3: 4-beat burst, no stall
        read_burst(4'd4, 4'd3, 0, 2'b00, "T3 burst x4");

        // T4: 4-beat burst, back-pressure on every beat
        read_burst(4'd8, 4'd3, 3, 2'b00, "T4 burst x4 + stall");

        // T5: length latch test (length corrupted after AR handshake)
        read_burst(4'd2, 4'd2, 0, 2'b10, "T5 length latch");

        // T6: address AND length corrupted, with stall
        read_burst(4'd5, 4'd2, 2, 2'b11, "T6 addr+len latch");

        // T7: max length burst (16 beats)
        read_burst(4'd0, 4'd15, 0, 2'b00, "T7 burst x16");

        // T8: back-to-back single beats
        read_burst(4'd3, 4'd0, 0, 2'b00, "T8a back-to-back");
        read_burst(4'd9, 4'd0, 0, 2'b00, "T8b back-to-back");

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

/*
TESTBENCH TEST LIST (tb_axi4_read)

T1 - Single beat
  addr=1, len=0 (1 beat), stall=0, no corruption
  Checks: basic read, AR handshake, correct data, RRESP, RLAST, return to idle

T2 - Address latch + back-pressure
  addr=1, len=0 (1 beat), stall=5, read_add inverted after AR handshake
  Checks: address is latched, RVALID/RDATA stay stable while RREADY is low

T3 - Burst x4
  addr=4, len=3 (4 beats), stall=0, no corruption
  Checks: multi-beat data sequence, RLAST only on the final beat

T4 - Burst x4 with back-pressure
  addr=8, len=3 (4 beats), stall=3 on every beat, no corruption
  Checks: RVALID/RDATA stability on every beat of a burst

T5 - Length latch
  addr=2, len=2 (3 beats), stall=0, read_add_length inverted after AR handshake
  Checks: length is latched

T6 - Address + length latch with stall
  addr=5, len=2 (3 beats), stall=2, both read_add and read_add_length inverted
  Checks: address and length latching together, with back-pressure

T7 - Maximum burst
  addr=0, len=15 (16 beats), stall=0, no corruption
  Checks: longest burst, whole memory read

T8a - Back-to-back read, first
  addr=3, len=0 (1 beat), stall=0, no corruption

T8b - Back-to-back read, second
  addr=9, len=0 (1 beat), stall=0, no corruption
  T8a/T8b check: a new read is accepted right after a completed one

CHECKS DONE ON EVERY BEAT
  RDATA == memory[addr + beat]
  RRESP == 1
  RLAST == (beat == len)
  ARREADY low during the burst

CHECKS DONE ON EVERY BURST
  ARREADY drops right after the AR handshake
  RVALID low after the last beat
  ARREADY returns high within 5 cycles
  RVALID/RDATA stable during stall (only when stall > 0)
*/