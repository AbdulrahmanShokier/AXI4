module axi4_lite_slave
#(
    parameter data_width = 32,
    parameter add_width  = 4,
    parameter add_num    = 16
)
(
    input                            clk,
    input                            rst,     // active-LOW

    // Write address channel
    input  [add_width  - 1 : 0]      write_add,
    input                            write_add_valid,
    output                           write_add_ready,

    // Write data channel
    input  [data_width - 1 : 0]      write_data,
    input                            write_data_valid,
    output                           write_data_ready,

    // Write response channel
    output                           write_resp,
    output                           write_resp_valid,
    input                            write_resp_ready,

    // Read address channel
    input  [add_width  - 1 : 0]      read_add,
    input                            read_add_valid,
    output                           read_add_ready,

    // Read data channel
    output [data_width - 1 : 0]      read_data,
    output                           read_data_valid,
    output                           read_data_resp,
    input                            read_data_ready
);

    //-------------------------------------------------------------------
    // Shared memory, written by the write channel and read by the read
    // channel. Synchronous write, combinational (same-cycle) read -
    // standard single-port RAM behavior. On a same-cycle read/write to
    // the same address the read returns the OLD value (write-first would
    // require extra bypass logic, not needed here).
    //-------------------------------------------------------------------
    reg [data_width - 1 : 0] memory [0 : add_num - 1];

    wire                     mem_wr_en;
    wire [add_width - 1 : 0] mem_wr_addr;
    wire [data_width - 1 : 0] mem_wr_data;

    wire [add_width - 1 : 0]  mem_rd_addr;
    wire [data_width - 1 : 0] mem_rd_data;

    always @(posedge clk) begin
        if (mem_wr_en)
            memory[mem_wr_addr] <= mem_wr_data;
    end

    assign mem_rd_data = memory[mem_rd_addr];

    //-------------------------------------------------------------------
    // Write channel
    //-------------------------------------------------------------------
    axi4_lite_write #(
        .data_width (data_width),
        .add_width  (add_width),
        .add_num    (add_num)
    ) u_write (
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

        .mem_wr_en        (mem_wr_en),
        .mem_wr_addr      (mem_wr_addr),
        .mem_wr_data      (mem_wr_data)
    );

    //-------------------------------------------------------------------
    // Read channel
    //-------------------------------------------------------------------
    axi4_lite_read #(
        .data_width (data_width),
        .add_width  (add_width),
        .add_num    (add_num)
    ) u_read (
        .clk              (clk),
        .rst              (rst),

        .read_add         (read_add),
        .read_add_valid   (read_add_valid),
        .read_add_ready   (read_add_ready),

        .read_data        (read_data),
        .read_data_valid  (read_data_valid),
        .read_data_resp   (read_data_resp),
        .read_data_ready  (read_data_ready),

        .mem_rd_addr      (mem_rd_addr),
        .mem_rd_data      (mem_rd_data)
    );

endmodule