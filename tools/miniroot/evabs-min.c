/* Print the absolute-axis ranges of an evdev device (EVIOCGABS), freestanding.
 * usage: evabs-min /dev/input/event0   -> "abs <code> min max res fuzz flat value" lines
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o evabs-min tools/miniroot/evabs-min.c
 */
#define SYS_openat 56
#define SYS_write 64
#define SYS_ioctl 29
#define SYS_exit 93
#define AT_FDCWD (-100)
#define EVIOCGABS(a) (0x80184540UL + (a))

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
	b[i] = ' ';
	do {
		b[--i] = '0' + v % 10;
		v /= 10;
	} while (v);
	if (neg)
		b[--i] = '-';
	sc(SYS_write, 1, (long)&b[i], 24 - i);
}

void __attribute__((naked)) _start(void)
{
	__asm__ volatile("mov x0, sp\n bl main2\n");
}

void main2(long *sp)
{
	char **argv = (char **)(sp + 1);
	int abs_codes[] = { 0x00, 0x01, 0x2f, 0x35, 0x36, 0x30, 0x31, 0x32, 0x39 };
	long fd, i;
	int info[6];

	if (sp[0] < 2)
		sc(SYS_exit, 2, 0, 0);
	fd = sc(SYS_openat, AT_FDCWD, (long)argv[1], 0);
	if (fd < 0)
		sc(SYS_exit, 1, 0, 0);
	for (i = 0; i < (long)(sizeof(abs_codes) / sizeof(abs_codes[0])); i++) {
		if (sc(SYS_ioctl, fd, EVIOCGABS(abs_codes[i]), (long)info) < 0)
			continue;
		sc(SYS_write, 1, (long)"abs ", 4);
		putnum(abs_codes[i]);
		putnum(info[1]);	/* min */
		putnum(info[2]);	/* max */
		putnum(info[5]);	/* resolution */
		putnum(info[3]);	/* fuzz */
		putnum(info[4]);	/* flat */
		putnum(info[0]);	/* value */
		sc(SYS_write, 1, (long)"\n", 1);
	}
	sc(SYS_exit, 0, 0, 0);
}
