// SPDX-License-Identifier: GPL-2.0
/* Bring-up experiment: drive the DAP3 pads (PP0 = FS, PP3 = SCLK) as plain
 * GPIOs and bit-bang a continuous 32 * fs I2S clock for `ms` milliseconds,
 * so the speaker amps' PLL status (R0) can be read from userspace meanwhile.
 * Proves whether the amps listen to these pads, independent of the Tegra I2S
 * block.  Port P is bank 3 / port 3 of the Tegra GPIO controller.
 * insmod bitbang.ko ms=4000 pad=120
 */
#include <linux/module.h>
#include <linux/io.h>
#include <linux/ktime.h>
#include <linux/kthread.h>
#include <linux/delay.h>
#include <linux/completion.h>

static int ms = 4000;
module_param(ms, int, 0);
static int cpu = 1;
static u64 nframes = 40000;
module_param(nframes, ullong, 0);
module_param(cpu, int, 0);
static int extra_ns;	/* per-BCLK-cycle padding */
module_param(extra_ns, int, 0);

#define FS	BIT(0)
#define SCLK	BIT(3)
#define PORT	0x6000d300UL
#define CNF	0x0c
#define OE	0x1c
#define OUT	0x2c

static int bb(void *unused)
{
	void __iomem *g = ioremap(PORT, 0x40);
	u32 cnf, oe, out, o;
	unsigned long flags;
	u64 t0, t1, cycles = 0, frames = 0;
	int i;

	if (!g)
		return -ENOMEM;
	cnf = readl(g + CNF);
	oe = readl(g + OE);
	out = readl(g + OUT);
	local_irq_save(flags);
	writel(out & ~(FS | SCLK), g + OUT);
	writel(oe | FS | SCLK, g + OE);
	writel(cnf | FS | SCLK, g + CNF);
	t0 = ktime_get_ns();
	o = out & ~(FS | SCLK);
	while (frames < nframes) {
		for (i = 0; i < 32; i++) {
			u32 fs = i < 16 ? 0 : FS;

			writel((o & ~FS) | fs | SCLK, g + OUT);
			writel((o & ~FS) | fs, g + OUT);
			if (extra_ns)
				ndelay(extra_ns);
			cycles++;
		}
		frames++;
	}
	t1 = ktime_get_ns();
	writel(cnf, g + CNF);
	writel(oe, g + OE);
	writel(out, g + OUT);
	local_irq_restore(flags);
	iounmap(g);
	pr_info("n9bb %llu bclk cycles, %llu frames in %llu us -> fs %llu Hz, bclk %llu Hz\n",
		cycles, frames, (t1 - t0) / 1000,
		frames * 1000000000ULL / (t1 - t0),
		cycles * 1000000000ULL / (t1 - t0));
	return 0;
}

static int __init bb_init(void)
{
	struct task_struct *t = kthread_create(bb, NULL, "n9bb");

	if (IS_ERR(t))
		return PTR_ERR(t);
	kthread_bind(t, cpu);
	wake_up_process(t);
	return -EAGAIN;
}
module_init(bb_init);
MODULE_LICENSE("GPL");
