/* btwake: reproduce Android bluedroid_pm's BT_WAKE behaviour on the flounder
 * BCM4350C0, then probe HCI on the BT UART.
 *
 * Android raises BT_WAKE (PEE1) only when the stack wants to transmit and
 * drops it when the chip reports idle.  Holding the line statically high from
 * boot (as a fixed regulator does) is not the same signal: the chip comes up
 * with the line already asserted and never sees the idle->wake transition.
 *
 * This tool power-cycles REG_ON (PR1), asserts BT_WAKE (PEE1, active low),
 * then replays libbt-vendor's opening: HCI Reset at 115200/crtscts, VSC
 * 0xfc18 to 3 Mbaud, switch the host, Read Local Name.  If 115200 is silent
 * it falls back to a 3M Reset for comparison.
 *
 * usage: btwake [power_line] [wake_line]
 */
#define SYS_openat    56
#define SYS_close     57
#define SYS_ioctl     29
#define SYS_write     64
#define SYS_read      63
#define SYS_nanosleep 101
#define SYS_exit      93

#define AT_FDCWD (-100)
#define O_RDWR 2
#define O_NOCTTY 0400
#define O_NONBLOCK 04000

/* GPIO chardev ioctls.  The request struct gained consumer_label[32], so
 * sizeof == 364 and the encoded ioctl number is 0xC16CB403 (0xC14CB403 is
 * the pre-label layout and the kernel rejects it as a different size). */
#define GPIOHANDLE_GET_LINE_IOCTL 0xC16CB403
/* _IOWR(0xB4, 0x09, struct gpiohandle_data); 0x05 is a different command */
#define GPIOHANDLE_SET_LINE_VALUES_IOCTL 0xC040B409
#define GPIOHANDLE_REQUEST_OUTPUT 2	/* bit 1; 1 is INPUT */

/* Android's live termios on /dev/ttyTHS2: legacy TCSETS, speed 3000000
 * (B3000000 == 0x100d), cs8|cread|clocal|crtscts. */
#define TCSETS 0x5402
#define TIOCSETD 0x5423
#define TIOCOUTQ 0x5411
#define TIOCMGET 0x5415
#define TIOCM_RTS 0x004
#define TIOCM_CTS 0x020
#define B3000000 0x100d
#define B115200 0x1002
#define CS8 0x30
#define CREAD 0x80
#define CLOCAL 0x800
#define CRTSCTS 0x80000000u

struct gpiohandle_request {
	unsigned int lineoffsets[64];
	unsigned int flags;
	unsigned char default_values[64];
	char consumer_label[32];
	unsigned int lines;
	int fd;
};

struct gpiohandle_data {
	unsigned char values[64];
};

struct termios_k {
	unsigned int c_iflag, c_oflag, c_cflag, c_lflag;
	unsigned char c_line;
	unsigned char c_cc[19];
	unsigned int c_ispeed, c_ospeed;
};

static long sc(long n, long a, long b, long c, long d, long e)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b, x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d, x4 __asm__("x4") = e;

	__asm__ volatile("svc 0" : "+r"(x0)
			 : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4)
			 : "memory");
	return x0;
}

static void put(const char *s)
{
	/* One write per line: every /dev/kmsg write becomes its own
	 * record, so prefix and text must travel together. */
	static char line[192];
	static const char pre[] = "<6>n9bt: ";
	int i = 0, j;

	for (j = 0; pre[j] && i < 180; j++)
		line[i++] = pre[j];
	for (j = 0; s[j] && s[j] != '\n' && i < 190; j++)
		line[i++] = s[j];
	line[i++] = '\n';
	{
		long fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/kmsg", 1 /*O_WRONLY*/, 0, 0);

		if (fd >= 0) {
			sc(SYS_write, fd, (long)line, i, 0, 0);
			sc(SYS_close, fd, 0, 0, 0, 0);
		}
	}
}

/* Line builder: numbers and hex must land in the same kmsg record as their
 * label, so accumulate here and emit once with lb_end(). */
static char lb[180];
static int lbn;

static void lb_str(const char *s)
{
	while (*s && *s != '\n' && lbn < (int)sizeof(lb) - 1)
		lb[lbn++] = *s++;
}

static void lb_hex(unsigned char v)
{
	static const char hx[] = "0123456789abcdef";

	if (lbn < (int)sizeof(lb) - 4) {
		lb[lbn++] = hx[v >> 4];
		lb[lbn++] = hx[v & 0xf];
		lb[lbn++] = ' ';
	}
}

