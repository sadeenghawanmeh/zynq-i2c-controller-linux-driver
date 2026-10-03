`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/23/2025 07:23:03 PM
// Design Name: 
// Module Name: fifo
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module fifo(
    input              clk,
    input              reset,
    input       [7:0]  wr_data,
    input              wr_request,
    output      [7:0]  rd_data,
    input              rd_request,
    output             empty,
    output             full,
    output reg         overflow,
    input              clear_overflow_request,
    output reg  [3:0]  wr_index,   
    output reg  [3:0]  rd_index    
    );

    reg [7:0] mem [0:15];
    assign empty = (wr_index == rd_index);  
    assign full  = ((wr_index + 4'd1) == rd_index);
    assign rd_data = mem[rd_index];
    
    // Previous values for edge detection
    reg wr_request_pre;
    reg rd_request_pre;

    // Rising-edge pulses
    wire wr_pulse =  wr_request & ~wr_request_pre;   
    wire rd_pulse =  rd_request & ~rd_request_pre;   
    
    always_ff @(posedge clk) begin
        if (reset) begin
            wr_index  <= 4'd0;
            rd_index  <= 4'd0;
            wr_request_pre  <= 1'b0;
            rd_request_pre  <= 1'b0;
           // rd_data  <= 8'd0;   
            overflow  <= 1'b0;
        end 
        else begin
            wr_request_pre<= wr_request;
            rd_request_pre <= rd_request;
            // Clear overflow if requested
            if (clear_overflow_request) begin
                overflow <= 1'b0;
            end
            // WRITE requested and not full
            if (wr_pulse) begin
                if (!full) begin
                    mem[wr_index] <= wr_data;
                    wr_index      <= wr_index + 4'd1;  // modulo 16
                end 
                else begin
                    //full => set overflow flag
                    overflow <= 1'b1;
                end
            end
            // READ request and not empty
            if (rd_pulse && !empty) begin
               // rd_data  <= mem[rd_index];
                rd_index <= rd_index + 4'd1;
            end
        end
    end
endmodule
