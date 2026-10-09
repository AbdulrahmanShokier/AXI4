//=============================================================================
// axi4_master : burst master for the axi4_slave
//   - rst is ACTIVE-LOW, burst length field: beats = length + 1
//   - Write: outside data comes in on write_data_out / write_data_valid_out,
//            the master forwards it to the slave W channel (no storage)
//   - Read : each beat from the slave R channel goes out on read_data_out
//   - Pulse start_write_out / start_read_out for one cycle when not busy.
//     A start while busy is ignored.
//   - *_done_out is a one-cycle pulse; *_error_out is valid at done and holds
//     until the next start (bad BRESP / bad RRESP / RLAST mismatch)
//=============================================================================
module axi4_master
#(
    parameter data_width = 32,
    parameter add_width  = 4,
    parameter len_width  = 4
)
(
    input                           clk,
    input                           rst,

    // Simple control interface : write
    input                           start_write_out,
    input      [add_width  - 1 : 0] write_add_out,
    input      [len_width  - 1 : 0] write_length_out,
    input      [data_width - 1 : 0] write_data_out,
    input                           write_data_valid_out,
    output                          write_data_ready_out,
    output                          write_busy_out,
    output                          write_done_out,
    output reg                      write_error_out,

    // Simple control interface : read
    input                           start_read_out,
    input      [add_width  - 1 : 0] read_add_out,
    input      [len_width  - 1 : 0] read_length_out,
    output     [data_width - 1 : 0] read_data_out,
    output                          read_data_valid_out,
    input                           read_data_ready_out,
    output                          read_data_last_out,
    output                          read_busy_out,
    output                          read_done_out,
    output reg                      read_error_out,

    // AXI4 slave interface : write
    output     [add_width  - 1 : 0] write_add,             // to slave
    output                          write_add_valid,
    input                           write_add_ready,
    output     [len_width  - 1 : 0] write_add_length,

    output     [data_width - 1 : 0] write_data,            // to slave
    output                          write_data_valid,
    input                           write_data_ready,
    output                          write_data_last,

    input                           write_resp,            // from slave
    input                           write_resp_valid,
    output                          write_resp_ready,

    // AXI4 slave interface : read
    output     [add_width  - 1 : 0] read_add,              // to slave
    output                          read_add_valid,
    input                           read_add_ready,
    output     [len_width  - 1 : 0] read_add_length,

    input      [data_width - 1 : 0] read_data,             // from slave
    input                           read_data_valid,
    input                           read_data_resp,
    output                          read_data_ready,
    input                           read_data_last
);

reg [add_width - 1 : 0] write_add_reg;
reg [len_width - 1 : 0] write_len_reg;
reg [len_width - 1 : 0] write_counter;

reg [add_width - 1 : 0] read_add_reg;
reg [len_width - 1 : 0] read_len_reg;
reg [len_width - 1 : 0] read_counter;

parameter [2:0]
idle_write         = 3'b000,
write_add_state    = 3'b001,
write_data_state   = 3'b010,
write_resp_state   = 3'b011,
write_done_state   = 3'b100;

parameter [1:0]
idle_read          = 2'b00,
read_add_state     = 2'b01,
read_data_state    = 2'b10,
read_done_state    = 2'b11;

reg [2:0] current_state_write, next_state_write;
reg [1:0] current_state_read,  next_state_read;


//=============================================================================
// WRITE
//=============================================================================

// VALIDs depend on the state / outside source only, never on the slave READY
assign write_add         = write_add_reg;
assign write_add_length  = write_len_reg;
assign write_add_valid   = (current_state_write == write_add_state);

assign write_data        = write_data_out;
assign write_data_valid  = (current_state_write == write_data_state) && write_data_valid_out;
assign write_data_last   = (current_state_write == write_data_state) && (write_counter == write_len_reg);
assign write_data_ready_out = (current_state_write == write_data_state) && write_data_ready;

assign write_resp_ready  = (current_state_write == write_resp_state);

assign write_busy_out    = (current_state_write != idle_write);
assign write_done_out    = (current_state_write == write_done_state);