static void lb_dec(long v)
{
	char b[20];
	int i = 0;

	if (v < 0) { lb_str("-"); v = -v; }
	if (!v) b[i++] = '0';
	while (v) { b[i++] = '0' + (v % 10); v /= 10; }
	while (i && lbn < (int)sizeof(lb) - 1)
		lb[lbn++] = b[--i];
}

static void lb_end(void)
{
	lb[lbn] = 0;
	put(lb);
	lbn = 0;
}

static int num(const char *s)
{
	int v = 0;

	while (*s >= '0' && *s <= '9')
		v = v * 10 + (*s++ - '0');
	return v;
}

static void ms(int m)
{
	struct { long s, ns; } ts = { m / 1000, (m % 1000) * 1000000L };

	sc(SYS_nanosleep, (long)&ts, 0, 0, 0, 0);
}

/* Read a decimal sysfs attribute ("/sys/class/gpio/gpiochipN/base"). */
static long readnum(const char *path)
{
	long fd, n;
	char b[32];
	long v = 0;
	int i;

	fd = sc(SYS_openat, AT_FDCWD, (long)path, 0 /* O_RDONLY */, 0, 0);
	if (fd < 0)
		return -1;
	n = sc(SYS_read, fd, (long)b, sizeof(b) - 1, 0, 0);
	sc(SYS_close, fd, 0, 0, 0, 0);
	if (n <= 0)
		return -1;
	for (i = 0; i < n && b[i] >= '0' && b[i] <= '9'; i++)
		v = v * 10 + (b[i] - '0');
	return v;
}

/* The requested line number is the global gpiolib number that debugfs and
 * the DT gpios property use.  /dev/gpiochipN offsets are local to that
 * chip, and the numbering order is probe order (the PMIC GPIO controller
 * usually comes first), so resolve chip and offset from sysfs. */
/*
 * /sys/kernel/debug/gpio lists controllers in probe order with their line
 * counts, and gpiolib numbers them from 0 in that same order:
 *   gpiochip0: 256 GPIOs, parent: platform/6000d000.gpio, tegra-gpio:
 *   gpiochip1: 8 GPIOs, parent: ...:tps65913@58:gpio, ...
 * CONFIG_GPIO_SYSFS is off, so this is the only mapping available.
 */
static int find_chip_debugfs(unsigned int line, unsigned int *offset, char *path)
{
	static const char f[] = "/sys/kernel/debug/gpio";
	char buf[4096];
	long fd, n;
	int i;
	unsigned int base = 0;

	fd = sc(SYS_openat, AT_FDCWD, (long)f, 0, 0, 0);
	if (fd < 0)
		return -1;
	n = sc(SYS_read, fd, (long)buf, sizeof(buf) - 1, 0, 0);
	sc(SYS_close, fd, 0, 0, 0, 0);
	if (n <= 0)
		return -1;
	buf[n] = 0;

	for (i = 0; i + 8 < n; i++) {
		int c = 0, k;
		unsigned int count = 0;

		if (buf[i] != 'g' || buf[i + 1] != 'p' || buf[i + 2] != 'i' ||
		    buf[i + 3] != 'o' || buf[i + 4] != 'c' || buf[i + 5] != 'h' ||
		    buf[i + 6] != 'i' || buf[i + 7] != 'p')
			continue;
		/* only at start of a line */
		if (i > 0 && buf[i - 1] != '\n')
			continue;
		k = i + 8;
		while (k < n && buf[k] >= '0' && buf[k] <= '9')
			c = c * 10 + (buf[k++] - '0');
		while (k < n && buf[k] != '\n' && (buf[k] < '0' || buf[k] > '9'))
			k++;
		while (k < n && buf[k] >= '0' && buf[k] <= '9')
			count = count * 10 + (buf[k++] - '0');
		if ((unsigned long)line >= base && (unsigned long)line < base + count) {
			static const char dev[] = "/dev/gpiochip";
			int k2 = 0;

			for (k2 = 0; dev[k2]; k2++)
				path[k2] = dev[k2];
			if (c >= 10)
				path[k2++] = '0' + c / 10;
			path[k2++] = '0' + c % 10;
			path[k2] = 0;
			*offset = line - base;
			return 0;
		}
		base += count;
		while (i < n && buf[i] != '\n')
			i++;
	}
	return -1;
}

