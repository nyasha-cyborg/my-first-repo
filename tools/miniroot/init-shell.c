/* Freestanding aarch64 init: mount the pseudo filesystems and hand the USB
 * serial gadget (g_serial, /dev/ttyGS0) to a busybox shell.
 *
 * This is the post-USB-fix interactive harness: once the tablet enumerates on
 * the host as a serial gadget, this init gives the host a shell on it, so the
 * flash-based boot record is no longer needed for day-to-day debugging.
 *
 * The gadget itself is bound by the kernel: g_serial is built in and connects
 * as soon as ci_hdrc probes (tegra124_udc forces the VBUS comparators).
 */
#define SYS_mount     40
#define SYS_openat    56
#define SYS_close     57
#define SYS_write     64
#define SYS_execve    221
#define SYS_dup3      24
#define SYS_nanosleep 101

#define AT_FDCWD (-100)
#define O_RDWR   2

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

void _start(void)
{
	static const char *envp[] = { "PATH=/bin:/sbin:/usr/bin", "HOME=/", 0 };
	static const char *argv[] = { "sh", "-i", 0 };
	long fd = -1;
	int i;

	sc(SYS_mount, (long)"devtmpfs", (long)"/dev", (long)"devtmpfs", 0, 0);
	sc(SYS_mount, (long)"proc", (long)"/proc", (long)"proc", 0, 0);
	sc(SYS_mount, (long)"sysfs", (long)"/sys", (long)"sysfs", 0, 0);

	say("n9shell: waiting for ttyGS0\n");
	for (i = 0; i < 300; i++) {
		fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/ttyGS0", O_RDWR, 0, 0);
		if (fd >= 0)
			break;
		sleep_ms(100);
	}

	if (fd < 0) {
		say("n9shell: no ttyGS0\n");
		for (;;)
			sleep_ms(1000);
	}

	sc(SYS_dup3, fd, 0, 0, 0, 0);
	sc(SYS_dup3, fd, 1, 0, 0, 0);
	sc(SYS_dup3, fd, 2, 0, 0, 0);

	say("\nn9shell: connected\n");
	sc(SYS_execve, (long)"/bin/sh", (long)argv, (long)envp, 0, 0);

	say("n9shell: exec failed\n");
	for (;;)
		sleep_ms(1000);
}
