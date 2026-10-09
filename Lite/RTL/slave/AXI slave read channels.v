module axi4_lite_read
#(
    parameter data_width = 32, 
    parameter add_width  = 4,  
    parameter add_num    = 16 
)
(
    input                           clk,
    input                           rst,

    input  [add_width - 1 : 0]      read_add,
    input                           read_add_valid,
    output reg                      read_add_ready,

    output reg [data_width - 1 : 0] read_data,
    output reg                      read_data_valid,
    output reg                      read_data_resp,
    input                           read_data_ready,

    // Memory-read interface (drives an external/shared memory array)
    output [add_width - 1 : 0]      mem_rd_addr,
    input  [data_width - 1 : 0]     mem_rd_data
);

reg [add_width  - 1 : 0] read_add_reg;

// Address presented to the shared memory: the latched address of the
// transfer currently being serviced.
assign mem_rd_addr = read_add_reg;


parameter [1:0]
idle               = 2'b00,
read_data_state    = 2'b01;

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
            if (read_add_valid && read_add_ready)
                next_state = read_data_state;
        end

        read_data_state: begin
            if (read_data_ready && read_data_valid)
                next_state = idle;
        end

        default:
            next_state = idle;

    endcase
end


always @(posedge clk) begin
    
    if(!rst) begin
        read_add_ready  <= 1;
        read_data_valid <= 0;
        read_data_resp  <= 0;

        read_data <= {data_width{1'b0}}; 
        read_add_reg <= {add_width{1'b0}} ;
    end
    
    else begin

        case(current_state)
        
        idle: begin
            read_data_valid <= 0;                           // to wait till a new address is received 
            read_data_resp  <= 0;

            if (read_add_valid && read_add_ready) begin
                read_add_reg <= read_add;
                read_add_ready <= 1'b0;   // about to move to read_data_state
            end 
            
            else begin
                read_add_ready <= 1'b1;
            end
            
        end 

        read_data_state: begin
            read_add_ready  <= 0;                           // not ready for new address to extract data off

            read_data       <= mem_rd_data;
            read_data_valid <= 1;                          // data is extracted succesfully out of memory
            read_data_resp  <= 1;                          // response to the current data exctracted of memory

            if (read_data_valid && read_data_ready) begin

                    read_data_valid <= 1'b0;

                end
        
        end 
        
        default: begin

            read_add_ready  <= 1'b1;
            read_data_valid <= 1'b0;
            read_data_resp  <= 1'b0;

        end
            

        endcase
    end
end




endmodule