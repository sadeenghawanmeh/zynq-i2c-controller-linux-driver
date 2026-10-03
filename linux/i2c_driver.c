#include <linux/kernel.h>     // kstrtouint
#include <linux/module.h>     // MODULE_ macros
#include <linux/init.h>       // __init
#include <linux/kobject.h>    // kobject, kobject_atribute,
                              // kobject_create_and_add, kobject_put
#include <asm/io.h>           // iowrite, ioread, ioremap_nocache (platform specific)
#include "../address_map.h"   // overall memory map
//#include "qe_regs.h"          // register offsets in QE IP

//-----------------------------------------------------------------------------
// Kernel module information
//-----------------------------------------------------------------------------

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Sadeen");
MODULE_DESCRIPTION("I2C IP Driver");

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

// Control register bit
#define RW                    (1 << 0)
#define BYTE_COUNT            (0xF << 1)
#define USE_REG               (1 << 5)
#define USE_REPEATED_START    (1 << 6)
#define START_BIT             (1 << 7)

// Status register bit
#define RXFO      (1u << 0)
#define RXFF      (1u << 1)
#define RXFE      (1u << 2)
#define TXFO      (1u << 3)
#define TXFF      (1u << 4)
#define TXFE      (1u << 5)
#define ACK_ERR   (1u << 6)
#define BUSY      (1u << 7)

//-----------------------------------------------------------------------------
// Subroutines
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
//
//-----------------------------------------------------------------------------

void writeReg(unsigned int offset, unsigned int value)
{
    iowrite32(value, base + offset);
}

unsigned int readReg(unsigned int offset)
{
    return ioread32(base + offset);
}

//-----------------------------------------------------------------------------
// Kernel Objects
//-----------------------------------------------------------------------------

// Address
static unsigned int address = 0; 
/*module_param(address, unsigned int, S_IRUGO);
MODULE_PARM_DESC(address, "Address of MCP");*/
static ssize_t addressStore(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    int result = kstrtouint(buffer, 0, &address);
    /*if(result == !0)
        return result;*/
    writeReg(ADDRESS_OFFSET, address);
    return count;
}

static ssize_t addressShow(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    address = readReg(ADDRESS_OFFSET);
    return sprintf(buffer, "%u\n", address);
}

static struct kobj_attribute addressAttr = __ATTR(address, 0664, addressShow, addressStore);

// Register -----------------------------------------------------------------------------
static int regIndex = -1;
/*module_param(regIndex, int, S_IRUGO);
MODULE_PARM_DESC(regIndex, "Register Index");*/
static ssize_t registerStore(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    unsigned int ctrl;
    if(strncmp(buffer, "none", 4) == 0)
    {
        regIndex = -1;
        ctrl = readReg(CONTROL_OFFSET);
        ctrl &= ~USE_REG;
        writeReg(CONTROL_OFFSET, ctrl);
    }
    else
    {
        //unsigned int ctrl;
        ctrl = readReg(CONTROL_OFFSET);
        ctrl |= USE_REG;
        writeReg(CONTROL_OFFSET, ctrl);

        kstrtouint(buffer, 0, &regIndex);
        writeReg(REGISTER_OFFSET, regIndex);
    }
    return count;
}

static ssize_t registerShow(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    if (regIndex == -1)return sprintf(buffer, "none\n");
    return sprintf(buffer, "%u\n", regIndex);
}

static struct kobj_attribute registerAttr = __ATTR(register, 0664, registerShow, registerStore);

// Mode -----------------------------------------------------------------------------
static char mode[10] = "write";
/*module_param(mode, char, S_IRUGO);
MODULE_PARM_DESC(mode, "Read or Write mode");*/
static ssize_t modeStore(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    unsigned int ctrl;
    ctrl = readReg(CONTROL_OFFSET);
    if (strncmp(buffer, "read", 4) == 0)
    {
        strcpy(mode, "read");
        ctrl |= RW;         // read = 1
    }
    else if (strncmp(buffer, "write", 5) == 0)
    {
        strcpy(mode, "write");
        ctrl &= ~RW;        // write = 0
    }
    writeReg(CONTROL_OFFSET, ctrl);
    return count;
}
static ssize_t modeShow(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    unsigned int ctrl;
    ctrl = readReg(CONTROL_OFFSET);
    return sprintf(buffer, "%s\n", (ctrl & RW) ? "read" : "write");
}

static struct kobj_attribute modeAttr = __ATTR(mode, 0664, modeShow, modeStore);

// Byte_Count -----------------------------------------------------------------------------
static unsigned int byte_count = 0;
/*module_param(byte_count, unsigned int, S_IRUGO);
MODULE_PARM_DESC(byte_count, "BYTE_COUNT");*/
static ssize_t bytecount_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    unsigned int ctrl;
    kstrtouint(buffer, 0, &byte_count);
    ctrl = readReg(CONTROL_OFFSET);
    ctrl &= ~BYTE_COUNT;
    ctrl |= (byte_count & 0xF) << 1;
    writeReg(CONTROL_OFFSET, ctrl);
    return count;
}

static ssize_t bytecount_show(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    unsigned int ctrl;
    unsigned int bc;
    ctrl = readReg(CONTROL_OFFSET);
    bc = (ctrl >> 1) & 0xF;
    return sprintf(buffer, "%u\n", bc);
}