static int find_chip(unsigned int line, unsigned int *offset, char *path)
{
	int c;

	for (c = 0; c < 8; c++) {
		char p[64];
		static const char pre[] = "/sys/class/gpio/gpiochip";
		int k = 0;
		long base, ngpio;

		for (k = 0; pre[k]; k++)
			p[k] = pre[k];
		if (c >= 10)
			p[k++] = '0' + c / 10;
		p[k++] = '0' + c % 10;
		p[k] = 0;
		{
			/* append "/base" and "/ngpio" */
			static const char sb[] = "/base";
			static const char sn[] = "/ngpio";
			int j;

			for (j = 0; sb[j]; j++) p[k + j] = sb[j];
			p[k + j] = 0;
			base = readnum(p);
			for (j = 0; sn[j]; j++) p[k + j] = sn[j];
			p[k + j] = 0;
			ngpio = readnum(p);
		}
		if (base < 0 || ngpio <= 0)
			continue;
		if ((long)line >= base && (long)line < base + ngpio) {
			static const char dev[] = "/dev/gpiochip";
			int k2 = 0;

			for (k2 = 0; dev[k2]; k2++)
				path[k2] = dev[k2];
			if (c >= 10)
				path[k2++] = '0' + c / 10;
			path[k2++] = '0' + c % 10;
			path[k2] = 0;
			*offset = line - (unsigned int)base;
			return 0;
		}
	}
	/* sysfs absent (CONFIG_GPIO_SYSFS off): parse the debugfs map. */
	return find_chip_debugfs(line, offset, path);
}

static int out_line(const char *chip, unsigned int line, unsigned int init)
{
	struct gpiohandle_request req;
	long fd, rc;

	fd = sc(SYS_openat, AT_FDCWD, (long)chip, O_RDWR, 0, 0);
	if (fd < 0) {
		lb_str("btwake: chip open errno "); lb_dec(-fd); lb_end();
		return -1;
	}
	for (unsigned int i = 0; i < sizeof(req); i++)
		((char *)&req)[i] = 0;
	req.lineoffsets[0] = line;
	req.flags = GPIOHANDLE_REQUEST_OUTPUT;
	req.default_values[0] = (unsigned char)init;
	req.consumer_label[0] = 'b';
	req.consumer_label[1] = 't';
	req.consumer_label[2] = 'w';
	req.consumer_label[3] = 'a';
	req.consumer_label[4] = 'k';
	req.consumer_label[5] = 'e';
	req.lines = 1;
	rc = sc(SYS_ioctl, fd, GPIOHANDLE_GET_LINE_IOCTL, (long)&req, 0, 0);
	sc(SYS_close, fd, 0, 0, 0, 0);
	if (rc < 0) {
		lb_str("btwake: line request errno "); lb_dec(-rc); lb_end();
		return -2;
	}
	return req.fd;
}

static int set_line(int hfd, unsigned int v)
{
	struct gpiohandle_data d;

	for (unsigned int i = 0; i < sizeof(d); i++)
		((char *)&d)[i] = 0;
	d.values[0] = (unsigned char)v;
	return (int)sc(SYS_ioctl, hfd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, (long)&d, 0, 0);
}

/* Android's userial_vendor_open: cfmakeraw, then c_cflag |= CRTSCTS, speed
 * from the open config.  Raw termios is all-zero flags apart from cflag. */
static int set_speed_fc(long fd, unsigned int bconst, unsigned int fc)
{
	struct termios_k t;

	for (unsigned int i = 0; i < sizeof(t); i++)
		((char *)&t)[i] = 0;
	t.c_cflag = bconst | CS8 | CREAD | CLOCAL | fc;
	return (int)sc(SYS_ioctl, fd, TCSETS, (long)&t, 0, 0);
}

static int set_speed(long fd, unsigned int bconst)
{
	return set_speed_fc(fd, bconst, CRTSCTS);
}

/* With CRTSCTS the UART only shifts bytes out while CTS (the chip's RTS) is
 * asserted, so a chip that never raises RTS leaves the command queued and
 * looks exactly like a silent chip.  Log CTS/RTS and the unsent count. */
static long g_fd = -1;

static void line_state(const char *when)
{
	int m = 0, q = -1;
	long rc = sc(SYS_ioctl, g_fd, TIOCMGET, (long)&m, 0, 0);

	sc(SYS_ioctl, g_fd, TIOCOUTQ, (long)&q, 0, 0);
	lb_str("btwake: lines "); lb_str(when);
	if (rc < 0) {
		lb_str(" tiocmget errno "); lb_dec(-rc);
	} else {
		lb_str(" cts="); lb_dec(!!(m & TIOCM_CTS));
		lb_str(" rts="); lb_dec(!!(m & TIOCM_RTS));
	}
	lb_str(" outq="); lb_dec(q);
	lb_end();
}

/* Write one HCI command and collect whatever arrives for up to wait_ms.
 * Returns the number of bytes received; every chunk is logged as one line. */
