#include <linux/kernel.h>     // kstrtouint
#include <linux/module.h>     // MODULE_ macros
#include <linux/init.h>       // __init
#include <linux/kobject.h>    // kobject, kobject_atribute,
                              // kobject_create_and_add, kobject_put
#include <asm/io.h>           // iowrite, ioread, ioremap_nocache (platform specific)
#include "../address_map.h"   // overall memory map
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/types.h>
#include <linux/delay.h>
//#include "i2c_driver.h"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Sadeen");
MODULE_DESCRIPTION("MCP23008 I2C Expander Driver");

//-----------------------------------------------------------------------------
// Global variables
//-----------------------------------------------------------------------------

static unsigned int *base = NULL;

//-----------------------------------------------------------------------------
// Registers
//-----------------------------------------------------------------------------

#define AXI4_LITE_BASE     0x43C00000
#define I2C_BASE_OFFSET    0x20000
#define I2C_SPAN_IN_BYTES  32

#define ADDRESS_OFFSET     0
#define REGISTER_OFFSET    1
#define DATA_OFFSET        2
#define STATUS_OFFSET      3
#define CONTROL_OFFSET     4

// MCP23008 registers
#define MCP_ADDR   0x20
#define IODIR   0x00
#define GPPU    0x06
#define GPIO    0x09
#define OLAT    0x0A

// CONTROL bits
#define RW                    (1 << 0)
#define BYTE_COUNT            (0xF << 1)
#define USE_REG               (1 << 5)
#define USE_REPEATED_START    (1 << 6)
#define START_BIT             (1 << 7)

// BUSY bit in STATUS
#define BUSY                  (1 << 7)
#define RXFO      (1u << 0)
#define TXFO      (1u << 3)
#define ACK_ERR   (1u << 6)

// --------------------------------------------------------
// Function prototypes from I2C driver
// --------------------------------------------------------

void writeReg(unsigned int offset, unsigned int value)
{
    iowrite32(value, base + offset);
}

unsigned int readReg(unsigned int offset)
{
    return ioread32(base + offset);
}

//---------------------------------------------------------
static void mcp_write_reg(uint8_t reg, uint8_t value)
{
    unsigned int ctrl;
    unsigned int status;
    writeReg(STATUS_OFFSET,RXFO | TXFO | ACK_ERR);
    
    writeReg(ADDRESS_OFFSET, MCP_ADDR);
    writeReg(REGISTER_OFFSET, reg);

    ctrl = 0;
    //ctrl = readReg(CONTROL_OFFSET);
    ctrl &= ~RW;
    ctrl |= USE_REG;
    ctrl &= ~USE_REPEATED_START;
    ctrl &= ~BYTE_COUNT;
    ctrl |= (1 << 1);       //byte_count = 1

    writeReg(DATA_OFFSET, value);

    ctrl |= START_BIT;
    writeReg(CONTROL_OFFSET, ctrl);

    while (readReg(STATUS_OFFSET) & BUSY);
    status = readReg(STATUS_OFFSET);
    if (status & ACK_ERR)
        printk(KERN_ERR "i2c_expander: ACK_ERR on write reg 0x%02X, value 0x%02X, STATUS=0x%08X\n",
               reg, value, status);
}
static uint8_t mcp_read_reg(uint8_t reg)
{
    unsigned int ctrl;
    
    writeReg(ADDRESS_OFFSET, MCP_ADDR);
    writeReg(REGISTER_OFFSET, reg);

    writeReg(STATUS_OFFSET, RXFO | TXFO | ACK_ERR);
    //readReg(DATA_OFFSET);

    ctrl = 0;
    //ctrl = readReg(CONTROL_OFFSET);
    ctrl |= RW;                 // read
    ctrl |= USE_REG;
    ctrl |= USE_REPEATED_START;
    ctrl &= ~BYTE_COUNT;
    ctrl |= (1 << 1);

    ctrl |= START_BIT;
    writeReg(CONTROL_OFFSET, ctrl);

    while (readReg(STATUS_OFFSET) & BUSY);

    msleep(1);
    //return readReg(DATA_OFFSET) & 0xFF;
    uint8_t data = readReg(DATA_OFFSET);
    printk(KERN_INFO "return Data at mcp_read: DATA=0x%02X\n",data);
    return data;
}

static struct kobject *expander_kobj;
static struct kobject *pin_kobj[8];

static inline int get_pin(struct kobject *kobj)
{
    return kobj->name[3] - '0';
}

//-----------------------------------------------------------
// DIR
//-----------------------------------------------------------
static uint8_t iodir = 0xFF;
static ssize_t dirStore(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    int pin;
    pin = get_pin(kobj);
    char mode[10];
    //sscanf(buffer, "%s", mode);
    //iodir = mcp_read_reg(IODIR);
    printk(KERN_INFO "dataStore: BEFORE pin=%d IODIR=0x%02X\n", pin, iodir);

    if (strncmp(buffer, "in", 2) == 0)
        iodir |= (1<< pin);
    else if (strncmp(buffer, "out", 3) == 0)
        iodir &= ~(1 << pin);

    printk(KERN_INFO "dataStore: AFTER pin=%d IODIR=0x%02X\n", pin, iodir);
    printk(KERN_INFO "dirShow: pin=%d IODIR=0x%02X bit=%d\n",pin, iodir, ((iodir>> pin) & 0x1));
    mcp_write_reg(IODIR, iodir);

    uint8_t verify = iodir;
    printk(KERN_INFO "dirStore: VERIFY pin=%d IODIR(read)=0x%02X\n", pin, verify);
    
    return count;
}

