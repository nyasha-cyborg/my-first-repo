/* btwake: reproduce Android bluedroid_pm's BT_WAKE behaviour on the flounder
 * BCM4350C0, then probe HCI on the BT UART.
 *
 * Android raises BT_WAKE (PEE1) only when the stack wants to transmit and
 * drops it when the chip reports idle.  Holding the line statically high from
 * boot (as a fixed regulator does) is not the same signal: the chip comes up
 * with the line already asserted and never sees the idle->wake transition.
 *
 * This tool drives PEE1 low, then high, waits for the chip to settle, opens
 * the UART at Android's 3 Mbaud/crtscts settings, sends an HCI Reset, and
 * retries once with a fresh wake edge if the first frame is unanswered.
 *
 * usage: btwake [chip] [wake_line] [baud]
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

/* GPIO v1 chardev ioctls (CONFIG_GPIO_CDEV_V1) */
#define GPIOHANDLE_GET_LINE_IOCTL 0xC14CB403
#define GPIOHANDLE_SET_LINE_VALUES_IOCTL 0xC040B405
#define GPIOHANDLE_REQUEST_OUTPUT 1

/* Android's live termios on /dev/ttyTHS2: legacy TCSETS, speed 3000000
 * (B3000000 == 0x100d), cs8|cread|clocal|crtscts. */
#define TCSETS 0x5402
#define TIOCSETD 0x5423
#define B3000000 0x100d
#define B115200 0x1002
#define CS8 0x30
#define CREAD 0x80
#define CLOCAL 0x800
#define CRTSCTS 0x8000

struct gpiohandle_request {
	unsigned int lineoffsets[64];
	unsigned int flags;
	unsigned char default_values[64];
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
	long n = 0;

	while (s[n]) n++;
	sc(SYS_write, 2, (long)s, n, 0, 0);
}

static void puthex(unsigned char v)
{
	static const char hx[] = "0123456789abcdef";

	sc(SYS_write, 2, (long)&hx[v >> 4], 1, 0, 0);
	sc(SYS_write, 2, (long)&hx[v & 0xf], 1, 0, 0);
}

static void putdec(long v)
{
	char b[20];
	int i = 0;

	if (v < 0) { put("-"); v = -v; }
	if (!v) b[i++] = '0';
	while (v) { b[i++] = '0' + (v % 10); v /= 10; }
	while (i) sc(SYS_write, 2, (long)&b[--i], 1, 0, 0);
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
	return -1;
}

static int out_line(const char *chip, unsigned int line, unsigned int init)
{
	struct gpiohandle_request req;
	long fd, rc;

	fd = sc(SYS_openat, AT_FDCWD, (long)chip, O_RDWR, 0, 0);
	if (fd < 0) {
		put("btwake: chip open errno "); putdec(-fd); put("\n");
		return -1;
	}
	for (unsigned int i = 0; i < sizeof(req); i++)
		((char *)&req)[i] = 0;
	req.lineoffsets[0] = line;
	req.flags = GPIOHANDLE_REQUEST_OUTPUT;
	req.default_values[0] = (unsigned char)init;
	req.lines = 1;
	rc = sc(SYS_ioctl, fd, GPIOHANDLE_GET_LINE_IOCTL, (long)&req, 0, 0);
	sc(SYS_close, fd, 0, 0, 0, 0);
	if (rc < 0) {
		put("btwake: line request errno "); putdec(-rc); put("\n");
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
	int wake = (argc > 1) ? num(argv[1]) : 241;
	int baud = (argc > 2) ? num(argv[2]) : 3000000;
	struct termios_k t;
	int ldisc = 0;
	long fd, n;
	unsigned char reset[4] = { 0x01, 0x03, 0x0c, 0x00 };
	unsigned char buf[64];
	int hwake, tries;

	if (find_chip((unsigned int)wake, &offset, chipbuf) < 0) {
		/* Fall back to the raw number on chip 0. */
		chip = "/dev/gpiochip0";
		offset = (unsigned int)wake;
		put("btwake: chip lookup failed, trying chip0\n");
	} else {
		chip = chipbuf;
		put("btwake: user line ");
		putdec(wake);
		put(" -> ");
		put(chip);
		put(" offset ");
		putdec(offset);
		put("\n");
	}

	hwake = out_line(chip, offset, 0);	/* start idle/low */
	if (hwake < 0) {
		put("btwake: wake line unavailable\n");
		sc(SYS_exit, 1, 0, 0, 0, 0);
	}
	put("btwake: wake low\n");
	ms(250);
	if (set_line(hwake, 1) < 0)
		put("btwake: wake high set failed\n");
	put("btwake: wake high\n");
	ms(30);

	fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/ttyTHS2",
		O_RDWR | O_NOCTTY | O_NONBLOCK, 0, 0);
	if (fd < 0) {
		put("btwake: tty open failed\n");
		sc(SYS_exit, 2, 0, 0, 0, 0);
	}
	sc(SYS_ioctl, fd, TIOCSETD, (long)&ldisc, 0, 0);	/* N_TTY */
	for (unsigned int i = 0; i < sizeof(t); i++)
		((char *)&t)[i] = 0;
	t.c_cflag = ((baud == 3000000) ? B3000000 : B115200)
		    | CS8 | CREAD | CLOCAL | CRTSCTS;
	if (sc(SYS_ioctl, fd, TCSETS, (long)&t, 0, 0) < 0)
		put("btwake: TCSETS failed\n");
	ms(120);					/* Android: 100 ms settlement */

	for (tries = 0; tries < 2; tries++) {
		if (tries) {
			/* Re-edge the wake line and retry. */
			set_line(hwake, 0);
			put("btwake: retry: wake low\n");
			ms(250);
			set_line(hwake, 1);
			put("btwake: retry: wake high\n");
			ms(30);
		}
		put("btwake: sending HCI Reset\n");
		sc(SYS_write, fd, (long)reset, 4, 0, 0);
		for (n = 0; n < 10; n++) {
			long r = sc(SYS_read, fd, (long)buf, sizeof(buf), 0, 0);

			if (r > 0) {
				long i;

				put("btwake: got ");
				for (i = 0; i < r; i++) {
					puthex(buf[i]);
					sc(SYS_write, 2, (long)" ", 1, 0, 0);
				}
				put("\n");
				break;
			}
			ms(200);
		}
		if (n < 10) {
			put("btwake: done (reply)\n");
			break;
		}
		put("btwake: no reply in 2s\n");
	}

	sc(SYS_close, fd, 0, 0, 0, 0);
	/* Hold BT_WAKE asserted so the chip stays awake for later tools. */
	for (;;)
		ms(1000);
}
