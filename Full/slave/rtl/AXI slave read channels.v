module axi4_read
#(
    parameter data_width = 32, 
    parameter add_width  = 4,  
    parameter len_width  = 4 
)
(
    input                           clk,
    input                           rst,

    input  [add_width - 1 : 0]      read_add,
    input                           read_add_valid,
    output reg                      read_add_ready,
    input  [len_width - 1 : 0]      read_add_length,
     

    output reg [data_width - 1 : 0] read_data,
    output reg                      read_data_valid,
    output reg                      read_data_resp,
    input                           read_data_ready,
    output reg                      read_data_last,

    // Memory-read interface (drives an external/shared memory array)
    output [add_width - 1 : 0]      mem_rd_addr,
    input  [data_width - 1 : 0]     mem_rd_data
);

reg [add_width  - 1 : 0] read_add_reg;


reg [len_width  - 1 : 0] read_counter;


reg [len_width-1:0] read_len_reg;


// Address presented to the shared memory: the latched address of the
// transfer currently being serviced.
assign mem_rd_addr = read_add_reg + read_counter + (read_data_valid & read_data_ready);



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

    read_data_last = 1'b0;

    case (current_state)

        idle: begin
            if (read_add_valid && read_add_ready)
                next_state = read_data_state;
        end

        read_data_state: begin

            if (read_counter == read_len_reg)
                read_data_last = 1'b1;

            if (read_data_ready && read_data_valid) begin
                if (read_counter == read_len_reg)
                    next_state = idle;
            end

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

        read_data       <= {data_width{1'b0}}; 
        read_add_reg    <= {add_width{1'b0}} ;

        read_counter    <= 0;
        read_len_reg    <= 0;
    end
    
    else begin

        case(current_state)
        
        idle: begin
            read_data_valid <= 0;                           // to wait till a new address is received 
            read_data_resp  <= 0;

            if (read_add_valid && read_add_ready) begin
                read_add_reg    <= read_add;
                read_len_reg    <= read_add_length;
                read_add_ready  <= 1'b0;   // about to move to read_data_state
                read_counter    <= 0;
            end 
            
            else begin
                read_add_ready <= 1'b1;
            end
            
        end 

        read_data_state: begin
            read_add_ready  <= 0;                           // not ready for new address to extract data off

            if (!read_data_valid || read_data_ready)
                read_data <= mem_rd_data;
                
            read_data_valid <= 1;                          // data is extracted succesfully out of memory
            read_data_resp  <= 1;                          // response to the current data exctracted of memory

            if (read_data_valid && read_data_ready) begin

                if (read_counter == read_len_reg) begin
                    read_data_valid <= 1'b0;
                end
                else begin
                    read_counter <= read_counter + 1'b1;
                end

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