always @(posedge clk) begin

    if(!rst)
        current_state_write <= idle_write;
    else
        current_state_write <= next_state_write;
end


always @(*) begin

    next_state_write = current_state_write;

    case (current_state_write)

        idle_write: begin
            if (start_write_out)
                next_state_write = write_add_state;
        end

        write_add_state: begin
            if (write_add_valid && write_add_ready)
                next_state_write = write_data_state;
        end

        write_data_state: begin
            if (write_data_valid && write_data_ready && (write_counter == write_len_reg))
                next_state_write = write_resp_state;
        end

        write_resp_state: begin
            if (write_resp_valid && write_resp_ready)
                next_state_write = write_done_state;
        end

        write_done_state:
            next_state_write = idle_write;

        default:
            next_state_write = idle_write;

    endcase
end


always @(posedge clk) begin

    if(!rst) begin
        write_add_reg   <= {add_width{1'b0}};
        write_len_reg   <= {len_width{1'b0}};
        write_counter   <= {len_width{1'b0}};
        write_error_out <= 1'b0;
    end

    else begin

        case(current_state_write)

        idle_write: begin
            if (start_write_out) begin
                write_add_reg   <= write_add_out;
                write_len_reg   <= write_length_out;
                write_counter   <= {len_width{1'b0}};
                write_error_out <= 1'b0;
            end
        end

        write_data_state: begin
            if (write_data_valid && write_data_ready) begin
                if (write_counter != write_len_reg)
                    write_counter <= write_counter + 1'b1;
            end
        end

        write_resp_state: begin
            if (write_resp_valid && write_resp_ready) begin
                if (write_resp !== 1'b1)
                    write_error_out <= 1'b1;
            end
        end

        default: ;

        endcase
    end
end


//=============================================================================
// READ
//=============================================================================

assign read_add             = read_add_reg;
assign read_add_length      = read_len_reg;
assign read_add_valid       = (current_state_read == read_add_state);

// RREADY follows the outside sink, data passes straight through
assign read_data_ready      = (current_state_read == read_data_state) && read_data_ready_out;
assign read_data_out        = read_data;
assign read_data_valid_out  = (current_state_read == read_data_state) && read_data_valid;
assign read_data_last_out   = read_data_last;

assign read_busy_out        = (current_state_read != idle_read);
assign read_done_out        = (current_state_read == read_done_state);


always @(posedge clk) begin

    if(!rst)
        current_state_read <= idle_read;
    else
        current_state_read <= next_state_read;
end


always @(*) begin

    next_state_read = current_state_read;

    case (current_state_read)

        idle_read: begin
            if (start_read_out)
                next_state_read = read_add_state;
        end

        read_add_state: begin
            if (read_add_valid && read_add_ready)
                next_state_read = read_data_state;
        end

        read_data_state: begin
            if (read_data_valid && read_data_ready && (read_counter == read_len_reg))
                next_state_read = read_done_state;
        end

        read_done_state:
            next_state_read = idle_read;

        default:
            next_state_read = idle_read;

    endcase
end


always @(posedge clk) begin

    if(!rst) begin
        read_add_reg   <= {add_width{1'b0}};
        read_len_reg   <= {len_width{1'b0}};
        read_counter   <= {len_width{1'b0}};
        read_error_out <= 1'b0;
    end

    else begin

        case(current_state_read)

        idle_read: begin
            if (start_read_out) begin
                read_add_reg   <= read_add_out;
                read_len_reg   <= read_length_out;
                read_counter   <= {len_width{1'b0}};
                read_error_out <= 1'b0;
            end
        end

        read_data_state: begin
            if (read_data_valid && read_data_ready) begin

                if (read_data_resp !== 1'b1)
                    read_error_out <= 1'b1;

                if (read_data_last !== (read_counter == read_len_reg))
                    read_error_out <= 1'b1;

                if (read_counter != read_len_reg)
                    read_counter <= read_counter + 1'b1;
            end
        end

        default: ;

        endcase
    end
end


endmodule