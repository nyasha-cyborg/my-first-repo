/* Minimal hciattach for the BCM4354 on flounder: put the UART into the
 * N_HCI line discipline and select the Broadcom (H4) protocol. Then stay
 * alive holding the fd, because the ldisc is torn down on close.
 *
 * usage: hciattach-min /dev/ttyTHS2
 */
#define SYS_openat   56
#define SYS_close    57
#define SYS_ioctl    29
#define SYS_nanosleep 101
#define SYS_exit     93
#define SYS_write    64

#define AT_FDCWD (-100)
#define O_RDWR    2
#define O_NOCTTY  0400
#define O_NONBLOCK 04000

#define TCSETS2 0x402c542b
#define TCGETS2 0x802c542a
#define BOTHER 0x1000
#define TIOCSETD 0x5423
#define N_HCI 15
#define HCIUARTSETPROTO 0x400455c8
#define HCI_UART_BCM 7

#define CS8 0x30
#define CREAD 0x80
#define CLOCAL 0x800
#define B115200 0x1002
#define CRTSCTS 0x80000000u

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

static long slen(const char *s)
{
	long n = 0;

	while (s[n])
		n++;
	return n;
}

static void say(const char *s)
{
	sc(SYS_write, 2, (long)s, slen(s), 0, 0);
}

void _start(void)
{
	int argc;
	char **argv;
	const char *path;
	struct termios_k t;
	int ldisc = N_HCI, proto = HCI_UART_BCM;
	long fd, rc;
	unsigned int baud = 0;
	struct { long s, ns; } ts = { 1, 0 };

	{
		long *sp;

		/* At _start the kernel passes argc/argv on the stack. */
		__asm__ volatile("mov %0, sp" : "=r"(sp));
		argc = (int)sp[0];
		argv = (char **)(sp + 1);
	}
	path = (argc > 1) ? argv[1] : "/dev/ttyTHS2";
	if (argc > 2) {
		const char *b = argv[2];
		while (*b >= '0' && *b <= '9')
			baud = baud * 10 + (unsigned int)(*b++ - '0');
	}

	fd = sc(SYS_openat, AT_FDCWD, (long)path, O_RDWR | O_NOCTTY | O_NONBLOCK, 0, 0);
	if (fd < 0) {
		say("hciattach: open failed\n");
		sc(SYS_exit, 1, 0, 0, 0, 0);
	}

	for (int i = 0; i < (int)sizeof(t); i++)
		((char *)&t)[i] = 0;
	t.c_cflag = CS8 | CREAD | CLOCAL | CRTSCTS;
	if (baud && baud != 115200) {
		t.c_cflag |= BOTHER;
		t.c_ispeed = t.c_ospeed = baud;
	} else {
		/* TCSETS2 without BOTHER takes the speed from CBAUD in
		 * c_cflag; leaving it 0 means B0, i.e. hang up. */
		t.c_cflag |= B115200;
		t.c_ispeed = t.c_ospeed = 115200;
	}

	rc = sc(SYS_ioctl, fd, TCSETS2, (long)&t, 0, 0);
	if (rc < 0)
		say("hciattach: TCSETS failed\n");
	else {
		struct termios_k r;

		for (int i = 0; i < (int)sizeof(r); i++)
			((char *)&r)[i] = 0;
		if (sc(SYS_ioctl, fd, TCGETS2, (long)&r, 0, 0) >= 0) {
			static const char hx[] = "0123456789abcdef";
			char b[24];
			int k = 0, sh;
			const char *m = "hciattach: speed=";

			while (*m) b[k++] = *m++;
			for (sh = 28; sh >= 0; sh -= 4)
				b[k++] = hx[(r.c_ospeed >> sh) & 0xf];
			b[k++] = '\n';
			sc(SYS_write, 2, (long)b, k, 0, 0);
		}
	}

	rc = sc(SYS_ioctl, fd, TIOCSETD, (long)&ldisc, 0, 0);
	if (rc < 0) {
		say("hciattach: TIOCSETD N_HCI failed\n");
		sc(SYS_exit, 2, 0, 0, 0, 0);
	}

	/* HCIUARTSETPROTO takes the protocol value, not a pointer. */
	rc = sc(SYS_ioctl, fd, HCIUARTSETPROTO, (long)proto, 0, 0);
	if (rc < 0) {
		say("hciattach: HCIUARTSETPROTO BCM failed\n");
		sc(SYS_exit, 3, 0, 0, 0, 0);
	}
	say("hciattach: attached\n");

	for (;;)
		sc(SYS_nanosleep, (long)&ts, 0, 0, 0, 0);
}
