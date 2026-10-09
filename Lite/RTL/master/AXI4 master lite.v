module axi4_lite_master
#(
    parameter data_width = 32, 
    parameter add_width  = 4,  
    parameter add_num    = 16 
)
(
    input                           clk,
    input                           rst,

    // Simple control interface
    input                           start_write_out,
    input      [add_width  - 1 : 0] write_add_out,
    input      [data_width - 1 : 0] write_data_out,
    output reg                      write_done_out,

    input                           start_read_out,
    input      [add_width  - 1 : 0] read_add_out,
    output reg [data_width - 1 : 0] read_data_out,
    output reg                      read_done_out,
    

    // AXI4-Lite slave interface
    
    output reg  [add_width - 1 : 0] read_add,            // to slave
    input                           read_add_ready,
    output reg                      read_add_valid,

    input      [data_width - 1 : 0] read_data,           // from slave
    input                           read_data_valid,
    input                           read_data_resp,
    output reg                      read_data_ready,

    output reg  [add_width - 1 : 0] write_add,           // to slave
    input                           write_add_ready,
    output reg                      write_add_valid,
    
    output reg [data_width - 1 : 0] write_data,          // to slave
    input                           write_data_ready,
    output reg                      write_data_valid,

    input                           write_resp,          // to slave
    input                           write_resp_valid,
    output reg                      write_resp_ready
);

reg [add_width  - 1 : 0] read_add_reg   ;

reg add_received_flag;
reg data_received_flag;

parameter [2:0]
idle_read          = 3'b000,
read_add_state     = 3'b001,
read_data_state    = 3'b010;

parameter [2:0]
idle_write         = 3'b001,
write_transfer_state   = 3'b100;



reg [2:0] current_state_read, next_state_read;
reg [2:0] current_state_write, next_state_write;


always @(posedge clk) begin
    
    if(!rst)
        current_state_read <= idle_read;
    else
        current_state_read <= next_state_read;
end


always @(posedge clk) begin
    
    if(!rst)
        current_state_write <= idle_write;
    else
        current_state_write <= next_state_write;
end

reg busy_read;

 always @(*) begin

    next_state_read = current_state_read;

    case (current_state_read)

        idle_read: begin
            busy_read = 0;
            if (start_read_out)
                next_state_read = read_add_state;

            else
                next_state_read = idle_read;
        end

        read_add_state: begin
            busy_read = 1;
            if (read_add_ready && read_add_valid)
                next_state_read = read_data_state;

            else
                next_state_read = read_add_state;
        end

        read_data_state: begin
            busy_read = 1;
            if (read_data_ready && read_data_valid)
                next_state_read = idle_read;

            else
                next_state_read = read_data_state;
        end

        default:
        begin
            busy_read       = 0;
            next_state_read = idle_read;
        end
    endcase
end   

reg busy_write;

always @(*) begin

    next_state_write = current_state_write;

    case (current_state_write)

        idle_write: begin
            busy_write = 0;
            if (start_write_out)
                next_state_write = write_transfer_state;

            else
                next_state_write = idle_write;
        end
        
        write_transfer_state: begin
            busy_write = 1;
            if (write_resp_valid && write_resp_ready)
                next_state_write = idle_write;
        end

        default:
        begin
            busy_write       = 0;
            next_state_write = idle_write;
        end
    endcase
end


always @(posedge clk) begin
    
    if(!rst) begin
        read_add_valid  <= 0;
        read_data_ready <= 1;

        read_done_out   <= 0;
        read_data_out   <= 0;

        read_add        <= 0;

    end

    else begin

        if(start_read_out && (!busy_read)) begin
        read_add        <= read_add_out;
        read_add_valid  <= 1;
        read_data_out   <= 0;
        
        end 

        case(current_state_read)
        
        idle_read: begin
            read_data_ready <= 0; 
            read_done_out   <= 0;       
        end 

        read_add_state: begin
            read_data_ready <= 0;
            
            if(read_add_valid && read_add_ready) begin
                read_add_valid  <= 0;
            end
        end

        read_data_state: begin
            read_data_ready <= 1;
            if (read_data_valid && read_data_ready) begin
                read_data_out <= read_data;
                read_done_out <= 1;
            end
        end

        endcase

    end
end


always @(posedge clk) begin
    
    if(!rst) begin
        write_add_valid    <= 0;
        write_data_valid   <= 0;

        write_add        <= 0;
        write_data       <= 0;
        
        add_received_flag  <= 0;
        data_received_flag <= 0;

        write_resp_ready   <= 0;

        write_done_out     <= 0;

    end
    
    else begin
        write_done_out <= 0;

        if (start_write_out && (!busy_write)) begin
            write_add        <= write_add_out;
            write_data       <= write_data_out;
            write_add_valid  <= 1 ;
            write_data_valid <= 1 ;
        end

        case(current_state_write)
        
        idle_write: begin 
            write_done_out      <= 0;       
        end 

        write_transfer_state: begin

            if (write_add_valid && write_add_ready) begin
                add_received_flag <= 1;
                write_add_valid   <= 0;  
            end

            if (write_data_valid && write_data_ready) begin
                data_received_flag <= 1;
                write_data_valid   <= 0;  
            end

            if (data_received_flag && add_received_flag) begin
                write_resp_ready   <= 1;
            end

            if (write_resp_valid && write_resp_ready) begin
                add_received_flag   <= 0;
                data_received_flag  <= 0;
                write_done_out      <= 1;
                write_resp_ready    <= 0;
            end
        end 
        
        default: begin
        write_add_valid    <= 0;
        write_data_valid   <= 0;
        
        add_received_flag  <= 0;
        data_received_flag <= 0;

        write_resp_ready   <= 0;
        end
            

        endcase
    end
end


endmodule