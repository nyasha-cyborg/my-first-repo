/* Read one register over /dev/i2c-N (SMBus-style byte read), freestanding.
 * usage: i2cget-min <bus> <slave-hex> <reg-hex>   e.g. i2cget-min 4 59 f9
 * Uses I2C_SLAVE_FORCE, so it works while a kernel driver owns the slave.
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -o i2cget-min tools/miniroot/i2cget-min.c
 */
#define SYS_openat 56
#define SYS_close 57
#define SYS_read 63
#define SYS_write 64
#define SYS_ioctl 29
#define SYS_exit 93
#define AT_FDCWD (-100)
#define O_RDWR 2
#define I2C_SLAVE_FORCE 0x0706

static long sc(long n, long a, long b, long c, long d, long e)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b, x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d, x4 __asm__("x4") = e;

	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4) : "memory");
	return x0;
}

static long hex(const char *s)
{
	long v = 0;

	for (; *s; s++) {
		v <<= 4;
		v |= (*s >= 'a') ? *s - 'a' + 10 : (*s >= 'A') ? *s - 'A' + 10 : *s - '0';
	}
	return v;
}

void c_main(long *sp)
{
	char **argv;
	char path[] = "/dev/i2c-0";
	unsigned char reg, val = 0;
	char out[8] = "00\n";
	static const char hx[] = "0123456789abcdef";
	long fd, rc;

	argv = (char **)(sp + 1);
	if (sp[0] < 4)
		sc(SYS_exit, 2, 0, 0, 0, 0);
	path[9] = argv[1][0];
	reg = hex(argv[3]);
	fd = sc(SYS_openat, AT_FDCWD, (long)path, O_RDWR, 0, 0);
	if (fd < 0)
		sc(SYS_exit, 3, 0, 0, 0, 0);
	if (sc(SYS_ioctl, fd, I2C_SLAVE_FORCE, hex(argv[2]), 0, 0) < 0)
		sc(SYS_exit, 4, 0, 0, 0, 0);
	rc = sc(SYS_write, fd, (long)&reg, 1, 0, 0);
	if (rc != 1)
		sc(SYS_exit, 5, 0, 0, 0, 0);
	rc = sc(SYS_read, fd, (long)&val, 1, 0, 0);
	if (rc != 1)
		sc(SYS_exit, 6, 0, 0, 0, 0);
	out[0] = hx[val >> 4];
	out[1] = hx[val & 15];
	sc(SYS_write, 1, (long)out, 3, 0, 0);
	sc(SYS_exit, 0, 0, 0, 0, 0);
}

__attribute__((naked)) void _start(void)
{
	__asm__("mov x0, sp\n\tbl c_main\n");
}
