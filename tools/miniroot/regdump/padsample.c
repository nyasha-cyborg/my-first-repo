// SPDX-License-Identifier: GPL-2.0
/* Poor man's logic analyser for bring-up: spin-read the Tegra GPIO_IN
 * register of one port (the pad level is visible there when the pad's
 * input buffer is enabled, even while the pad is muxed to a peripheral)
 * and report, per bit, high-count and edge-count over a fixed window.
 * insmod padsample.ko addr=0x6000d33c      (PP0-PP7)
 */
#include <linux/module.h>
#include <linux/io.h>
#include <linux/ktime.h>

static unsigned long addr;
module_param(addr, ulong, 0);
static int reads = 400000;
module_param(reads, int, 0);

static int __init padsample_init(void)
{
	void __iomem *p = ioremap(addr, 4);
	unsigned int hi[8] = {}, edges[8] = {}, prev, v;
	u64 t0, t1;
	int i, b;

	if (!p)
		return -ENOMEM;
	local_irq_disable();
	prev = readl(p);
	t0 = ktime_get_ns();
	for (i = 0; i < reads; i++) {
		v = readl(p);
		for (b = 0; b < 8; b++) {
			hi[b] += (v >> b) & 1;
			edges[b] += ((v ^ prev) >> b) & 1;
		}
		prev = v;
	}
	t1 = ktime_get_ns();
	local_irq_enable();
	iounmap(p);
	pr_info("n9pad window %llu us, %d reads\n", (t1 - t0) / 1000, reads);
	for (b = 0; b < 8; b++)
		pr_info("n9pad bit%d hi=%u edges=%u\n", b, hi[b], edges[b]);
	return -EAGAIN;
}
module_init(padsample_init);
MODULE_LICENSE("GPL");
