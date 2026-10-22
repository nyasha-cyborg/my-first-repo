/* Receive N raw bytes from the console tty (stdin) into a file, with a byte-sum check.
 * usage: rxfile <path> <nbytes>      (run on the tablet's serial shell; pair: tools/n9push.py)
 * Puts the tty in raw mode, prints "RXREADY", reads exactly N bytes in 16384-byte blocks and
 * answers every block with one ACK byte (0x06) so the sender cannot overrun the tty buffers,
 * writes them to <path>, restores the tty and prints "rx ok <n> sum=<hex>".
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o rxfile tools/miniroot/rxfile.c
 */
#define SYS_openat 56
#define SYS_close 57
#define SYS_read 63
#define SYS_write 64
#define SYS_ioctl 29
#define SYS_exit 93
#define AT_FDCWD (-100)
#define TCGETS 0x5401
#define TCSETS 0x5402
#define O_WRONLY_CREAT_TRUNC (1 | 0100 | 01000)

typedef unsigned int u32;
typedef unsigned long u64;

struct tio { u32 iflag, oflag, cflag, lflag; unsigned char line, cc[19]; };

static unsigned char buf[1 << 16];

static long sc(long n, long a, long b, long c)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b, x2 __asm__("x2") = c;

	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
	return x0;
}

static void say(const char *s)
{
	long n = 0;

	while (s[n])
		n++;
	sc(SYS_write, 1, (long)s, n);
}

static void hex(u64 v)
{
	char b[20];
	int i = 19;

	b[i] = 0;
	do {
		b[--i] = "0123456789abcdef"[v & 15];
		v >>= 4;
	} while (v);
	say(&b[i]);
}

void __attribute__((naked)) _start(void)
{
	__asm__ volatile("mov x0, sp\n bl main2\n");
}

void main2(long *sp)
{
	char **argv = (char **)(sp + 1);
	struct tio old, raw;
	u64 total = 0, got = 0;
	u32 sum = 0;
	long fd, r, i, tty;

	if (sp[0] < 3)
		sc(SYS_exit, 2, 0, 0);
	for (i = 0; argv[2][i]; i++)
		total = total * 10 + (argv[2][i] - '0');
	fd = sc(SYS_openat, AT_FDCWD, (long)argv[1], O_WRONLY_CREAT_TRUNC);
	if (fd < 0)
		sc(SYS_exit, 1, 0, 0);
	/* the console shell runs commands with </dev/null: open the gadget tty ourselves */
	tty = sc(SYS_openat, AT_FDCWD, (long)"/dev/ttyGS0", 2 | 0400 /* O_RDWR|O_NOCTTY */);
	if (tty < 0)
		sc(SYS_exit, 1, 0, 0);
	sc(SYS_ioctl, tty, TCGETS, (long)&old);
	raw = old;
	raw.iflag = 0;
	raw.oflag = 0;
	raw.lflag = 0;
	raw.cc[6] = 1;	/* VMIN */
	raw.cc[5] = 0;	/* VTIME */
	sc(SYS_ioctl, tty, TCSETS, (long)&raw);
	say("RXREADY\n");
	while (got < total) {
		u64 want = total - got > 16384 ? 16384 : total - got, have = 0;

		while (have < want) {
			r = sc(SYS_read, tty, (long)buf + have, want - have);
			if (r <= 0)
				goto out;
			have += r;
		}
		for (i = 0; i < (long)have; i++)
			sum += buf[i];
		sc(SYS_write, fd, (long)buf, have);
		got += have;
		sc(SYS_write, 1, (long)"\006", 1);
	}
out:
	sc(SYS_close, fd, 0, 0);
	sc(SYS_ioctl, tty, TCSETS, (long)&old);
	say("\nrx ok ");
	hex(got);
	say(" sum=");
	hex(sum);
	say("\n");
	sc(SYS_exit, got == total ? 0 : 1, 0, 0);
}
