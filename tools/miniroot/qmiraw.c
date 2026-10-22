/* Send one raw QMUX frame to a cdc-wdm node and print the replies as hex (freestanding).
 * usage: qmiraw /dev/cdc-wdm0 <hex frame> [replies-to-wait-for]
 * Replies are printed one per line as hex; waits up to 4 s for the first, 1 s for further ones.
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o qmiraw tools/miniroot/qmiraw.c
 */
#define SYS_openat 56
#define SYS_write 64
#define SYS_read 63
#define SYS_ppoll 73
#define SYS_exit 93
#define AT_FDCWD (-100)

static long sc(long n, long a, long b, long c, long d)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b, x2 __asm__("x2") = c, x3 __asm__("x3") = d;

	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
	return x0;
}

static unsigned char req[1024], rsp[4096];

void __attribute__((naked)) _start(void)
{
	__asm__ volatile("mov x0, sp\n bl main2\n");
}

static int hexv(char c)
{
	return c <= '9' ? c - '0' : (c | 32) - 'a' + 10;
}

void main2(long *sp)
{
	char **argv = (char **)(sp + 1);
	long fd, n = 0, i, want = 1, got = 0;
	struct { int fd; short ev, rev; } pfd;
	long ts[2];

	if (sp[0] < 3)
		sc(SYS_exit, 2, 0, 0, 0);
	if (sp[0] > 3)
		want = argv[3][0] - '0';
	for (i = 0; argv[2][i] && argv[2][i + 1]; i += 2)
		req[n++] = hexv(argv[2][i]) * 16 + hexv(argv[2][i + 1]);
	fd = sc(SYS_openat, AT_FDCWD, (long)argv[1], 2, 0);
	if (fd < 0) {
		sc(SYS_write, 1, (long)"open failed\n", 12, 0);
		sc(SYS_exit, 1, 0, 0, 0);
	}
	if (sc(SYS_write, fd, (long)req, n, 0) != n)
		sc(SYS_write, 1, (long)"write failed\n", 13, 0);
	while (got < want) {
		pfd.fd = fd;
		pfd.ev = 1;	/* POLLIN */
		pfd.rev = 0;
		ts[0] = got ? 1 : 4;
		ts[1] = 0;
		if (sc(SYS_ppoll, (long)&pfd, 1, (long)ts, 0) <= 0)
			break;
		n = sc(SYS_read, fd, (long)rsp, sizeof(rsp), 0);
		if (n <= 0)
			break;
		for (i = 0; i < n; i++) {
			char h[2] = { "0123456789abcdef"[rsp[i] >> 4], "0123456789abcdef"[rsp[i] & 15] };

			sc(SYS_write, 1, (long)h, 2, 0);
		}
		sc(SYS_write, 1, (long)"\n", 1, 0);
		got++;
	}
	if (!got)
		sc(SYS_write, 1, (long)"no reply\n", 9, 0);
	sc(SYS_exit, 0, 0, 0, 0);
}