static struct kobj_attribute bytecountAttr = __ATTR(byte_count, 0664, bytecount_show, bytecount_store);

// Use_Repeated_Start -------------------------------------------------------------------------------
static ssize_t repeatedStore(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    unsigned int ctrl;
    ctrl = readReg(CONTROL_OFFSET);
    if (strncmp(buffer, "true", 4) == 0)
        ctrl |= USE_REPEATED_START;
    else if (strncmp(buffer, "false", 5) == 0)
        ctrl &= ~USE_REPEATED_START;
    
    writeReg(CONTROL_OFFSET, ctrl);
    return count;
}
static ssize_t repeatedShow(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    unsigned int ctrl;
    ctrl = readReg(CONTROL_OFFSET);
    return sprintf(buffer, "%s\n", (ctrl & USE_REPEATED_START) ? "true" : "false");
}
static struct kobj_attribute repeatedAttr = __ATTR(use_repeated_start, 0664, repeatedShow, repeatedStore);

//Start ---------------------------------------------------------------------------------------------
static ssize_t startStore(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    unsigned int ctrl;
    writeReg(STATUS_OFFSET, RXFO | TXFO | ACK_ERR);
    ctrl = readReg(CONTROL_OFFSET);
    ctrl |= START_BIT;
    writeReg(CONTROL_OFFSET, ctrl);
    return count;
}
static ssize_t startShow(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    unsigned int status;
    status = readReg(STATUS_OFFSET);
    return sprintf(buffer, "%u\n", status);
}
static struct kobj_attribute startAttr = __ATTR(start, 0664, startShow, startStore);

//RX_DATA -------------------------------------------------------------------------------------------
static unsigned int rxdata = 0;
/*module_param(rxdata, unsigned int, S_IRUGO);
MODULE_PARM_DESC(rxdata, "Value of FIFPO");*/
static ssize_t rxShow(struct kobject *kobj, struct kobj_attribute *attr, char *buffer)
{
    /*unsigned int status = readReg(STATUS_OFFSET);

    // If RXFE --> FIFO empty → return -1
    if (status & RXFE)
    return sprintf(buffer, "-1\n");

    // Otherwise read byte from FIFO
    unsigned int value = readReg(DATA_OFFSET);
    return sprintf(buffer, "0x%02X\n", value);*/

    unsigned int status;
    status = readReg(STATUS_OFFSET);
    printk(KERN_INFO "rxShow: STATUS=0x%08X\n", status);

    if (status & RXFE)
        return sprintf(buffer, "-1\n");

    rxdata = readReg(DATA_OFFSET);
    printk(KERN_INFO "rxShow: =0x%02X\n", rxdata);

    return sprintf(buffer, "0x%02X\n", rxdata);
}
static struct kobj_attribute rxAttr = __ATTR(rx_data, 0444, rxShow, NULL);

//TX_DATA -------------------------------------------------------------------------------------------
unsigned int value;
static ssize_t txStore(struct kobject *kobj, struct kobj_attribute *attr, const char *buffer, size_t count)
{
    unsigned int status;
    status = readReg(STATUS_OFFSET);
    if (status & TXFF)
        return count;   

    kstrtouint(buffer, 0, &value);
    writeReg(DATA_OFFSET, value & 0xFF);
    return count;
}
static struct kobj_attribute txAttr = __ATTR(tx_data, 0220, NULL, txStore);

//Attributes ------------------------------------------------------------
static struct attribute *i2c_attrs[] = {
    &modeAttr.attr,
    &bytecountAttr.attr,
    &registerAttr.attr,
    &addressAttr.attr,
    &repeatedAttr.attr,
    &startAttr.attr,
    &txAttr.attr,
    &rxAttr.attr,
    NULL
};

static const struct attribute_group i2c_group = {
    .name = NULL,
    .attrs = i2c_attrs,
};

//-----------------------------------------------------------------------------
// Initialization and Exit
//-----------------------------------------------------------------------------

static struct kobject *kobj;

static int __init i2c_init(void)
{
    int result;

    printk(KERN_INFO "I2C driver: starting\n");

    // Create i2c directory under /sys/kernel
    kobj = kobject_create_and_add("i2c", kernel_kobj); //kernel_kobj);  //kobj = kobject_create_and_add("i2c", NULL); for /sys/kernel/i2c/

    if (!kobj)
    {
        printk(KERN_ALERT "I2C driver: failed to create and add kobj\n");
        return -ENOENT;
    }

    result = sysfs_create_group(kobj, &i2c_group);
    if (result !=0)
        return result;

    // Physical to virtual memory map to access gpio registers
    base = (unsigned int*)ioremap(AXI4_LITE_BASE + I2C_BASE_OFFSET, I2C_SPAN_IN_BYTES);
    
    if (base == NULL)
        return -ENODEV;

    printk(KERN_INFO "I2C driver: initialized\n");
    return 0;
}
static void __exit i2c_exit(void)
{
    kobject_put(kobj);
    printk(KERN_INFO "I2C driver: exit\n");
}

module_init(i2c_init);
module_exit(i2c_exit);