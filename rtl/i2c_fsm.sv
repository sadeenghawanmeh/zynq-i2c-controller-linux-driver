`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/19/2025 07:29:16 PM
// Design Name: 
// Module Name: i2c_fsm
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

module i2c_fsm(
    input wire  clk,
    input wire  reset,
    input wire  en_200k,

    input wire  rd_wr,              //1 read, 0 write
    input wire  [3:0] BYTE_COUNT,
    input wire  USE_REGISTER,
    input wire  USE_REPEATED_START,
    input wire  START_pulse,
    input wire  [6:0] dev_addr,
    input wire  [7:0] reg_index,

    output reg BUSY,
    output reg ACK_ERROR,

    /*inout i2c_SDA,        //open-drain
    inout i2c_SCL,*/

    output reg  scl_odr,   // 0 = drive low, 1 = release
    output reg  sda_odr,   // 0 = drive low, 1 = release
    input  wire sda_in,    

    output reg [3:0] debug_state,
    output reg [5:0] debug_phase,
    output reg       debug_ack,
    output reg       debug_busy,

    //TX FIFO
    input wire tx_empty,
    input wire [7:0] tx_data,
    output reg tx_pop,

    //RX FIFO
    input wire rx_full,
    output reg [7:0] rx_data,
    output reg rx_push
);
    reg [3:0] state;
    reg [5:0] phase;        //from 0 to 17 (17 for data & 1 for ack)
    reg [3:0] count;
    reg [2:0] bit_index;
    reg [7:0] tx_shift_reg;
    reg [7:0] rx_shift_reg;

    reg restart_after_stop;

    /*reg scl_odr;            //open-drain
    reg sda_odr;
    assign i2c_SCL = scl_odr ? 1'bz : 1'b0;
    assign i2c_SDA = sda_odr ? 1'bz : 1'b0;
    wire sda_in = i2c_SDA; */ // for read i2c_SDA

    //wire tick = en_200k;

    parameter IDLE         = 4'd0;
    parameter START        = 4'd1;
    parameter ADDR_WRITE   = 4'd2;
    parameter REG_SEND     = 4'd3;
    parameter WRITE_BYTES  = 4'd4;
    parameter REP_START    = 4'd5;
    parameter ADDR_READ    = 4'd6;
    parameter READ_BYTES   = 4'd7;
    parameter STOP_COND    = 4'd8;

    always_ff @(posedge clk) 
     begin
        if (reset) 
        begin
            state       <= IDLE;
            BUSY        <= 1'b0;
            ACK_ERROR   <= 1'b0;

            phase       <= 6'd0;
            count       <= 4'b0;
            bit_index   <= 3'd7;

            scl_odr     <= 1'b1;   
            sda_odr     <= 1'b1;

            tx_shift_reg<= 8'h00;
            rx_shift_reg<= 8'h00;

            rx_data     <= 8'h00;
            tx_pop       <= 1'b0;
            rx_push      <= 1'b0;

            restart_after_stop <= 1'b0;
        end
        else begin
            if(en_200k) begin
                tx_pop  <= 1'b0;
                rx_push <= 1'b0;
                case(state)
                    IDLE:
                    begin
                        BUSY      <= 1'b0;
                       //ACK_ERROR <= 1'b0;
                        phase     <= 6'd0;
                        count     <= 4'b0;
                        bit_index <= 3'd7;

                        scl_odr   <= 1'b1;
                        sda_odr   <= 1'b1;

                        restart_after_stop <= 1'b0;

                        if(START_pulse) begin
                            BUSY        <= 1'b1;
                            count       <= BYTE_COUNT;
                            phase       <= 6'd0;
                            //sda_odr     <= 1'b0; // drive SDA low start_cond
                            //scl_odr     <= 1'b1; // keep SCL released high
                            state       <= START;
                        end
                    end
                    START:
                    begin
                        restart_after_stop <= 1'b0;  //after entering stop - start
                        case(phase)
                        0:
                        begin
                            /*sda_odr <= 1'b1; 
                            scl_odr <= 1'b1;
                            phase   <= 6'd1;*/
                            scl_odr     <= 1'b1; // keep SCL released high
                            sda_odr     <= 1'b0; // drive SDA low start_cond
                            phase       <= 6'd1;
                        end
                        1:
                        begin
                            scl_odr     <= 1'b1; // keep SCL released high
                            sda_odr     <= 1'b0; 
                            phase       <= 6'd0;

                            if(rd_wr && !USE_REGISTER) begin                 //if read and no user_reg
                                tx_shift_reg <= {dev_addr, 1'b1};
                                state  <= ADDR_READ;
                            end else if (!rd_wr || USE_REGISTER) begin       // if write or read with user_reg
                                tx_shift_reg <= {dev_addr, 1'b0};              
                                state  <= ADDR_WRITE;
                            end
                        end
                        endcase
                    end
                    ADDR_WRITE:
                    begin
                        //tx_shift_reg <= {dev_addr, 1'b0};       //device address, 0 for write 8bits total
                        case (phase)
                        0,2,4,6,8,10,12,14: 
                        begin
                            scl_odr <= 1'b0;    //low for data
                            sda_odr <= tx_shift_reg[bit_index];
                            phase <= phase +1;
                            bit_index <= bit_index - 3'b1;
                        end
                        1,3,5,7,9,11,13,15: 
                        begin
                            scl_odr <= 1'b1;    // hold data
                            phase <= phase + 6'd1;
                        end
                        16:                     // for ACK
                        begin
                            scl_odr <= 1'b0;
                            sda_odr <= 1'b1;    //released
                            phase <= 6'd17;
                        end
                        17: 
                        begin
                            scl_odr <= 1'b1;
                            ACK_ERROR <= sda_in; //ACK =0, NACK =1
                            phase <= 6'd0;
                            bit_index <= 3'd7;

                            if(sda_in) begin    
                                state <= STOP_COND;  //IDLE or STOP?
                            end else if(USE_REGISTER) begin
                                    tx_shift_reg <= reg_index;
                                    state        <= REG_SEND;
                            end else begin
                                    if(count == 0) state <= STOP_COND;
                                    else begin
                                        if(!tx_empty) begin
                                            tx_shift_reg <= tx_data;
                                            tx_pop <= 1'b1;
                                        end
                                        state <= WRITE_BYTES;
                                    end
                            end                       
                        end
                        endcase
                    end
                    REG_SEND:
                    begin
                        case(phase)
                        0,2,4,6,8,10,12,14: begin
                            scl_odr <= 1'b0;    //low for data
                            sda_odr <= tx_shift_reg[bit_index];
                            phase <= phase +6'd1;
                            bit_index <= bit_index - 3'b1;
                        end
                        1,3,5,7,9,11,13,15: begin
                            scl_odr <= 1'b1;    // hold data
                            phase <= phase + 6'd1;
                        end
                        16:begin
                            scl_odr <= 1'b0;
                            sda_odr <= 1'b1;
                            phase <= 6'd17;
                        end
                        17: begin
                            scl_odr <= 1'b1;
                            ACK_ERROR <= sda_in; //ACK =0, NACK =1
                            phase <= 6'd0;
                            bit_index <= 3'd7;
                        
                            if(sda_in)
                                state <= STOP_COND;
                            else if (!rd_wr) begin
                                if(count == 0) state <= STOP_COND;
                                else begin
                                    if(!tx_empty) begin
                                        tx_shift_reg <= tx_data;
                                        tx_pop <= 1'b1;
                                    end
                                    state <= WRITE_BYTES;
                                end
                            end else begin
                                if(USE_REPEATED_START) begin
                                    state <= REP_START;
                                end else if(!USE_REPEATED_START)begin
                                    restart_after_stop <= 1'b1;
                                    state  <= STOP_COND; //if not repeated_start stop then start again ?
                                end
                            end
                        end
                        endcase
                    end
                    WRITE_BYTES:
                    begin
                        //tx_shift_reg <= {tx_data};  //8 bits data
                        case (phase)
                        0,2,4,6,8,10,12,14: 
                        begin
                            scl_odr <= 1'b0;    //low for data
                            sda_odr <= tx_shift_reg[bit_index];
                            phase <= phase +1;
                            bit_index <= bit_index - 3'b1;
                        end
                        1,3,5,7,9,11,13,15: 
                        begin
                            scl_odr <= 1'b1;    // hold data
                            phase <= phase + 6'd1;
                        end
                        16:                     // for ACK
                        begin
                            scl_odr <= 1'b0;
                            sda_odr <= 1'b1;
                            phase <= 6'd17;
                        end
                        17: 
                        begin
                            scl_odr <= 1'b1;
                            ACK_ERROR <= sda_in; //ACK =0, NACK =1
                            phase <= 6'd0;
                            bit_index <= 3'd7;
                            if(sda_in) begin
                                state <= STOP_COND;   //IDLE or STOP ?
                            end else begin
                                if(count == 1) begin
                                    state <= STOP_COND;
                                end else begin
                                    count <= count - 1;
                                    if(!tx_empty) begin
                                        tx_shift_reg <= tx_data;
                                        tx_pop <= 1'b1;
                                    end
                                        state <= WRITE_BYTES; //stays in write
                                end
                            end
                        end
                        endcase
                    end
                    REP_START:
                    begin
                        //START Condition again
                        case(phase)
                        0:
                        begin
                            scl_odr <= 1'b0;
                            sda_odr <= 1'b1;
                            phase   <= 6'd1;
                        end
                        1:
                        begin
                            scl_odr <= 1'b1;
                            phase   <= 6'd2;
                        end
                        2:
                        begin
                            sda_odr <= 0;
                            tx_shift_reg <= {dev_addr, 1'b1};
                            bit_index <= 7;
                            phase <= 0;
                            state <= ADDR_READ;
                        end
                        endcase
                    end
                    ADDR_READ:
                    begin
                        //tx_shift_reg <= {dev_addr, 1'b1};       //device address, 1 for read
                        case (phase)
                        0,2,4,6,8,10,12,14: 
                        begin
                            scl_odr <= 1'b0;    //low for data
                            sda_odr <= tx_shift_reg[bit_index];
                            phase <= phase +1;
                            bit_index <= bit_index - 3'b1;
                        end
                        1,3,5,7,9,11,13,15: 
                        begin
                            scl_odr <= 1'b1;    // hold data
                            phase <= phase + 6'd1;
                        end
                        16:                     // for ACK
                        begin
                            scl_odr <= 1'b0;
                            sda_odr <= 1'b1;    // released
                            phase <= 6'd17;
                        end
                        17: 
                        begin
                            scl_odr <= 1'b1;
                            ACK_ERROR <= sda_in; //ACK =0, NACK =1
                            phase <= 6'd0;
                            bit_index <= 3'd7;
                            if(sda_in) begin
                                state <= STOP_COND;
                            end else begin
                                if(count == 0) begin
                                    state <= STOP_COND; //or IDLE
                                end else
                                    state <= READ_BYTES;
                            end
                        end
                        endcase
                    end
                    READ_BYTES:
                    begin
                        case (phase)
                        0,2,4,6,8,10,12,14: 
                        begin
                            scl_odr <= 1'b0;    //low for data
                            sda_odr <= 1'b1;
                            phase <= phase +1;
                        end
                        1,3,5,7,9,11,13,15: 
                        begin
                            scl_odr <= 1'b1;    // hold data
                            rx_shift_reg[bit_index] <= sda_in;
                            phase <= phase +1;
                            bit_index <= bit_index - 3'b1;
                        end
                        16:                      // send ACK
                        begin
                            scl_odr <= 1'b0;
                            sda_odr <= (count == 4'd1) ? 1'b1 : 1'b0;  // ACK low for more bytes, NACK high on last
                            phase <= 17;
                        end
                        17: 
                        begin
                            scl_odr <= 1'b1;
                            rx_data <= rx_shift_reg;
                            rx_push <= 1'b1;
                            phase <= 0;
                            bit_index <= 3'd7;
                            if(count == 1)
                                state <= STOP_COND;
                            else begin
                                count <= count - 1;
                                state <= READ_BYTES;
                            end
                        end
                        endcase
                    end
                    STOP_COND:
                    begin
                        //STOP CONDITION
                        case(phase)
                        0: 
                        begin
                            scl_odr <= 1'b0;      
                            sda_odr <= 1'b0;     // drive low
                            phase <= 6'd1;
                        end
                        1:
                        begin
                            scl_odr <= 1'b1;    
                            sda_odr <= 1'b0;      // SDA low 
                            phase <= 6'd2;
                        end
                        2:
                        begin
                            scl_odr <= 1'b1;
                            sda_odr <= 1'b1;      // SDA high (STOP)
                            phase   <= 6'd0;

                            /*if(restart_after_stop) begin
                                state  <= START;    // maybe
                                BUSY   <= 1'b1;
                            end else begin
                                state <= IDLE;
                                BUSY  <= 1'b0;
                            end*/
                            state <= IDLE;
                            BUSY  <= 1'b0;
                        end
                        endcase
                    end
                    default:
                        state <= IDLE;
                endcase
            end
        end
    end
endmodule