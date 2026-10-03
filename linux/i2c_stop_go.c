#include <stdint.h>         
#include <stdio.h>           
#include <stdbool.h>         
#include <fcntl.h>           
#include <sys/mman.h>        
#include <unistd.h>          
#include "../address_map.h"  
#include "gpio_ip.h"         
#include "gpio_regs.h"  

//OFFSETS
//#define MAP_SPAN        0x00010000u   // 64 KB typical for AXI-Lite IP
#define AXI4_LITE_BASE     0x43C00000
#define I2C_BASE_OFFSET    0x20000

#define ADDRESS_OFFSET     0
#define REGISTER_OFFSET    1
#define DATA_OFFSET        2
#define STATUS_OFFSET      3
#define CONTROL_OFFSET     4

#define RXFO      (1u << 0)
//#define RXFF      (1u << 1)
//#define RXFE      (1u << 2)
#define TXFO      (1u << 3)
//#define TXFF      (1u << 4)
//#define TXFE      (1u << 5)
#define ACK_ERR   (1u << 6)
#define BUSY      (1u << 7)

#define MCP_ADDR    0x20         // MCP23008 address 
#define OLAT        0x0A
#define IODIR       0x00
#define GPIO        0x09
#define GPPU        0x06                

#define RED_BIT    0  // GP0
#define YELLOW_BIT   1  // GP1
#define PB_BIT     2  // GP2 push button

#define CTRL_WRITE_1BYTE_REG  0x000001A2u  //rd_wr=0, byte_count=1, use_reg=1, rep=0, start=1, test_out=1
#define CTRL_READ_1BYTE_REG   0x000001E3u  // rd_wr=1, byte_count=1, use_reg=1, rep=1, start=1

// Global variables
uint8_t wr_index;
uint8_t rd_index;
uint32_t *base = NULL;bool gpioOpen()
{
    // Open /dev/mem
    int file = open("/dev/mem", O_RDWR | O_SYNC);
    bool bOK = (file >= 0);
    if (bOK)
    {
        // Create a map from the physical memory location of
        // /dev/mem at an offset to LW avalon interface
        // with an aperature of SPAN_IN_BYTES bytes
        // to any location in the virtual 32-bit memory space of the process
        base = mmap(NULL, SPAN_IN_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED,
                    file, AXI4_LITE_BASE + I2C_BASE_OFFSET);
        bOK = (base != MAP_FAILED);

        // Close /dev/mem
        close(file);
    }
    return bOK;
}



void address_dev(uint8_t addr7)
{
    volatile uint32_t *r = (volatile uint32_t *) (base + ADDRESS_OFFSET);
    *r = (uint32_t)(addr7 & 0x7F); //7-bits
}

void reg(uint8_t reg_index)
{
    volatile uint32_t *r = (volatile uint32_t *) (base + REGISTER_OFFSET);
    *r = (uint32_t) reg_index;
}
void wr_data(uint8_t wr_data) {
    volatile uint32_t *r = (volatile uint32_t *) (base + DATA_OFFSET);
    *r = (uint32_t)wr_data;
}

uint8_t rd_data(void)
{ 
    volatile uint32_t *r = (volatile uint32_t *)(base + DATA_OFFSET);
    return (uint8_t)(*r);
}
uint32_t status_reg(void)
{
    volatile uint32_t *r = (volatile uint32_t *) (base + STATUS_OFFSET);
    return *r;
}
void write_status(uint32_t value) //to clear
{
    volatile uint32_t *r = (volatile uint32_t *)(base + STATUS_OFFSET);
    *r = value;
}

void control_reg(uint32_t value)
{
    volatile uint32_t *r = (volatile uint32_t *) (base + CONTROL_OFFSET);
    *r = value;
}

void i2c_clear_errors(void)
{
    write_status(RXFO | TXFO | ACK_ERR);
}

void i2c_wait_not_busy(void)
{
    while (status_reg() & BUSY);

}
void delay_ms(uint32_t ms) {
    volatile uint32_t i;
    while (ms--) {
        for (i = 0; i < 50000; i++);
    }
}

/////////////////////////////////////
void print_status(const char *msg) {
    uint32_t s = status_reg();
    printf("%s: STATUS = 0x%08X  (ACK_ERR=%d, BUSY=%d)\n",
           msg, s,
           (s & ACK_ERR) != 0,
           (s & BUSY) != 0);
}
/////////////////////////////////////

// Write 1 byte to (dev_addr, reg_addr)
void i2c_write_reg(uint8_t dev_addr, uint8_t reg_addr, uint8_t value)
{
    i2c_clear_errors();

    address_dev(dev_addr);
    //print_status("After sending address");
    reg(reg_addr);
    //print_status("After sending register");
    wr_data(value);
    //print_status("After sending data");
    control_reg(CTRL_WRITE_1BYTE_REG);
    i2c_wait_not_busy();
}

// Read 1 byte from (dev_addr, reg_addr)
uint8_t i2c_read_reg(uint8_t dev_addr, uint8_t reg_addr)
{
    i2c_clear_errors();

    address_dev(dev_addr);
    reg(reg_addr);

    control_reg(CTRL_READ_1BYTE_REG);
    i2c_wait_not_busy();

    return rd_data();
}


int main(void)
{
    if (!gpioOpen()) { 
        printf("Unable to open GPIO\n");
        return -1;
    }
    
    printf("i2c_stop_go: program started\n");

    // initial delay
    delay_ms(2000);

    uint8_t iodir = 0x00;
    iodir |= (1 << PB_BIT);          //0b0000_0100 PB is input
    //iodir &= ~(1 << RED_BIT);
    //iodir &= ~(1<< YELLOW_BIT);
    i2c_write_reg(MCP_ADDR,IODIR,iodir);

    delay_ms(5);

    uint8_t gppu = 0x00;
    gppu |= (1 << PB_BIT);      //pull-up on PB
    i2c_write_reg(MCP_ADDR,GPPU,gppu);

    delay_ms(5);

    uint8_t led_state = 0;
    uint8_t led = 0x00;
    led = (1<< RED_BIT);        //initialy
    i2c_write_reg(MCP_ADDR,GPIO,led);

    delay_ms(5);

    i2c_read_reg(MCP_ADDR,GPIO);

    delay_ms(5);

    uint8_t pb_prev = 1;

    while(1)
    {
        uint8_t PB = i2c_read_reg(MCP_ADDR,GPIO);
        //printf("rd_data: 0x%02X\n", rd_data());

        uint8_t pb_now = (PB >> PB_BIT) & 0x1; //read GP2

        if(pb_prev == 0  &&  pb_now == 1)
        {
            led_state ^= 1;

            if(led_state == 0)
                led = (1 << RED_BIT);
            else
                led = (1 << YELLOW_BIT);
            
            i2c_write_reg(MCP_ADDR, GPIO, led);
        }
        pb_prev = pb_now;

        delay_ms(50);
    }

    return 0;
}