// SPDX-License-Identifier: GPL-2.0
/* Read-only physical register dump for bring-up (STRICT_DEVMEM blocks
 * /dev/mem on driver-claimed ranges).  insmod regdump.ko addrs=0x70003030,...
 * Prints "n9reg <addr>=<value>" to the kernel log and refuses to stay loaded.
 */
#include <linux/module.h>
#include <linux/io.h>

static unsigned long addrs[64];
static int naddrs;
module_param_array(addrs, ulong, &naddrs, 0);

static int __init regdump_init(void)
{
	int i;

	for (i = 0; i < naddrs; i++) {
		void __iomem *p = ioremap(addrs[i], 4);

		if (!p)
			continue;
		pr_info("n9reg %08lx=%08x\n", addrs[i], readl(p));
		iounmap(p);
	}
	return -EAGAIN;
}
module_init(regdump_init);
MODULE_LICENSE("GPL");