static int hci_cmd(long fd, const char *what, const unsigned char *cmd, int len,
		   unsigned char *rx, int rxmax, int wait_ms)
{
	int total = 0, t;
	long w;

	lb_str("btwake: send "); lb_str(what); lb_end();
	w = sc(SYS_write, fd, (long)cmd, len, 0, 0);
	if (w != len) {
		lb_str("btwake: write returned "); lb_dec(w); lb_end();
	}
	for (t = 0; t < wait_ms; t += 50) {
		long r = sc(SYS_read, fd, (long)(rx + total), rxmax - total, 0, 0);

		if (r > 0) {
			lb_str("btwake: got ");
			for (long i = 0; i < r; i++)
				lb_hex(rx[total + i]);
			lb_end();
			total += r;
			if (total >= rxmax)
				break;
		}
		ms(50);
	}
	if (!total) {
		lb_str("btwake: no reply to "); lb_str(what); lb_end();
	}
	line_state("after");
	return total;
}

/* A Command Complete for `op` with status 0: 04 0e <len> <ncmd> <op lo> <op hi> 00 */
static int cc_ok(const unsigned char *rx, int n, unsigned int op)
{
	for (int i = 0; i + 6 < n; i++)
		if (rx[i] == 0x04 && rx[i + 1] == 0x0e &&
		    rx[i + 4] == (op & 0xff) && rx[i + 5] == (op >> 8))
			return rx[i + 6] == 0;
	return 0;
}

static void start_c(long *sp) __attribute__((noreturn, used));

void _start(void) __attribute__((naked));
void _start(void)
{
	__asm__ volatile("mov x0, sp\n\tb start_c");
}