static ssize_t dirShow(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    int pin;
    pin = get_pin(kobj);
    //uint8_t dir_data = mcp_read_reg(IODIR);
    //iodir = dir_data;
    iodir = mcp_read_reg(IODIR);
    int bit = (iodir>> pin) & 0x1;
    if(bit) return sprintf(buffer, "%s\n","in");
    else return sprintf(buffer, "%s\n","out");
    //return sprintf(buffer, "%s\n", ((iodir>> pin) & 0x1) ? "in" : "out");
    
}
static struct kobj_attribute dir_attr = __ATTR(dir, 0664, dirShow, dirStore);

//--------------------------------------------------------
// PULL-UP
//--------------------------------------------------------
//static char val[10] = "off";
static uint8_t gppu = 0x00;
static ssize_t pullupStore(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    int pin;
    pin = get_pin(kobj);

    //gppu = mcp_read_reg(GPPU);

    if (strncmp(buffer, "on", 2) == 0)
        gppu |= (1<< pin);
    else if (strncmp(buffer, "off", 3) == 0)
        gppu &= ~(1<<pin);

    mcp_write_reg(GPPU, gppu);
    
    return count;
}
static ssize_t pullupShow(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    int pin;
    pin = get_pin(kobj);
    uint8_t pullup_data = mcp_read_reg(GPPU);
    gppu = pullup_data;
    int bit = (gppu>> pin) & 0x1;
    printk(KERN_INFO "dataShow: pin=%d GPPU=0x%02X bit=%d\n",pin, gppu, bit);
    if(bit) return sprintf(buffer, "%s\n","on");
    else return sprintf(buffer, "%s\n","off");
    //return sprintf(buffer, "%s\n", ((gppu >> pin) & 0x1 )? "on" : "off");
  
}
static struct kobj_attribute pull_attr = __ATTR(pullup, 0664, pullupShow, pullupStore);

//--------------------------------------------------------
// DATA
//--------------------------------------------------------
//static char val[10] = "low";
static uint8_t olat = 0x00;
static uint8_t gpio;
static ssize_t dataStore(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    int pin;
    pin = get_pin(kobj);
    //olat = mcp_read_reg(OLAT);
    //sscanf(buffer, "%s", val);

    /*if (pin_dir[pin] == 1)
        return count;  // no write to input*/
    //olat = mcp_read_reg(OLAT);
    printk(KERN_INFO "dataStore: BEFORE pin=%d OLAT=0x%02X\n", pin, olat);


    if (strncmp(buffer, "high", 4) == 0)
        olat |= (1<< pin);
    else if (strncmp(buffer, "low", 3) == 0)
        olat &= ~(1<<pin);
    
    printk(KERN_INFO "dataStore: AFTER  pin=%d OLAT=0x%02X\n", pin, olat);
    mcp_write_reg(OLAT, olat);
        
    //u8 verify = mcp_read_reg(OLAT);
    //printk(KERN_INFO "dataStore: VERIFY pin=%d OLAT(read)=0x%02X\n", pin, verify);
    return count;
}
static ssize_t dataShow(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    int pin;
    pin = get_pin(kobj);
    uint8_t gpio_data = mcp_read_reg(GPIO);
    gpio = gpio_data;
    int bit = (gpio>> pin) & 0x1;
    printk(KERN_INFO "dataShow: pin=%d GPIO=0x%02X bit=%d\n",pin, gpio, bit);
    if(bit) return sprintf(buffer, "%s\n","high");
    else return sprintf(buffer, "%s\n","low");
    //return sprintf(buffer, "%s\n", ((gpio >> pin) & 0x1 )? "high" : "low");

}
static struct kobj_attribute data_attr = __ATTR(data, 0664, dataShow, dataStore);

//---------------------------------------------------------
static int __init expander_init(void)
{
    expander_kobj = kobject_create_and_add("i2c_expander", kernel_kobj);
    if (!expander_kobj)
    {
        printk(KERN_ALERT "I2C expander: failed to create and add kobj\n");
        return -ENOENT;
    }

    //pin_kobj = kobject_create_and_add("pin", expander_kobj);
    
    for (int i = 0; i < 8; i++) {
        char name[8] = "pin0";
        name[3] = '0' + i;  //change last bit

        pin_kobj[i] = kobject_create_and_add(name, expander_kobj);
        
        if (!pin_kobj[i])
        {
            printk(KERN_ALERT "I2C expander_pin: failed to create and add kobj\n");
            return -ENOENT;
        }

        sysfs_create_file(pin_kobj[i], &dir_attr.attr);
        sysfs_create_file(pin_kobj[i], &pull_attr.attr);
        sysfs_create_file(pin_kobj[i], &data_attr.attr);

    }

    /*sysfs_create_file(pin_kobj, &dir_attr.attr);
    sysfs_create_file(pin_kobj, &pull_attr.attr);
    sysfs_create_file(pin_kobj, &data_attr.attr);*/

     // Physical to virtual memory map to access gpio registers
     base = (unsigned int*)ioremap(AXI4_LITE_BASE + I2C_BASE_OFFSET, I2C_SPAN_IN_BYTES);
    
     if (base == NULL)
         return -ENODEV;

    printk("i2c_expander: initialized\n");
    return 0;
}

static void __exit expander_exit(void)
{
    for (int i = 0; i < 8; i++)
        kobject_put(pin_kobj[i]);
    kobject_put(expander_kobj);
    printk(KERN_INFO "I2C expander: exit\n");
}
module_init(expander_init);
module_exit(expander_exit);

