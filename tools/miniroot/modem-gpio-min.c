/* Flounder LTE modem GPIO helper over the gpio character device (v2 uAPI),
 * freestanding aarch64.  Sequence taken from the Android kernel
 * (`modem_power_on` / `mdm_subsys_powerup`, see notes/lte.md).
 *
 * usage: modem-gpio-min read          print the six MDM2AP_* input lines
 *        modem-gpio-min on [secs]     run the power-on sequence, then watch the
 *                                     inputs for [secs] (default 20) and exit;
 *                                     lines are released on exit (outputs fall
 *                                     back to inputs), so pair with `hold`.
 *        modem-gpio-min hold [mask]   power on and stay running (outputs held);
 *                                     mask bit0 = AP2MDM_WAKEUP high, bit1 =
 *                                     AP2MDM_ERRFATAL high (experiments)
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o modem-gpio-min tools/miniroot/modem-gpio-min.c
 */
#include <linux/gpio.h>
#include <linux/ioctl.h>

#define SYS_openat 56
#define SYS_close 57
#define SYS_ioctl 29
#define SYS_write 64
#define SYS_exit 93
#define SYS_ppoll 73
#define SYS_nanosleep 101
#define AT_FDCWD (-100)

#define AP2MDM_WAKEUP 113
#define AP2MDM_STATUS 114
#define AP2MDM_ERRFATAL 115
#define AP2MDM_PMIC_RESET_N 221
#define MDM2AP_ERRFATAL 168
#define MDM2AP_STATUS 150
#define MDM2AP_WAKEUP 149
#define MDM2AP_HSIC_READY 169
#define MDM2AP_IPC3 144
#define MDM2AP_VDD_MIN 226

static long sc(long n, long a, long b, long c)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b, x2 __asm__("x2") = c;

	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
	return x0;
}

void *memset(void *d, int c, unsigned long n)
{
	unsigned char *p = d;

	while (n--)
		*p++ = c;
	return d;
}

static void out(const char *s)
{
	long n = 0;

	while (s[n])
		n++;
	sc(SYS_write, 1, (long)s, n);
}

static void outnum(const char *tag, long v)
{
	char b[32];
	int i = 31;

	b[i] = 0;
	do {
		b[--i] = '0' + v % 10;
		v /= 10;
	} while (v);
	out(tag);
	out(&b[i]);
	out(" ");
}

static void msleep(long ms)
{
	struct { long s, ns; } ts = { ms / 1000, (ms % 1000) * 1000000 };

	sc(SYS_nanosleep, (long)&ts, 0, 0);
}

static long chip;

static long request(const unsigned int *lines, int n, int output, unsigned long long initial)
{
	struct gpio_v2_line_request req;
	int i;

	memset(&req, 0, sizeof(req));
	for (i = 0; i < n; i++)
		req.offsets[i] = lines[i];
	req.num_lines = n;
	req.config.flags = output ? GPIO_V2_LINE_FLAG_OUTPUT : GPIO_V2_LINE_FLAG_INPUT;
	if (output) {
		req.config.num_attrs = 1;
		req.config.attrs[0].mask = (1ULL << n) - 1;
		req.config.attrs[0].attr.id = GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES;
		req.config.attrs[0].attr.values = initial;
	}
	req.consumer[0] = 'm'; req.consumer[1] = 'd'; req.consumer[2] = 'm';
	if (sc(SYS_ioctl, chip, GPIO_V2_GET_LINE_IOCTL, (long)&req) < 0)
		return -1;
	return req.fd;
}

static void setvals(long fd, int n, unsigned long long vals)
{
	struct gpio_v2_line_values v;

	v.bits = vals;
	v.mask = (1ULL << n) - 1;
	sc(SYS_ioctl, fd, GPIO_V2_LINE_SET_VALUES_IOCTL, (long)&v);
}

static unsigned long long getvals(long fd, int n)
{
	struct gpio_v2_line_values v;

	v.bits = 0;
	v.mask = (1ULL << n) - 1;
	sc(SYS_ioctl, fd, GPIO_V2_LINE_GET_VALUES_IOCTL, (long)&v);
	return v.bits;
}

static void show(long in)
{
	unsigned long long v = getvals(in, 6);

	outnum("MDM2AP_STATUS=", v & 1);
	outnum("HSIC_READY=", v >> 1 & 1);
	outnum("ERRFATAL=", v >> 2 & 1);
	outnum("WAKEUP=", v >> 3 & 1);
	outnum("IPC3=", v >> 4 & 1);
	outnum("VDD_MIN=", v >> 5 & 1);
	out("\n");
}

void __attribute__((naked)) _start(void)
{
	__asm__ volatile("mov x0, sp\n bl main2\n");
}

void main2(long *sp)
{
	static const unsigned int inl[6] = { MDM2AP_STATUS, MDM2AP_HSIC_READY,
		MDM2AP_ERRFATAL, MDM2AP_WAKEUP, MDM2AP_IPC3, MDM2AP_VDD_MIN };
	/* order: wakeup, status, errfatal, pmic_reset_n */
	static const unsigned int outl[4] = { AP2MDM_WAKEUP, AP2MDM_STATUS,
		AP2MDM_ERRFATAL, AP2MDM_PMIC_RESET_N };
	char **argv = (char **)(sp + 1);
	const char *mode = sp[0] > 1 ? argv[1] : "read";
	long secs = 20, i, in, o;

	if (sp[0] > 2) {
		secs = 0;
		for (i = 0; argv[2][i]; i++)
			secs = secs * 10 + argv[2][i] - '0';
	}
	chip = sc(SYS_openat, AT_FDCWD, (long)"/dev/gpiochip0", 2);
	if (chip < 0) {
		out("no /dev/gpiochip0\n");
		sc(SYS_exit, 1, 0, 0);
	}
	in = request(inl, 6, 0, 0);
	if (in < 0) {
		out("input request failed\n");
		sc(SYS_exit, 1, 0, 0);
	}
	out("inputs: ");
	show(in);
	if (mode[0] == 'r')
		sc(SYS_exit, 0, 0, 0);

	/* all four AP2MDM outputs low (wakeup, status, errfatal, pmic_reset_n) */
	o = request(outl, 4, 1, 0);
	if (o < 0) {
		out("output request failed\n");
		sc(SYS_exit, 1, 0, 0);
	}
	out("power on: PMIC_RESET_N low 10 ms\n");
	msleep(10);
	out("PMIC_RESET_N high\n");
	setvals(o, 4, 1ULL << 3);
	msleep(40);
	out("AP2MDM_STATUS high\n");
	setvals(o, 4, (1ULL << 3) | (1ULL << 1));
	msleep(240);
	if (mode[0] == 'h' && sp[0] > 2) {
		unsigned long long v = (1ULL << 3) | (1ULL << 1);

		if (secs & 1)
			v |= 1ULL << 0;	/* AP2MDM_WAKEUP */
		if (secs & 2)
			v |= 1ULL << 2;	/* AP2MDM_ERRFATAL */
		setvals(o, 4, v);
		outnum("outputs=", (long)v);
		out("\n");
	}
	for (i = 0; i < (mode[0] == 'h' ? 100000 : secs); i++) {
		out("t+");
		outnum("", i);
		show(in);
		msleep(1000);
	}
	sc(SYS_exit, 0, 0, 0);
}
