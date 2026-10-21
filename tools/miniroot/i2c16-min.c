/* Read or write one 16-bit big-endian register of a TFA98xx-style I2C device
 * over /dev/i2c-N (I2C_SLAVE_FORCE, so it works while a driver owns the slave).
 *
 *   i2c16-min <bus> <slave-hex> <reg-hex>             -> prints the 16-bit value
 *   i2c16-min <bus> <slave-hex> <reg-hex> <val-hex>   -> writes it
 *
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o i2c16-min tools/miniroot/i2c16-min.c
 */
#define SYS_openat 56
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
	char **argv = (char **)(sp + 1);
	long argc = sp[0], fd;
	char path[] = "/dev/i2c-0";
	unsigned char b[3], v[2];
	char out[8];
	static const char hx[] = "0123456789abcdef";

	if (argc < 4)
		sc(SYS_exit, 2, 0, 0, 0, 0);
	path[9] = argv[1][0];
	fd = sc(SYS_openat, AT_FDCWD, (long)path, O_RDWR, 0, 0);
	if (fd < 0 || sc(SYS_ioctl, fd, I2C_SLAVE_FORCE, hex(argv[2]), 0, 0) < 0)
		sc(SYS_exit, 3, 0, 0, 0, 0);
	b[0] = hex(argv[3]);
	if (argc >= 5) {
		long val = hex(argv[4]);

		b[1] = val >> 8;
		b[2] = val & 0xff;
		if (sc(SYS_write, fd, (long)b, 3, 0, 0) != 3)
			sc(SYS_exit, 4, 0, 0, 0, 0);
		sc(SYS_exit, 0, 0, 0, 0, 0);
	}
	if (sc(SYS_write, fd, (long)b, 1, 0, 0) != 1 ||
	    sc(SYS_read, fd, (long)v, 2, 0, 0) != 2)
		sc(SYS_exit, 5, 0, 0, 0, 0);
	out[0] = hx[v[0] >> 4];
	out[1] = hx[v[0] & 15];
	out[2] = hx[v[1] >> 4];
	out[3] = hx[v[1] & 15];
	out[4] = '\n';
	sc(SYS_write, 1, (long)out, 5, 0, 0);
	sc(SYS_exit, 0, 0, 0, 0, 0);
}

__attribute__((naked)) void _start(void)
{
	__asm__("mov x0, sp\n\tbl c_main\n");
}
