module axi4_lite_write
#(
    parameter data_width = 32, 
    parameter add_width  = 4,  
    parameter add_num    = 16 
)
(
    input                           clk,
    input                           rst,

    input  [add_width - 1 : 0]      write_add,
    input                           write_add_valid,
    output reg                      write_add_ready,
    
    input  [data_width - 1 : 0]     write_data,
    input                           write_data_valid,
    output reg                      write_data_ready,

    output reg                      write_resp,
    output reg                      write_resp_valid,
    input                           write_resp_ready,

    // Memory-write interface (drives an external/shared memory array)
    output reg                      mem_wr_en,
    output reg [add_width - 1 : 0]  mem_wr_addr,
    output reg [data_width - 1 : 0] mem_wr_data
);

reg [add_width  - 1 : 0] write_add_reg;

reg [data_width - 1 : 0] write_data_reg;

reg add_received_flag;          // a flag to indicate is the address is received or not yet


parameter [1:0]
idle             = 2'b00,
write_data_state = 2'b01,
//write_add_state  = 2'b10;

reg [1:0] current_state, next_state;


always @(posedge clk) begin
    
    if(!rst)
        current_state <= idle;
    else
        current_state <= next_state;
end


always @(*) begin

    next_state = current_state;

    case (current_state)

        idle: begin
            if (!write_add_ready && !write_data_ready)
                next_state = write_data_state;

            else
                next_state = idle;
        end

        // write_add_state: begin
        //     if (write_data_valid && write_data_ready)
        //         next_state = write_data_state;
        // end
        
        write_data_state: begin

            if (write_resp_valid && write_resp_ready)
                next_state = idle;

        end

        default:
            next_state = idle;

    endcase
end


always @(posedge clk) begin
    
    if(!rst) begin
        write_add_ready   <= 1;
        write_data_ready  <= 1;
        
        add_received_flag <= 0;

        write_resp_valid  <= 0;

        write_add_reg     <= {add_width{1'b0}}  ; 
        write_data_reg    <= {data_width{1'b0}} ;

        mem_wr_en         <= 1'b0;
        mem_wr_addr       <= {add_width{1'b0}};
        mem_wr_data       <= {data_width{1'b0}};
    end
    
    else begin

        case(current_state)
        
        idle: begin
        write_resp_valid  <= 0;
        write_resp        <= 0;
        mem_wr_en         <= 1'b0;   // default: no memory write in idle

            if (write_add_valid && write_add_ready) begin
                write_add_reg     <= write_add;
                add_received_flag <= 1;
                write_add_ready   <= 1'b0;  
            end

            if (write_data_valid && write_data_ready) begin
                write_data_reg   <= write_data;
                write_data_ready <= 1'b0;  
            end        
        end 

        write_data_state: begin

            mem_wr_en <= 1'b0;   // default: pulse for exactly one cycle below

            if (add_received_flag) begin
                mem_wr_en   <= 1'b1;
                mem_wr_addr <= write_add_reg;
                mem_wr_data <= write_data_reg;

                write_resp            <= 1;
                write_resp_valid      <= 1;

                add_received_flag <= 0;
            end

            if (write_resp && write_resp_ready) begin
                write_add_ready       <= 1'b1;
                write_data_ready      <= 1'b1;
            end
        end 
        
        default: begin

        write_add_ready   <= 1;
        write_data_ready  <= 1;
        
        add_received_flag <= 0;

        write_resp_valid  <= 0;
        mem_wr_en         <= 1'b0;

        end
            

        endcase
    end
end




endmodule