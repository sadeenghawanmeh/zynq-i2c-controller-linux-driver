// Top level file for GPIO example for Xilinx XUP Blackboard rev D 
// (i2c_system_top.sv)
// Jason Losh
//
// 32-bit GPIO port:
//   AXI4-lite aperature memory offset is 0x00000000

module i2c_system_top(

    input CLK100,
    output [9:0] LED,       // RGB1, RGB0, LED 9..0 placed from left to right
    output [2:0] RGB0,      
    output [2:0] RGB1,
    output [3:0] SS_ANODE,   // Anodes 3..0 placed from left to right
    output [7:0] SS_CATHODE, // Bit order: DP, G, F, E, D, C, B, A
    input [11:0] SW,         // SWs 11..0 placed from left to right
    input [3:0] PB,          // PBs 3..0 placed from left to right
    inout [23:0] GPIO,       // PMODA-C 1P, 1N, ... 3P, 3N order
    output [3:0] SERVO,      // Servo outputs
    output PDM_SPEAKER,      // PDM signals for mic and speaker
    input PDM_MIC_DATA,      
    output PDM_MIC_CLK,
    output ESP32_UART1_TXD,  // WiFi/Bluetooth serial interface 1
    input ESP32_UART1_RXD,
    output IMU_SCLK,         // IMU spi clk
    output IMU_SDI,          // IMU spi data input
    input IMU_SDO_AG,        // IMU spi data output (accel/gyro)
    input IMU_SDO_M,         // IMU spi data output (mag)
    output IMU_CS_AG,        // IMU cs (accel/gyro) 
    output IMU_CS_M,         // IMU cs (mag)
    input IMU_DRDY_M,        // IMU data ready (mag)
    input IMU_INT1_AG,       // IMU interrupt (accel/gyro)
    input IMU_INT_M,         // IMU interrupt (mag)
    output IMU_DEN_AG,       // IMU data enable (accel/gyro)
    inout [14:0]DDR_addr,
    inout [2:0]DDR_ba,
    inout DDR_cas_n,
    inout DDR_ck_n,
    inout DDR_ck_p,
    inout DDR_cke,
    inout DDR_cs_n,
    inout [3:0]DDR_dm,
    inout [31:0]DDR_dq,
    inout [3:0]DDR_dqs_n,
    inout [3:0]DDR_dqs_p,
    inout DDR_odt,
    inout DDR_ras_n,
    inout DDR_reset_n,
    inout DDR_we_n,
    inout FIXED_IO_ddr_vrn,
    inout FIXED_IO_ddr_vrp,
    inout [53:0]FIXED_IO_mio,
    inout FIXED_IO_ps_clk,
    inout FIXED_IO_ps_porb,
    inout FIXED_IO_ps_srstb
    );
     
    // Terminate all of the unused outputs or i/o's
    // assign LED = 10'b0000000000;
    //assign RGB0 = 3'b000;
    //assign RGB1 = 3'b000;
    // assign SS_ANODE = 4'b0000;
    // assign SS_CATHODE = 8'b11111111;
    // assign GPIO = 24'bzzzzzzzzzzzzzzzzzzzzzzzz;
    assign SERVO = 4'b0000;
    assign PDM_SPEAKER = 1'b0;
    assign PDM_MIC_CLK = 1'b0;
    assign ESP32_UART1_TXD = 1'b0;
    assign IMU_SCLK = 1'b0;
    assign IMU_SDI = 1'b0;
    assign IMU_CS_AG = 1'b1;
    assign IMU_CS_M = 1'b1;
    assign IMU_DEN_AG = 1'b0;

    // display g (gpio) on left seven segment display
    assign SS_ANODE = 4'b0111;
    assign SS_CATHODE = 8'b10010000;

    // Tie gpio to PMOD connectors
    wire [31:0] gpio_data_in;
    wire [31:0] gpio_data_out;
    wire [31:0] gpio_data_oe;
   
    
   // assign LED[7:0] = i2c_LED;   // from i2c IP

    // pin control
    genvar j;
    for (j = 3; j < 22; j = j + 1)
        assign GPIO[j] = gpio_data_oe[j] ? gpio_data_out[j] : 1'bz;
    assign gpio_data_in = {8'b0, GPIO[23:3]};
  
        
    // Tie intr output to RGB0 green LED
    wire intr;
    //assign RGB0 = {1'b0, intr, 1'b0};
    
    wire [7:0] LED_index;
    wire [31:0] STATUS_OUT;
    
    wire i2c_SDA;
    wire i2c_SCL;
    wire i2c_TEST_OUT;
    
    wire scl_odr;
    wire sda_odr;
    wire sda_in;
    
    wire [3:0] debug_state;
    wire [5:0] debug_phase;
    wire       debug_ack;
    wire       debug_busy;
    
    //i2c pin
    /*assign GPIO[0] = i2c_SCL; // scl_odr ? 1'bz : 1'b0;
    assign GPIO[1] = i2c_SDA; // sda_odr ? 1'bz : 1'b0;*/
    assign GPIO[0] = scl_odr ? 1'bz : 1'b0;   // SCL open drain
    assign GPIO[1] = sda_odr ? 1'bz : 1'b0;   // SDA open drain
    assign GPIO[2] = i2c_TEST_OUT; 
    

    assign sda_in = GPIO[1];   // sample SDA
    
    assign LED[7:0] = LED_index;
    /*assign LED[0] = scl_odr;
    assign LED[1] = sda_odr;
    assign LED[2] = sda_in;*/
    
    /*assign LED[4] = STATUS_OUT[0];
    assign LED[5] = STATUS_OUT[1];
    assign LED[6] = STATUS_OUT[2];*/
    assign RGB0 [2:0] = {STATUS_OUT[2],STATUS_OUT[1],STATUS_OUT[0]};
   // assign RGB1 [2:0] = {STATUS_OUT[6],STATUS_OUT[5],STATUS_OUT[4]};
    assign RGB1 [0] = STATUS_OUT[6];

    // Instantiate system wrapper
    system_wrapper system (
        .DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .gpio_data_in(gpio_data_in),
        .gpio_data_out(gpio_data_out),
        .gpio_data_oe(gpio_data_oe),
        .STATUS_OUT(STATUS_OUT),
        .LED_index(LED_index),
        .i2c_SCL(i2c_SCL),
        .i2c_SDA(i2c_SDA),
        .i2c_TEST_OUT(i2c_TEST_OUT),
        .intr(intr),
        .scl_odr(scl_odr),
        .sda_odr(sda_odr),
        .sda_in(sda_in),
        .debug_state(debug_state),
        .debug_phase(debug_phase),
        .debug_ack(debug_ack),
        .debug_busy(debug_busy)
        );
        
    /*ila_0 i2c_ila (
        .clk(CLK100),                 
        .probe0(scl_odr),
        .probe1(sda_odr),
        .probe2(sda_in),
        .probe3(debug_state),
        .probe4(debug_phase),
        .probe5(debug_ack),
        .probe6(debug_busy)
        );*/
        
endmodule
