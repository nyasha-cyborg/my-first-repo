/* Minimal test init: tty first, then an armed+pinged watchdog, then sh.
 * The pinger proves whether userspace is still running after a later stall:
 * pings stop -> hardware reset; pings continue -> only the tty path is dead. */
#define SYS_mount     40
#define SYS_openat    56
#define SYS_write     64
#define SYS_execve    221
#define SYS_dup3      24
#define SYS_nanosleep 101
#define SYS_clone     220

#define AT_FDCWD (-100)
#define O_RDWR   2
#define O_WRONLY 1
#define O_RDONLY 0

static long sc(long n, long a, long b, long c, long d, long e)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b;
	register long x2 __asm__("x2") = c, x3 __asm__("x3") = d, x4 __asm__("x4") = e;
	__asm__ volatile("svc 0" : "+r"(x0)
			 : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4) : "memory");
	return x0;
}

static void sleep_ms(long ms)
{
	struct { long s, ns; } ts = { ms / 1000, (ms % 1000) * 1000000L };

	sc(SYS_nanosleep, (long)&ts, 0, 0, 0, 0);
}

static void say(const char *s)
{
	long n = 0;

	while (s[n])
		n++;
	sc(SYS_write, 1, (long)s, n, 0, 0);
}

static void ping_loop(long fd)
{
	static const char b = 0;

	for (;;) {
		sleep_ms(20000);
		if (sc(SYS_openat, AT_FDCWD, (long)"/stop-ping", O_RDONLY, 0, 0) >= 0)
			break;
		sc(SYS_write, fd, (long)&b, 1, 0, 0);
	}
	for (;;)
		sleep_ms(60000);
}

void _start(void)
{
	static const char *envp[] = { "PATH=/bin:/sbin:/usr/bin", "HOME=/", 0 };
	static const char *argv[] = { "sh", "-i", 0 };
	long fd = -1, wfd;
	int i;

	sc(SYS_mount, (long)"devtmpfs", (long)"/dev", (long)"devtmpfs", 0, 0);
	sc(SYS_mount, (long)"proc", (long)"/proc", (long)"proc", 0, 0);
	sc(SYS_mount, (long)"sysfs", (long)"/sys", (long)"sysfs", 0, 0);

	for (i = 0; i < 600; i++) {
		fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/ttyGS0", O_RDWR, 0, 0);
		if (fd >= 0)
			break;
		sleep_ms(100);
	}
	if (fd < 0) {
		for (;;)
			sleep_ms(1000);
	}
	sc(SYS_dup3, fd, 0, 0, 0, 0);
	sc(SYS_dup3, fd, 1, 0, 0, 0);
	sc(SYS_dup3, fd, 2, 0, 0, 0);

	say("\nn9ping: tty connected\n");
	wfd = sc(SYS_openat, AT_FDCWD, (long)"/dev/watchdog", O_WRONLY, 0, 0);
	say(wfd >= 0 ? "n9ping: watchdog opened\n" : "n9ping: watchdog FAILED\n");
	if (wfd >= 0 && sc(SYS_clone, 17, 0, 0, 0, 0) == 0)
		ping_loop(wfd);

	say("n9ping: exec sh\n");
	sc(SYS_execve, (long)"/bin/sh", (long)argv, (long)envp, 0, 0);
	say("n9ping: exec failed\n");
	for (;;)
		sleep_ms(1000);
}
