// SPDX-License-Identifier: GPL-2.0
/* Bring-up experiment: give the DAP3 pads (PP0-PP3) back to the pinmux
 * function by clearing their GPIO_CNF bits (the bootloader leaves them as
 * GPIO outputs driving low, which overrides the I2S2 signals).
 * insmod sfio.ko [mask=0xf]
 */
#include <linux/module.h>
#include <linux/io.h>

static unsigned int mask = 0xf;
module_param(mask, uint, 0);

static int __init sfio_init(void)
{
	void __iomem *g = ioremap(0x6000d300, 0x40);
	u32 v;

	if (!g)
		return -ENOMEM;
	v = readl(g + 0x0c);
	writel(v & ~mask, g + 0x0c);
	pr_info("n9sfio CNF %08x -> %08x\n", v, readl(g + 0x0c));
	iounmap(g);
	return -EAGAIN;
}
module_init(sfio_init);
MODULE_LICENSE("GPL");
