/* Read-only i2c register dump (freestanding).  Never writes a register.
 * usage: i2cread <bus> <addr-hex> <first-reg-hex> <count> [w]
 * Prints "rr=vv" per register (byte reads), or "rr=vvvv" little-endian 16-bit words with "w" (MAX17050 style).
 * Uses I2C_RDWR (write register pointer + read in one combined transfer), so it also works on an address a driver owns.
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o i2cread tools/miniroot/i2cread.c
 */
#define SYS_ioctl 29
#define SYS_openat 56
#define SYS_write 64
#define SYS_exit 93
#define AT_FDCWD (-100)
#define I2C_RDWR 0x0707
#define I2C_M_RD 1

static long sc(long n, long a, long b, long c, long d)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b, x2 __asm__("x2") = c, x3 __asm__("x3") = d;

	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
	return x0;
}

void __attribute__((naked)) _start(void)
{
	__asm__ volatile("mov x0, sp\n bl main2\n");
}

struct i2c_msg { unsigned short addr, flags, len; unsigned char *buf; };
struct i2c_rdwr { struct i2c_msg *msgs; unsigned nmsgs; };

static long hex(const char *s)
{
	long v = 0;

	for (; *s; s++)
		v = v * 16 + (*s <= '9' ? *s - '0' : (*s | 32) - 'a' + 10);
	return v;
}

static long dec(const char *s)
{
	long v = 0;

	for (; *s; s++)
		v = v * 10 + *s - '0';
	return v;
}

static void puthex(unsigned v, int digits)
{
	char b[8];
	int i;

	for (i = digits - 1; i >= 0; i--, v >>= 4)
		b[i] = "0123456789abcdef"[v & 15];
	sc(SYS_write, 1, (long)b, digits, 0);
}

void main2(long *sp)
{
	char **argv = (char **)(sp + 1);
	char dev[16] = "/dev/i2c-";
	long fd, reg, n, i, w;
	unsigned char r, d[2];
	struct i2c_msg m[2];
	struct i2c_rdwr x;

	if (sp[0] < 5)
		sc(SYS_exit, 2, 0, 0, 0);
	for (i = 0; argv[1][i] && i < 4; i++)
		dev[9 + i] = argv[1][i];
	dev[9 + i] = 0;
	w = sp[0] > 5;
	reg = hex(argv[3]);
	n = dec(argv[4]);
	fd = sc(SYS_openat, AT_FDCWD, (long)dev, 2, 0);
	if (fd < 0) {
		sc(SYS_write, 1, (long)"open failed\n", 12, 0);
		sc(SYS_exit, 1, 0, 0, 0);
	}
	for (i = 0; i < n; i++) {
		r = reg + i;
		m[0].addr = hex(argv[2]); m[0].flags = 0; m[0].len = 1; m[0].buf = &r;
		m[1].addr = m[0].addr; m[1].flags = I2C_M_RD; m[1].len = w ? 2 : 1; m[1].buf = d;
		x.msgs = m;
		x.nmsgs = 2;
		puthex(r, 2);
		sc(SYS_write, 1, (long)"=", 1, 0);
		if (sc(SYS_ioctl, fd, I2C_RDWR, (long)&x, 0) != 2)
			sc(SYS_write, 1, (long)"err", 3, 0);
		else if (w)
			puthex(d[0] | d[1] << 8, 4);
		else
			puthex(d[0], 2);
		sc(SYS_write, 1, (long)"\n", 1, 0);
	}
	sc(SYS_exit, 0, 0, 0, 0);
}
