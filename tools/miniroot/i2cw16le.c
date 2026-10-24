/* Write one 16-bit little-endian register (MAX17050 style) and read it back (freestanding).
 * usage: i2cw16le <bus> <addr-hex> <reg-hex> <val-hex>
 * Prints "rr: old=vvvv new=vvvv". Uses I2C_RDWR, so it also works on an address a driver owns.
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o i2cw16le tools/miniroot/i2cw16le.c
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

static void puts_(const char *s)
{
	long n = 0;

	while (s[n])
		n++;
	sc(SYS_write, 1, (long)s, n, 0);
}

static void puthex(unsigned v, int digits)
{
	char b[8];
	int i;

	for (i = digits - 1; i >= 0; i--, v >>= 4)
		b[i] = "0123456789abcdef"[v & 15];
	sc(SYS_write, 1, (long)b, digits, 0);
}

static long rd16(long fd, unsigned short addr, unsigned char reg)
{
	unsigned char d[2];
	struct i2c_msg m[2] = {
		{ addr, 0, 1, &reg },
		{ addr, I2C_M_RD, 2, d },
	};
	struct i2c_rdwr x = { m, 2 };

	if (sc(SYS_ioctl, fd, I2C_RDWR, (long)&x, 0) != 2)
		return -1;
	return d[0] | d[1] << 8;
}

void main2(long *sp)
{
	char **argv = (char **)(sp + 1);
	char dev[16] = "/dev/i2c-";
	unsigned short addr;
	unsigned char reg, b[3];
	long fd, val, old, now, i;
	struct i2c_msg m;
	struct i2c_rdwr x;

	if (sp[0] != 5) {
		puts_("usage: i2cw16le <bus> <addr-hex> <reg-hex> <val-hex>\n");
		sc(SYS_exit, 2, 0, 0, 0);
	}
	for (i = 0; argv[1][i] && i < 4; i++)
		dev[9 + i] = argv[1][i];
	dev[9 + i] = 0;
	addr = hex(argv[2]);
	reg = hex(argv[3]);
	val = hex(argv[4]);
	fd = sc(SYS_openat, AT_FDCWD, (long)dev, 2, 0);
	if (fd < 0) {
		puts_("open failed\n");
		sc(SYS_exit, 1, 0, 0, 0);
	}
	old = rd16(fd, addr, reg);
	b[0] = reg; b[1] = val & 0xff; b[2] = val >> 8;
	m.addr = addr; m.flags = 0; m.len = 3; m.buf = b;
	x.msgs = &m;
	x.nmsgs = 1;
	if (sc(SYS_ioctl, fd, I2C_RDWR, (long)&x, 0) != 1) {
		puts_("write failed\n");
		sc(SYS_exit, 1, 0, 0, 0);
	}
	now = rd16(fd, addr, reg);
	puthex(reg, 2);
	puts_(": old=");
	puthex(old, 4);
	puts_(" new=");
	puthex(now, 4);
	puts_("\n");
	sc(SYS_exit, 0, 0, 0, 0);
}
