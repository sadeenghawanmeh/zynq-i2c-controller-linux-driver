/// AXI4-lite GPIO IP implementation
// (gpio_v1_0_AXI.v)
// AXI4-lite GPIO IP implementation
// (gpio_v1_0_AXI.v)
// Jason Losh based on Xilinx IP tool auto-generated file
//
// Contains:
// AXI4-lite interface
// GPIO memory-mapped interface
// GPIO port interface and implemention
// GPIO interrupt generation
`timescale 1 ns / 1 ps

    module i2c_slave_lite_v1_0_i2c_axi #
    (
        // Bit width of S_AXI address bus
        parameter integer C_S_AXI_ADDR_WIDTH = 5
    )
    (
        // Ports to top level module (what makes this the GPIO IP module)
        input wire [31:0] gpio_data_in,
        output wire [31:0] gpio_data_out,
        output wire [31:0] gpio_data_oe,
        output wire intr,
        
        //I2C Ports
        /*output wire [7:0] LED,
        output wire STATUS_OUT,*/  

        // TX FIFO
        output logic [7:0] tx_wr_data,      
        input  wire        tx_full,         
        input  wire        tx_empty,        
        input  wire        tx_overflow, 
        output logic       tx_clr_overflow_req, 

        // RX FIFO 
        input  wire [7:0] rx_rd_data,            
        input  wire       rx_full,         
        input  wire       rx_empty,        
        input  wire       rx_overflow, 
        output logic      rx_clr_overflow_req,

        output wire i2c_clk,
        output wire i2c_reset,
        output wire i2c_wr_request,
        input  wire [3:0] i2c_wr_index,
        output wire i2c_rd_request,
        input  wire [3:0] i2c_rd_index,
        input  wire i2c_busy,
        input  wire i2c_ack_error,

        output wire [31:0] i2c_status,
        output wire [31:0] i2c_control,
        output wire i2c_TEST_OUT,
        output wire [7:0] i2c_DEBUG_OUT,

        output logic        rd_wr,
        output logic [3:0]  BYTE_COUNT,
        output logic        USE_REGISTER,
        output logic        USE_REPEATED_START,
        output logic        START_pulse,
        output wire [6:0]  dev_addr,     // from ADDRESS[6:0]
        output wire [7:0]  reg_index,    // from REGISTER[7:0]
        output wire         en_200k,     //200 kHz tick to FSM

        // AXI clock and reset        
        input wire S_AXI_ACLK,
        input wire S_AXI_ARESETN,

        // AXI write channel
        // address:  add, protection, valid, ready
        // data:     data, byte enable strobes, valid, ready
        // response: response, valid, ready 
        input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
        input wire [2:0] S_AXI_AWPROT,
        input wire S_AXI_AWVALID,
        output wire S_AXI_AWREADY,
        
        input wire [31:0] S_AXI_WDATA,
        input wire [3:0] S_AXI_WSTRB,
        input wire S_AXI_WVALID,
        output wire  S_AXI_WREADY,
        
        output wire [1:0] S_AXI_BRESP,
        output wire S_AXI_BVALID,
        input wire S_AXI_BREADY,
        
        // AXI read channel
        // address: add, protection, valid, ready
        // data:    data, resp, valid, ready
        input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
        input wire [2:0] S_AXI_ARPROT,
        input wire S_AXI_ARVALID,
        output wire S_AXI_ARREADY,
        
        output wire [31:0] S_AXI_RDATA,
        output wire [1:0] S_AXI_RRESP,
        output wire S_AXI_RVALID,
        input wire S_AXI_RREADY
    );

    // Internal registers
    reg [31:0] latch_data;
    reg [31:0] out;
    reg [31:0] od;
    reg [31:0] int_enable;
    reg [31:0] int_positive;
    reg [31:0] int_negative;
    reg [31:0] int_edge_mode;
    reg [31:0] int_status;
    reg [31:0] int_clear_request;

    //i2c Internal registers
    reg [31:0] ADDRESS;
    reg [31:0] REGISTER;
    reg [31:0] DATA;
    reg [31:0] STATUS;
    reg [31:0] CONTROL;

    assign dev_addr  = ADDRESS[6:0];
    assign reg_index = REGISTER[7:0];

    reg wr_request, rd_request;
    assign i2c_wr_request = wr_request;
    assign i2c_rd_request = rd_request;

    reg [7:0] DEBUG_OUT;
    assign i2c_DEBUG_OUT = DEBUG_OUT;
    
    assign i2c_clk   = S_AXI_ACLK;
    assign i2c_reset = ~S_AXI_ARESETN;

    // Register map
    // ofs  fn
    //   0  data (r/w)
    //   4  out (r/w)
    //   8  od (r/w)
    //  12  int_enable (r/w)
    //  16  int_positive (r/w)
    //  20  int_negative (r/w)
    //  24  int_edge_mode (r/w)
    //  28  int_status_clear (r/w1c)
    
    // Register numbers
    localparam integer DATA_REG             = 3'b000;
    localparam integer OUT_REG              = 3'b001;
    localparam integer ODR_REG              = 3'b010;
    localparam integer INT_ENABLE_REG       = 3'b011;
    localparam integer INT_POSITIVE_REG     = 3'b100;
    localparam integer INT_NEGATIVE_REG     = 3'b101;
    localparam integer INT_EDGE_MODE_REG    = 3'b110;
    localparam integer INT_STATUS_CLEAR_REG = 3'b111;


    // Register map for i2c
    localparam integer i2c_ADDRESS_DEV      = 3'b000;
    localparam integer i2c_REGISTER         = 3'b001;
    localparam integer i2c_DATA_REG         = 3'b010;
    localparam integer i2c_STATUS_REG       = 3'b011;
    localparam integer i2c_CONTROL_REG      = 3'b100;
    
    // AXI4-lite signals
    reg axi_awready;
    reg axi_wready;
    reg [1:0] axi_bresp;
    reg axi_bvalid;
    reg axi_arready;
    reg [31:0] axi_rdata;
    reg [1:0] axi_rresp;
    reg axi_rvalid;
    
    // friendly clock, reset, and bus signals from master
    wire axi_clk           = S_AXI_ACLK;
    wire axi_resetn        = S_AXI_ARESETN;
    wire [31:0] axi_awaddr = S_AXI_AWADDR;
    wire axi_awvalid       = S_AXI_AWVALID;
    wire axi_wvalid        = S_AXI_WVALID;
    wire [3:0] axi_wstrb   = S_AXI_WSTRB;
    wire axi_bready        = S_AXI_BREADY;
    wire [31:0] axi_araddr = S_AXI_ARADDR;
    wire axi_arvalid       = S_AXI_ARVALID;
    wire axi_rready        = S_AXI_RREADY;    
    
    // assign bus signals to master to internal reg names
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;
    
    clk_en_200k u_clk_en (
        .axi_clk(axi_clk),
        .axi_resetn(axi_resetn),
        .en_200k(en_200k)
    );

    reg  st_tx_overflow;
    reg  st_rx_overflow;
    reg  st_ack_error;

    reg [31:0] STATUS_word;
    always @(*) begin
        STATUS_word[0] = rx_overflow;    //RXFO        //st_rx_overflow
        STATUS_word[1] = rx_full;        //RXFF
        STATUS_word[2] = rx_empty;       //RXFE
        STATUS_word[3] = tx_overflow;    //TXFO        //st_tx_overflow
        STATUS_word[4] = tx_full;        //TXFF        
        STATUS_word[5] = tx_empty;       //TXFE
        STATUS_word[6] = st_ack_error;   //ACK_ERROR;
        STATUS_word[7] = i2c_busy;       //BUSY;
        STATUS_word[31:8] = 24'b0;

    end
    assign i2c_status = STATUS_word;
    
    reg TEST_OUT;
    wire  test_out_en = TEST_OUT;            // gate 200 kHz TEST_OUT
    reg       start_req;
    reg [8:0] start_cnt;
    reg start_bit_reg;
    assign START_pulse = start_req;

    reg [31:0] CONTROL_word;
    always @(*) begin
        CONTROL_word[0]     = rd_wr;
        CONTROL_word[4:1]   = BYTE_COUNT;
        CONTROL_word[5]     = USE_REGISTER;
        CONTROL_word[6]     = USE_REPEATED_START;
        CONTROL_word[7]     = start_bit_reg;
        CONTROL_word[8]     = TEST_OUT;
        //CONTROL_word[31:9] = 23'b0;
        CONTROL_word[23:9]  = 15'b0;                   //reserved
        CONTROL_word[31:24]   = DEBUG_OUT;
    end
    assign i2c_control = CONTROL_word;

    assign i2c_TEST_OUT = test_out_en ? en_200k : 1'b0;

    // Handle gpio input metastability safely
    reg [31:0] read_port_data;          //reg [7:0] read_port_data;
    reg [31:0] pre_read_port_data;      //reg [7:0] pre_read_port_data;
    always_ff @ (posedge(axi_clk))
    begin
        pre_read_port_data <= {24'd0, rx_rd_data};   //from FIFO or just rx_rd_data?
        read_port_data <= pre_read_port_data;
    end

    reg [31:0] write_port_data;
   /* reg [31:0] pre_write_port_data;
    always_ff @ (posedge(axi_clk))
    begin
        pre_write_port_data <= fifo_wr_data;
        read_port_data <= pre_write_port_data;
    end*/
    
    //assign i2c_data_out = write_port_data;
    
    // Assert address ready handshake (axi_awready) 
    // - after address is valid (axi_awvalid)
    // - after data is valid (axi_wvalid)
    // - while configured to receive a write (aw_en)
    // De-assert ready (axi_awready)
    // - after write response channel ready handshake received (axi_bready)
    // - after this module sends write response channel valid (axi_bvalid) 
    wire wr_add_data_valid = axi_awvalid && axi_wvalid;
    reg aw_en;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end
        else
        begin
            if (wr_add_data_valid && ~axi_awready && aw_en)
            begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end
            else if (axi_bready && axi_bvalid)
                begin
                    aw_en <= 1'b1;
                    axi_awready <= 1'b0;
                end
            else           
                axi_awready <= 1'b0;
        end 
    end

    // Capture the write address (axi_awaddr) in the first clock (~axi_awready)
    // - after write address is valid (axi_awvalid)
    // - after write data is valid (axi_wvalid)
    // - while configured to receive a write (aw_en)
    reg [C_S_AXI_ADDR_WIDTH-1:0] waddr;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
            waddr <= 0;
        else if (wr_add_data_valid && ~axi_awready && aw_en)
            waddr <= axi_awaddr;
    end

    // Output write data ready handshake (axi_wready) generation for one clock
    // - after address is valid (axi_awvalid)
    // - after data is valid (axi_wvalid)
    // - while configured to receive a write (aw_en)
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
            axi_wready <= 1'b0;
        else
            axi_wready <= (wr_add_data_valid && ~axi_wready && aw_en);
    end       

    // Write data to internal registers
    // - after address is valid (axi_awvalid)
    // - after write data is valid (axi_wvalid)
    // - after this module asserts ready for address handshake (axi_awready)
    // - after this module asserts ready for data handshake (axi_wready)
    // write correct bytes in 32-bit word based on byte enables (axi_wstrb)
    // int_clear_request write is only active for one clock


    /*
    // STATUS sticky bits (W1C)
    reg        st_rx_overflow;      // STATUS[0] RXFO 
    reg        st_tx_overflow;      // STATUS[3] TXFO 
    reg        st_ack_error;        // STATUS[6] ACK_ERROR*/

    wire wr = wr_add_data_valid && axi_awready && axi_wready;
    integer byte_index;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            ADDRESS [31:0]  <= 32'b0;
            REGISTER [31:0] <= 32'b0;
            DATA [31:0]     <= 32'b0;
            STATUS [31:0]   <= 32'b0;
            CONTROL [31:0]  <= 32'b0;

            rd_wr              <= 1'b0;
            BYTE_COUNT         <= 4'd0;
            USE_REGISTER       <= 1'b0;
            USE_REPEATED_START <= 1'b0;
            start_req          <= 1'b0;
            start_cnt          <= 9'd0;
            start_bit_reg      <= 1'b0;
            TEST_OUT           <= 1'b0;
            DEBUG_OUT          <= 8'd0;

            wr_request          <= 1'b0;
            tx_wr_data          <= 8'h00;
            tx_clr_overflow_req <= 1'b0;
            rx_clr_overflow_req <= 1'b0;
            st_ack_error        <= 1'b0;
        end 
        else 
        begin
            tx_clr_overflow_req <= 1'b0;
            wr_request <= 1'b0;
            rx_clr_overflow_req <= 1'b0;

            if(i2c_ack_error)
                st_ack_error <= 1'b1;

            if(start_req) begin   //stretch start
                if(start_cnt == 9'd499) begin
                        start_req <= 1'b0;
                        start_cnt <= 9'd0;
                        start_bit_reg <= 1'b0;
                end else begin
                    start_cnt <= start_cnt + 1'b1;
                end
            end

            if (wr)
            begin
                case (waddr[4:2])            //or waddr /axi_awaddr[4:2]
                    i2c_ADDRESS_DEV:    //I think it should be without the for loop since it's only 6-bit
                    begin
                        /*for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1) 
                                ADDRESS[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];*/
                        if (axi_wstrb[0]) ADDRESS[6:0] <= S_AXI_WDATA[6:0];     //{25'd0, S_AXI_WDATA[6:0]}
                    end
                    i2c_REGISTER:       // again no loop it's only 8 bits
                    begin
                        /*for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1) 
                                REGISTER[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];*/
                        if (axi_wstrb[0]) REGISTER[7:0] <= S_AXI_WDATA[7:0];    //{24'd0, S_AXI_WDATA[7:0]}
                    end
                    i2c_DATA_REG:       // should be 8 bits wide
                    begin
                        wr_request <= 1'b1;
                        /*for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1) 
                                fifo_wr_data[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];*/
                        if (axi_wstrb[0]) tx_wr_data <= S_AXI_WDATA[7:0];
                    end                      
                    i2c_STATUS_REG:
                    begin
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1) 
                                STATUS[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                        if(S_AXI_WDATA[0])  //clr RXFO
                            rx_clr_overflow_req  <= 1'b1;
                        if(S_AXI_WDATA[3])  //clr TXFO
                            tx_clr_overflow_req  <= 1'b1;
                        if(S_AXI_WDATA[6])  //clr ACK_ERROR
                            st_ack_error <= 1'b0;
                    end
                    i2c_CONTROL_REG:
                    begin
                        /*for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1) 
                                CONTROL[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];*/
                        if (axi_wstrb[0]) 
                        begin
                            rd_wr              <= S_AXI_WDATA[0];
                            BYTE_COUNT         <= S_AXI_WDATA[4:1];
                            USE_REGISTER       <= S_AXI_WDATA[5];
                            USE_REPEATED_START <= S_AXI_WDATA[6];

                            start_bit_reg      <= S_AXI_WDATA[7];
                
                            if (S_AXI_WDATA[7] && !i2c_busy  ) begin     // maybe if(S_AXI_WDATA[7] && !i2c_busy)
                                //START_pulse <= 1'b1;   
                                start_req <= 1'b1;        // start a new stretched pulse
                                start_cnt <= 9'd0;
                            end
                        end
                            if (axi_wstrb[1])
                                TEST_OUT  <= S_AXI_WDATA[8];
                            if (axi_wstrb[3]) begin
                                DEBUG_OUT <= S_AXI_WDATA[31:24];
                            end
                        end
                endcase
            end
            else
            begin

            end
        end
    end    

    // Send write response (axi_bvalid, axi_bresp)
    // - after address is valid (axi_awvalid)
    // - after write data is valid (axi_wvalid)
    // - after this module asserts ready for address handshake (axi_awready)
    // - after this module asserts ready for data handshake (axi_wready)
    // Clear write response valid (axi_bvalid) after one clock
    wire wr_add_data_ready = axi_awready && axi_wready;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_bvalid  <= 0;
            axi_bresp   <= 2'b0;
        end 
        else
        begin    
            if (wr_add_data_valid && wr_add_data_ready && ~axi_bvalid)
            begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0;
            end
            else if (S_AXI_BREADY && axi_bvalid) 
                axi_bvalid <= 1'b0; 
        end
    end   

    // In the first clock (~axi_arready) that the read address is valid
    // - capture the address (axi_araddr)
    // - output ready (axi_arready) for one clock
    reg [C_S_AXI_ADDR_WIDTH-1:0] raddr;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_arready <= 1'b0;
            raddr <= 32'b0;
        end 
        else
        begin    
            // if valid, pulse ready (axi_rready) for one clock and save address
            if (axi_arvalid && ~axi_arready)
            begin
                axi_arready <= 1'b1;
                raddr  <= axi_araddr;
            end
            else
                axi_arready <= 1'b0;
        end 
    end       
        
    // Update register read data
    // - after this module receives a valid address (axi_arvalid)
    // - after this module asserts ready for address handshake (axi_arready)
    // - before the module asserts the data is valid (~axi_rvalid)
    //   (don't change the data while asserting read data is valid)
    wire rd = axi_arvalid && axi_arready && ~axi_rvalid;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_rdata <= 32'b0;
            rd_request <= 1'b0;


        end 
        else
        begin 
            rd_request <= 1'b0;

            if (rd)
            begin
		// Address decoding for reading registers
		case (raddr[4:2])
		    i2c_ADDRESS_DEV: 
		        axi_rdata <= ADDRESS;
		    i2c_REGISTER:
		        axi_rdata <= REGISTER;
		    i2c_DATA_REG: 
            begin
                rd_request <= 1'b1;
		        axi_rdata <= read_port_data;
            end
		    i2c_STATUS_REG: 
			    axi_rdata <= STATUS_word;
            i2c_CONTROL_REG:
                axi_rdata <= CONTROL_word;
            default:
                axi_rdata <= 32'd0;
		endcase
            end
         else  
            rd_request  <= 1'b0;
        end
    end    

    // Assert data is valid for reading (axi_rvalid)
    // - after address is valid (axi_arvalid)
    // - after this module asserts ready for address handshake (axi_arready)
    // De-assert data valid (axi_rvalid) 
    // - after master ready handshake is received (axi_rready)
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
            axi_rvalid <= 1'b0;
        else
        begin
            if (axi_arvalid && axi_arready && ~axi_rvalid)
            begin
                axi_rvalid <= 1'b1;
                axi_rresp <= 2'b0;
            end   
            else if (axi_rvalid && axi_rready)
                axi_rvalid <= 1'b0;
        end
    end    

    // pin control
    // OUT LATCH ODR   PIN
    //  0    x    x    hi-Z
    //  1    0    x     0
    //  1    1    0     1
    //  1    1    1    hi-Z
    genvar j;
    for (j = 0; j < 32; j = j + 1)
    begin
        assign gpio_data_oe[j] = out[j] && (!latch_data[j] || !od[j]);
    end
    assign gpio_data_out = latch_data;
    
    // Interrupt generation
    integer i;
    reg [31:0] last_read_port_data;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            last_read_port_data <= 32'b0;
            int_status <= 32'b0;
        end
        else if (int_clear_request != 32'b0)
            int_status <= int_status & ~int_clear_request;
        else
        begin
            last_read_port_data <= read_port_data;
            for (i = 0; i < 32; i = i + 1)
            begin
                if (int_enable[i])
                begin
                    if (int_edge_mode[i])
                    begin
                        if (int_positive[i] && read_port_data[i] && !last_read_port_data[i])
                            int_status[i] <= 1'b1;
                        if (int_negative[i] && !read_port_data[i] && last_read_port_data[i])
                            int_status[i] <= 1'b1;
                    end
                    else
                    begin
                        if (int_positive[i] && read_port_data[i])
                            int_status[i] <= 1'b1;
                        if (int_negative[i] && !read_port_data[i])
                            int_status[i] <= 1'b1;
                    end
                end
            end
        end
    end
    assign intr = int_status != 32'b0;
    
endmodule
module clk_en_200k(
    input axi_clk,
    input axi_resetn,
    output reg en_200k);
    
    reg [8:0] count;
    
    always_ff @ (posedge(axi_clk))
    begin
        if(!axi_resetn)begin
            count <= 0;
            en_200k <= 0;
        end else begin
            en_200k <= 0;
            if (count == 9'd499)
            begin
            count <= 0;
            en_200k <= 1;
            end
            else
            begin
                count <= count + 1;
                en_200k <= 0;
            end
        end
    end    
endmodule