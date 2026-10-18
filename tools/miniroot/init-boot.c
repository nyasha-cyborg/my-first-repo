/* Freestanding aarch64 init for installed boot.
 *
 * Mainline cannot see this tablet's partitions (the GPT is not at LBA1), so
 * the root filesystem is kept as a raw ext4 image at a known byte offset of
 * the eMMC and loop-mounted here.
 *
 * Command line: n9.root_offset=<bytes> [n9.root_size=<bytes>]
 *
 * The image is built on the host with:
 *   dd if=/dev/zero of=n9root.ext4 bs=1M count=256
 *   mke2fs -t ext4 -d rootdir n9root.ext4
 * and written to the chosen partition with fastboot.
 *
 * Flow: mount devtmpfs/proc/sys, loop-mount the image, switch_root into it.
 * Everything is delegated to busybox (losetup, mount, switch_root); this
 * program only parses the command line and sequences the calls.
 */
#define SYS_openat    56
#define SYS_read      63
#define SYS_write     64
#define SYS_close     57
#define SYS_mount     40
#define SYS_clone     220
#define SYS_execve    221
#define SYS_exit      93
#define SYS_nanosleep 101

#define AT_FDCWD (-100)
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

static char cmdline[4096];

/* find n9.KEY=<value> in the kernel command line; returns the value */
static char *param(const char *key)
{
	char *p = cmdline;
	int klen = 0;

	while (key[klen])
		klen++;
	while (*p) {
		int i = 0;

		if ((p == cmdline || p[-1] == ' ') &&
		    p[0] == 'n' && p[1] == '9' && p[2] == '.') {
			while (i < klen && p[3 + i] && p[3 + i] == key[i])
				i++;
			if (i == klen && p[3 + klen] == '=') {
				char *v = p + 3 + klen + 1;
				char *e = v;

				while (*e && *e != ' ')
					e++;
				*e = 0;
				return v;
			}
		}
		while (*p && *p != ' ')
			p++;
		while (*p == ' ')
			p++;
	}
	return 0;
}

static void run(const char *path, const char *const *argv)
{
	long pid = sc(SYS_clone, 17, 0, 0, 0, 0);

	if (pid == 0) {
		sc(SYS_execve, (long)path, (long)argv, 0, 0, 0);
		sc(SYS_exit, 127, 0, 0, 0, 0);
	}
}

void _start(void)
{
	static const char *losetup_argv[] = {
		"busybox", "losetup", "-o", 0 /* filled */, "/dev/loop0",
		"/dev/mmcblk0", 0,
	};
	static const char *mount_argv[] = {
		"busybox", "mount", "-t", "ext4", "/dev/loop0", "/newroot", 0,
	};
	static const char *switch_argv[] = {
		"busybox", "switch_root", "/newroot", "/sbin/init", 0,
	};
	char *off;
	long fd, n;
	int tries;

	sc(SYS_mount, (long)"devtmpfs", (long)"/dev", (long)"devtmpfs", 0, 0);
	sc(SYS_mount, (long)"proc", (long)"/proc", (long)"proc", 0, 0);
	sc(SYS_mount, (long)"sysfs", (long)"/sys", (long)"sysfs", 0, 0);
	sleep_ms(200);

	fd = sc(SYS_openat, AT_FDCWD, (long)"/proc/cmdline", O_RDONLY, 0, 0);
	if (fd < 0) {
		say("n9boot: no cmdline\n");
		for (;;)
			sleep_ms(1000);
	}
	n = sc(SYS_read, fd, (long)cmdline, sizeof(cmdline) - 1, 0, 0);
	sc(SYS_close, fd, 0, 0, 0, 0);
	if (n <= 0)
		cmdline[0] = 0;
	else
		cmdline[n] = 0;

	off = param("root_offset");
	if (!off) {
		say("n9boot: n9.root_offset missing\n");
		for (;;)
			sleep_ms(1000);
	}
	losetup_argv[3] = off;
	say("n9boot: loop-mounting the root image\n");

	/* wait for the disk, then loop-setup and mount */
	for (tries = 0; tries < 50; tries++) {
		fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/mmcblk0", O_RDONLY,
			0, 0);
		if (fd >= 0) {
			sc(SYS_close, fd, 0, 0, 0, 0);
			break;
		}
		sleep_ms(100);
	}
	run("/bin/busybox", losetup_argv);
	sleep_ms(500);
	run("/bin/busybox", mount_argv);
	sleep_ms(1500);

	/* /newroot/sbin/init exists? if not, say so and stay put */
	fd = sc(SYS_openat, AT_FDCWD, (long)"/newroot/sbin/init", O_RDONLY, 0, 0);
	if (fd < 0) {
		say("n9boot: root mount failed\n");
		for (;;)
			sleep_ms(1000);
	}
	sc(SYS_close, fd, 0, 0, 0, 0);
	run("/bin/busybox", switch_argv);
	say("n9boot: switch_root failed\n");
	for (;;)
		sleep_ms(1000);
}
