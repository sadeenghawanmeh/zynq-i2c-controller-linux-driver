

`timescale 1 ns / 1 ps

	module i2c #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface i2c_axi
		parameter integer C_i2c_axi_DATA_WIDTH	= 32,
		parameter integer C_i2c_axi_ADDR_WIDTH	= 5
	)
	(
		// Users to add ports here
        output wire [7:0] LED_index,
        output wire [31:0] STATUS_OUT,

        inout  wire         i2c_SCL,
        inout  wire         i2c_SDA,
        output wire         i2c_TEST_OUT,
        output wire scl_odr,
        output wire sda_odr,
        input  wire sda_in,
        
        output [3:0] debug_state,
        output [5:0] debug_phase,
        output debug_ack,
        output debug_busy,

		// User ports ends
		// Do not modify the ports beyond this line

		// Ports of Axi Slave Bus Interface i2c_axi
		input wire  i2c_axi_aclk,
		input wire  i2c_axi_aresetn,
		input wire [C_i2c_axi_ADDR_WIDTH-1 : 0] i2c_axi_awaddr,
		input wire [2 : 0] i2c_axi_awprot,
		input wire  i2c_axi_awvalid,
		output wire  i2c_axi_awready,
		input wire [C_i2c_axi_DATA_WIDTH-1 : 0] i2c_axi_wdata,
		input wire [(C_i2c_axi_DATA_WIDTH/8)-1 : 0] i2c_axi_wstrb,
		input wire  i2c_axi_wvalid,
		output wire  i2c_axi_wready,
		output wire [1 : 0] i2c_axi_bresp,
		output wire  i2c_axi_bvalid,
		input wire  i2c_axi_bready,
		input wire [C_i2c_axi_ADDR_WIDTH-1 : 0] i2c_axi_araddr,
		input wire [2 : 0] i2c_axi_arprot,
		input wire  i2c_axi_arvalid,
		output wire  i2c_axi_arready,
		output wire [C_i2c_axi_DATA_WIDTH-1 : 0] i2c_axi_rdata,
		output wire [1 : 0] i2c_axi_rresp,
		output wire  i2c_axi_rvalid,
		input wire  i2c_axi_rready
	);
	    
    /*wire scl_odr;  
    wire sda_odr;   
    wire sda_in;    */

    /*assign i2c_SCL = scl_odr ? 1'bz : 1'b0;
    assign i2c_SDA = sda_odr ? 1'bz : 1'b0;
    assign sda_in = i2c_SDA;*/

    wire i2c_wr_request;
    wire i2c_rd_request;

    wire [3:0] i2c_wr_index;
    wire [3:0] i2c_rd_index;
    wire [31:0] i2c_status;
    wire [31:0] i2c_control; 
    wire [7:0]  i2c_DEBUG_OUT;
    wire        i2c_busy, i2c_ack_error;
    
    // TX FIFO side (AXI to FIFO)
    wire [7:0]  tx_wr_data;           // from AXI to TX FIFO
    wire        tx_wr_request,tx_rd_request;        // from AXI to TX FIFO
    wire        tx_full, tx_empty;
    wire        tx_overflow;
    wire        tx_clr_overflow_req;  //from AXI to TX FIFO
    wire [3:0]  tx_wr_index, tx_rd_index;

    // TX FIFO side (FIFO to FSM)
    wire [7:0]  tx_rd_data;           // to FSM
    wire        tx_pop;               //from FSM to TX FIFO rd_request

    // RX FIFO side (FSM to FIFO)
    wire [7:0]  rx_wr_data;           // from FSM
    wire        rx_push;              //from FSM to RX FIFO wr_request
    wire        rx_full, rx_empty;
    wire        rx_overflow;
    wire        rx_clr_overflow_req;  // from AXI to RX FIFO
    wire        rx_wr_request, rx_rd_request;
    wire [3:0]  rx_wr_index, rx_rd_index;

    // RX FIFO side (FIFO to AXI)
    wire [7:0]  rx_rd_data;           // to AXI
    wire        rx_pop;               //AXI pop (i2c_rd_request)

    // Control fields from AXI to FSM
    wire        rd_wr;
    wire [3:0]  BYTE_COUNT;
    wire        USE_REGISTER;
    wire        USE_REPEATED_START;
    wire        START_pulse;
    wire [6:0]  dev_addr;
    wire [7:0]  reg_index;

    wire        en_200k;

   // assign i2c_clk   = i2c_axi_aclk;
   // assign i2c_reset = ~i2c_axi_aresetn;   // AXI active-low to active-high
    
// Instantiation of Axi Bus Interface i2c_axi
	i2c_slave_lite_v1_0_i2c_axi # ( 
		//.C_S_AXI_DATA_WIDTH(C_i2c_axi_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_i2c_axi_ADDR_WIDTH)
	) i2c_slave_lite_v1_0_i2c_axi_inst (
		.S_AXI_ACLK(i2c_axi_aclk),
		.S_AXI_ARESETN(i2c_axi_aresetn),
		.S_AXI_AWADDR(i2c_axi_awaddr),
		.S_AXI_AWPROT(i2c_axi_awprot),
		.S_AXI_AWVALID(i2c_axi_awvalid),
		.S_AXI_AWREADY(i2c_axi_awready),
		.S_AXI_WDATA(i2c_axi_wdata),
		.S_AXI_WSTRB(i2c_axi_wstrb),
		.S_AXI_WVALID(i2c_axi_wvalid),
		.S_AXI_WREADY(i2c_axi_wready),
		.S_AXI_BRESP(i2c_axi_bresp),
		.S_AXI_BVALID(i2c_axi_bvalid),
		.S_AXI_BREADY(i2c_axi_bready),
		.S_AXI_ARADDR(i2c_axi_araddr),
		.S_AXI_ARPROT(i2c_axi_arprot),
		.S_AXI_ARVALID(i2c_axi_arvalid),
		.S_AXI_ARREADY(i2c_axi_arready),
		.S_AXI_RDATA(i2c_axi_rdata),
		.S_AXI_RRESP(i2c_axi_rresp),
		.S_AXI_RVALID(i2c_axi_rvalid),
		.S_AXI_RREADY(i2c_axi_rready),

        .tx_wr_data(tx_wr_data),
        .tx_full(tx_full),
        .tx_empty(tx_empty),
        .tx_overflow(tx_overflow),
        .tx_clr_overflow_req(tx_clr_overflow_req),

        .rx_rd_data(rx_rd_data),
        .rx_full(rx_full),
        .rx_empty(rx_empty),
        .rx_overflow(rx_overflow),
        .rx_clr_overflow_req(rx_clr_overflow_req),

        .i2c_clk(i2c_axi_aclk),
        .i2c_reset(~i2c_axi_aresetn),
        .i2c_wr_request(tx_wr_request),
        .i2c_rd_request(rx_rd_request),
        .i2c_wr_index(i2c_wr_index),
        .i2c_rd_index(i2c_rd_index),
        .i2c_busy(i2c_busy),
        .i2c_ack_error(i2c_ack_error),

        .i2c_status(i2c_status),
        .i2c_control(i2c_control),
        .i2c_TEST_OUT(i2c_TEST_OUT),
        .i2c_DEBUG_OUT(i2c_DEBUG_OUT),

        .rd_wr(rd_wr),
        .BYTE_COUNT(BYTE_COUNT),
        .USE_REGISTER(USE_REGISTER),
        .USE_REPEATED_START(USE_REPEATED_START),
        .START_pulse(START_pulse),
        .dev_addr(dev_addr),
        .reg_index(reg_index),
        .en_200k(en_200k)
	);

	// Add user logic here
        fifo tx_fifo(
            .clk                    (i2c_axi_aclk),
            .reset                  (~i2c_axi_aresetn),
            .wr_data                (tx_wr_data),
            .wr_request             (tx_wr_request),   //i2c_wr_request tx_wr_request
            .rd_data                (tx_rd_data),
            .rd_request             (tx_rd_request),   //tx_pop
            .empty                  (tx_empty),
            .full                   (tx_full),
            .overflow               (tx_overflow),
            .clear_overflow_request (tx_clr_overflow_req),
            .wr_index               (tx_wr_index),
            .rd_index               (tx_rd_index) 
        );

        fifo rx_fifo(
            .clk                    (i2c_axi_aclk),
            .reset                  (~i2c_axi_aresetn),
            .wr_data                (rx_wr_data),
            .wr_request             (rx_wr_request),
            .rd_data                (rx_rd_data),
            .rd_request             (rx_rd_request),   //i2c_rd_request
            .empty                  (rx_empty),
            .full                   (rx_full),
            .overflow               (rx_overflow),
            .clear_overflow_request (rx_clr_overflow_req),
            .wr_index               (rx_wr_index),
            .rd_index               (rx_rd_index) 
        );

        i2c_fsm u_fsm(
            .clk(i2c_axi_aclk),
            .reset(~i2c_axi_aresetn),
            .en_200k(en_200k),

            .rd_wr(rd_wr),              
            .BYTE_COUNT(BYTE_COUNT),
            .USE_REGISTER(USE_REGISTER),
            .USE_REPEATED_START(USE_REPEATED_START),
            .START_pulse(START_pulse),
            .dev_addr(dev_addr),
            .reg_index(reg_index),

            .BUSY(i2c_busy),
            .ACK_ERROR(i2c_ack_error),

            /*.i2c_SDA(i2c_SDA),     
            .i2c_SCL(i2c_SCL),*/
            .scl_odr(scl_odr),
            .sda_odr(sda_odr),
            .sda_in(sda_in),


            //TX FIFO
            .tx_empty(tx_empty),
            .tx_data(tx_rd_data),
            .tx_pop(tx_rd_request),

            //RX FIFO
            .rx_full(rx_full),
            .rx_data(rx_wr_data),
            .rx_push(rx_wr_request),
            .debug_state(debug_state),
            .debug_phase(debug_phase),
            .debug_ack(debug_ack),
            .debug_busy(debug_busy)
        );

        assign LED_index [3:0] = tx_wr_index;  
        assign LED_index [7:4] = rx_rd_index;
        
        assign STATUS_OUT[7:0] = {i2c_busy,i2c_ack_error,tx_empty, tx_full, tx_overflow,rx_empty, rx_full, rx_overflow};
        assign STATUS_OUT[31:8] = 24'd0;  //debug_in
        
	// User logic ends

	endmodule

