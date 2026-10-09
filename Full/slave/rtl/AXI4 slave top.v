//=============================================================================
// axi4_slave : top level of the AXI4 burst slave
//   - axi4_write : write channels (AW / W / B), bursts of (length + 1) beats
//   - axi4_read  : read channels  (AR / R),     bursts of (length + 1) beats
//   - one shared memory array (sync write, combinational read)
//
// rst is ACTIVE-LOW.
// Same-cycle read/write of the same address returns the OLD value.
// Addresses wrap modulo 2**add_width (add_num must equal 2**add_width).
//=============================================================================
module axi4_slave
#(
    parameter data_width = 32,
    parameter add_width  = 4,
    parameter len_width  = 4,
    parameter add_num    = 16
)
(
    input                            clk,
    input                            rst,

    // Write address channel
    input  [add_width  - 1 : 0]      write_add,
    input                            write_add_valid,
    output                           write_add_ready,
    input  [len_width  - 1 : 0]      write_add_length,

    // Write data channel
    input  [data_width - 1 : 0]      write_data,
    input                            write_data_valid,
    output                           write_data_ready,
    input                            write_data_last,

    // Write response channel
    output                           write_resp,
    output                           write_resp_valid,
    input                            write_resp_ready,

    // Read address channel
    input  [add_width  - 1 : 0]      read_add,
    input                            read_add_valid,
    output                           read_add_ready,
    input  [len_width  - 1 : 0]      read_add_length,

    // Read data channel
    output [data_width - 1 : 0]      read_data,
    output                           read_data_valid,
    output                           read_data_resp,
    input                            read_data_ready,
    output                           read_data_last
);

    //-------------------------------------------------------------------
    // Shared memory
    //-------------------------------------------------------------------
    reg [data_width - 1 : 0] memory [0 : add_num - 1];

    wire                      mem_wr_en;
    wire [add_width  - 1 : 0] mem_wr_addr;
    wire [data_width - 1 : 0] mem_wr_data;

    wire [add_width  - 1 : 0] mem_rd_addr;
    wire [data_width - 1 : 0] mem_rd_data;

    always @(posedge clk)
        if (mem_wr_en)
            memory[mem_wr_addr] <= mem_wr_data;

    assign mem_rd_data = memory[mem_rd_addr];

    //-------------------------------------------------------------------
    // Write channels
    //-------------------------------------------------------------------
    axi4_write #(
        .data_width (data_width),
        .add_width  (add_width),
        .len_width  (len_width)
    ) u_write (
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

    //-------------------------------------------------------------------
    // Read channels
    //-------------------------------------------------------------------
    axi4_read #(
        .data_width (data_width),
        .add_width  (add_width),
        .len_width  (len_width)
    ) u_read (
        .clk              (clk),
        .rst              (rst),

        .read_add         (read_add),
        .read_add_valid   (read_add_valid),
        .read_add_ready   (read_add_ready),
        .read_add_length  (read_add_length),

        .read_data        (read_data),
        .read_data_valid  (read_data_valid),
        .read_data_resp   (read_data_resp),
        .read_data_ready  (read_data_ready),
        .read_data_last   (read_data_last),

        .mem_rd_addr      (mem_rd_addr),
        .mem_rd_data      (mem_rd_data)
    );

endmodule