void start_c(long *sp)
{
	int argc = (int)sp[0];
	char **argv = (char **)(sp + 1);
	char chipbuf[64];
	const char *chip;
	unsigned int offset;
	int power = (argc > 1) ? num(argv[1]) : 137;
	int wake = (argc > 2) ? num(argv[2]) : 241;
	int ldisc = 0;
	long fd;
	static const unsigned char reset[4] = { 0x01, 0x03, 0x0c, 0x00 };
	/* HCI_VSC_UPDATE_BAUDRATE, exactly as hw_config_cback builds it:
	 * opcode fc18, len 6, 00 00, then 3000000 little-endian. */
	static const unsigned char to3m[10] = {
		0x01, 0x18, 0xfc, 0x06, 0x00, 0x00, 0xc0, 0xc6, 0x2d, 0x00 };
	static const unsigned char rdname[4] = { 0x01, 0x14, 0x0c, 0x00 };
	static const unsigned char rdver[4] = { 0x01, 0x01, 0x10, 0x00 };
	unsigned char buf[300];
	int hwake, tries, n;

	if (find_chip((unsigned int)wake, &offset, chipbuf) < 0) {
		/* Fall back to the raw number on chip 0. */
		chip = "/dev/gpiochip0";
		offset = (unsigned int)wake;
		put("btwake: chip lookup failed, trying chip0\n");
	} else {
		chip = chipbuf;
		lb_str("btwake: user line "); lb_dec(wake);
		lb_str(" -> "); lb_str(chip);
		lb_str(" offset "); lb_dec(offset); lb_end();
	}

	/* Android's BT_VND_PWR_ON powers the section off first, then on.
	 * Our old DT held REG_ON from boot, so the chip never saw that
	 * edge; do it here now that userspace owns the line. */
	{
		char chip2[64];
		unsigned int off2;
		int hpwr;

		if (find_chip((unsigned int)power, &off2, chip2) < 0) {
			put("btwake: power chip lookup failed\n");
			sc(SYS_exit, 3, 0, 0, 0, 0);
		}
		hpwr = out_line(chip2, off2, 0);
		if (hpwr < 0) {
			/* rfkill-gpio owns PR1 now and has already done the
			 * power cycle; nothing more to do here. */
			put("btwake: power line owned (rfkill), skipping\n");
			goto power_done;
		}
		/* REG_ON is ACTIVE HIGH: live Android, 2026-10-20 21:10,
		 * gpio-137 shutdown_gpio reads "out hi" with BT on and
		 * "out lo" with BT off (repeated on/off/on/off). */
		put("btwake: power off (low)\n");
		if (set_line(hpwr, 0) < 0)
			put("btwake: power off set failed\n");
		ms(200);
		if (set_line(hpwr, 1) < 0)
			put("btwake: power on set failed\n");
		put("btwake: power on (high)\n");
		ms(500);
	}

power_done:
	/* BT_WAKE is ACTIVE LOW on this board: bluedroid_pm's
	 * TIO_ASSERT_BT_WAKE sets ext_wake = 0 and "BT sleeping" sets it
	 * to 1.  Hold it asserted (low) through the probe. */
	hwake = out_line(chip, offset, 1);	/* idle: sleep */
	if (hwake < 0) {
		put("btwake: wake line unavailable\n");
		sc(SYS_exit, 1, 0, 0, 0, 0);
	}
	put("btwake: wake idle (high)\n");
	ms(20);
	if (set_line(hwake, 0) < 0)
		put("btwake: wake assert set failed\n");
	put("btwake: wake asserted (low)\n");
	ms(30);

	/* "hold": power and wake only, leave the UART to N_HCI/hci_uart
	 * (the tty path has no device to drive these lines itself). */
	if (argc > 3 && argv[3][0] == 'h') {
		put("btwake: holding power and wake, no UART probe\n");
		for (;;)
			ms(1000);
	}

	fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/ttyTHS2",
		O_RDWR | O_NOCTTY | O_NONBLOCK, 0, 0);
	if (fd < 0) {
		put("btwake: tty open failed\n");
		sc(SYS_exit, 2, 0, 0, 0, 0);
	}
	sc(SYS_ioctl, fd, TIOCSETD, (long)&ldisc, 0, 0);	/* N_TTY */
	g_fd = fd;

	/* libbt-vendor (REA, 2026-10-20): op(USERIAL_OPEN) opens at config
	 * 09 02 07 00 = 8N1, baud index 7 = B115200, with CRTSCTS.
	 * hw_config_start then sends HCI Reset at that speed, and only
	 * after its Command Complete switches the chip to 3M with VSC
	 * 0xfc18.  The ROM therefore talks 115200 first. */
	if (set_speed(fd, B115200) < 0)
		put("btwake: TCSETS 115200 failed\n");
	ms(100);
	line_state("open");

	n = 0;
	for (tries = 0; tries < 2 && !n; tries++) {
		if (tries) {
			/* Re-edge the wake line and retry. */
			set_line(hwake, 1);	/* sleep */
			ms(50);
			set_line(hwake, 0);	/* assert (active low) */
			put("btwake: retry with fresh wake edge\n");
			ms(30);
		}
		n = hci_cmd(fd, "HCI Reset @115200", reset, 4, buf, sizeof(buf), 2000);
	}

	if (n && cc_ok(buf, n, 0x0c03)) {
		put("btwake: ROM answered at 115200\n");
		/* hci_bcm's order (n9bt67): after Reset, 100 ms, then Read
		 * Local Version at 115200.  Under hci_uart the chip never
		 * answered it; check whether the ROM does over the tty. */
		ms(100);
		hci_cmd(fd, "Read Local Version @115200", rdver, 4, buf, sizeof(buf), 1000);
		n = hci_cmd(fd, "VSC fc18 -> 3000000", to3m, 10, buf, sizeof(buf), 1000);
		if (n && cc_ok(buf, n, 0xfc18)) {
			if (set_speed(fd, B3000000) < 0)
				put("btwake: TCSETS 3M failed\n");
			ms(20);
			n = hci_cmd(fd, "Read Local Name @3M", rdname, 4, buf, sizeof(buf), 1000);
			if (n > 7) {
				/* 04 0e len ncmd 14 0c status name... */
				lb_str("btwake: local name ");
				for (int i = 7; i < n && buf[i]; i++) {
					char c[2] = { (char)buf[i], 0 };

					lb_str(c);
				}
				lb_end();
			}
			hci_cmd(fd, "Read Local Version @3M", rdver, 4, buf, sizeof(buf), 1000);
		}
	} else if (!n) {
		/* Old path, kept as the comparison point. */
		put("btwake: 115200 silent, trying 3M\n");
		if (set_speed(fd, B3000000) < 0)
			put("btwake: TCSETS 3M failed\n");
		ms(100);
		n = hci_cmd(fd, "HCI Reset @3M", reset, 4, buf, sizeof(buf), 2000);
		if (!n) {
			/* Every no-flow-control run so far had REG_ON at the
			 * wrong polarity; this leg has never been valid. */
			if (set_speed_fc(fd, B115200, 0) < 0)
				put("btwake: TCSETS 115200 noflow failed\n");
			ms(100);
			hci_cmd(fd, "HCI Reset @115200 noflow", reset, 4, buf,
				sizeof(buf), 2000);
		}
	}
	put("btwake: probe done\n");

	sc(SYS_close, fd, 0, 0, 0, 0);
	/* Hold BT_WAKE asserted so the chip stays awake for later tools. */
	for (;;)
		ms(1000);
}
