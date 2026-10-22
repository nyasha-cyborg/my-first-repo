/* Android-side helper: ask the vendor kernel's /dev/mdm driver to bring the MDM9K out of
 * reset (qcks does this with the WAKE_CHARM ioctl), then hold the fd open.
 * usage: mdmwake [hold-seconds]     (default 60)
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o mdmwake tools/miniroot/mdmwake.c
 * Only the wake ioctl is issued; no image is sent, no EFS partition is touched.
 */
#define SYS_openat 56
#define SYS_write 64
#define SYS_ioctl 29
#define SYS_nanosleep 101
#define SYS_exit 93
#define AT_FDCWD (-100)
#define WAKE_CHARM 0xcc01UL

static long sc(long n, long a, long b, long c)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b, x2 __asm__("x2") = c;

	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
	return x0;
}

static void putnum(long v)
{
	char b[24];
	int i = 23, neg = v < 0;

	if (neg)
		v = -v;
	b[i] = '\n';
	do {
		b[--i] = '0' + v % 10;
		v /= 10;
	} while (v);
	if (neg)
		b[--i] = '-';
	sc(SYS_write, 1, (long)&b[i], 24 - i);
}

static void say(const char *s)
{
	long n = 0;

	while (s[n])
		n++;
	sc(SYS_write, 1, (long)s, n);
}

void __attribute__((naked)) _start(void)
{
	__asm__ volatile("mov x0, sp\n bl main2\n");
}

void main2(long *sp)
{
	char **argv = (char **)(sp + 1);
	long secs = 60, fd, r, i;
	long ts[2];

	if (sp[0] > 1) {
		secs = 0;
		for (i = 0; argv[1][i]; i++)
			secs = secs * 10 + (argv[1][i] - '0');
	}
	fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/mdm", 2);
	say("open /dev/mdm -> ");
	putnum(fd);
	if (fd < 0)
		sc(SYS_exit, 1, 0, 0);
	r = sc(SYS_ioctl, fd, WAKE_CHARM, 0);
	say("WAKE_CHARM -> ");
	putnum(r);
	ts[0] = secs;
	ts[1] = 0;
	sc(SYS_nanosleep, (long)ts, 0, 0);
	sc(SYS_exit, 0, 0, 0);
}
