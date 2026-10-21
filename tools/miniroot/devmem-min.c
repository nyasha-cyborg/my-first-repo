/* Read 32-bit physical registers through /dev/mem (read-only), freestanding.
 * usage: devmem-min <hex-addr> [<hex-addr> ...]    prints "addr=value" lines
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o devmem-min tools/miniroot/devmem-min.c
 */
#define SYS_openat 56
#define SYS_write 64
#define SYS_pread64 67
#define SYS_exit 93
#define AT_FDCWD (-100)

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
	long argc = sp[0], fd, i, k;
	static const char hx[] = "0123456789abcdef";
	char out[24];
	unsigned int v;

	fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/mem", 0, 0, 0);
	if (fd < 0)
		sc(SYS_exit, 2, 0, 0, 0, 0);
	for (i = 1; i < argc; i++) {
		long a = hex(argv[i]);

		v = 0;
		k = sc(SYS_pread64, fd, (long)&v, 4, a, 0);
		for (int j = 0; j < 8; j++)
			out[j] = hx[(a >> (28 - 4 * j)) & 15];
		out[8] = '=';
		if (k != 4) {
			out[9] = '?'; out[10] = '\n';
			sc(SYS_write, 1, (long)out, 11, 0, 0);
			continue;
		}
		for (int j = 0; j < 8; j++)
			out[9 + j] = hx[(v >> (28 - 4 * j)) & 15];
		out[17] = '\n';
		sc(SYS_write, 1, (long)out, 18, 0, 0);
	}
	sc(SYS_exit, 0, 0, 0, 0, 0);
}

__attribute__((naked)) void _start(void)
{
	__asm__("mov x0, sp\n\tbl c_main\n");
}
