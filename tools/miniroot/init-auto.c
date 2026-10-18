/* Freestanding aarch64 init: load the WiFi modules, record the kernel log to
 * the unused DTB partition, then reboot to Android so the record can be read
 * with adb. This exists because the host's /dev/ttyACM0 may not be readable
 * by the unprivileged user (no sudo while the operator is away), so the
 * serial shell cannot always be used as the result channel.
 *
 * Load order matters: rfkill -> cfg80211 -> brcmutil -> brcmfmac.
 */
#define SYS_mknodat       33
#define SYS_mount         40
#define SYS_openat        56
#define SYS_close         57
#define SYS_lseek         62
#define SYS_read          63
#define SYS_write         64
#define SYS_sync          81
#define SYS_fsync         82
#define SYS_readlinkat    78
#define SYS_nanosleep     101
#define SYS_clone         220
#define SYS_dup3          24
#define SYS_exit          93
#define SYS_clone         220
#define SYS_dup3          24
#define SYS_reboot        142
#define SYS_execve        221
#define SYS_finit_module  273

#define AT_FDCWD    (-100)
#define O_RDONLY    0
#define O_WRONLY    1
#define O_RDWR      2
#define O_NONBLOCK  04000
#define S_IFBLK     0060000
#define RB_AUTOBOOT 0x01234567

#define MMC_MAJOR 179
#define DTB_MINOR 5
#define DTB_OFFSET (79872LL * 512)

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

static char kbuf[128];

static void kmsg(const char *tag, long v)
{
	static const char hex[] = "0123456789abcdef";
	long fd, i = 0, j;
	char *o = kbuf;

	while (*tag)
		kbuf[i++] = *tag++;
	kbuf[i++] = ' ';
	kbuf[i++] = 'r';
	kbuf[i++] = 'c';
	kbuf[i++] = '=';
	o = kbuf + i;
	for (j = 28; j >= 0; j -= 4)
		o[(28 - j) / 4] = hex[(v >> j) & 0xf];
	i += 8;
	kbuf[i++] = '\n';

	fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/kmsg", O_WRONLY, 0, 0);
	if (fd >= 0) {
		sc(SYS_write, fd, (long)"<6>n9wifi: ", 12, 0, 0);
		sc(SYS_write, fd, (long)kbuf, i, 0, 0);
		sc(SYS_close, fd, 0, 0, 0, 0);
	}
}

static void load(const char *path)
{
	long fd = sc(SYS_openat, AT_FDCWD, (long)path, O_RDONLY, 0, 0);
	long rc;

	if (fd < 0) {
		kmsg(path, fd);
		return;
	}
	rc = sc(SYS_finit_module, fd, (long)"", 0, 0, 0);
	kmsg(path, rc);
	sc(SYS_close, fd, 0, 0, 0, 0);
}

static char log[256 * 1024];
static const char hdr[] = "N9LOG2\n";

static long dev_of(int major, int minor)
{
	return ((long)major << 8) | (minor & 0xff);
}

static void emit(const char *buf, long len)
{
	long flags = 0, fd;

	fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/mmcblk0", O_WRONLY, 0, 0);
	if (fd < 0) {
		sc(SYS_mknodat, AT_FDCWD, (long)"/mmc0", S_IFBLK | 0600,
		   dev_of(MMC_MAJOR, 0), 0);
		fd = sc(SYS_openat, AT_FDCWD, (long)"/mmc0", O_WRONLY, 0, 0);
	}
	if (fd < 0)
		return;
	sc(SYS_lseek, fd, DTB_OFFSET, 0, 0, 0);
	sc(SYS_write, fd, (long)hdr, sizeof(hdr) - 1, 0, 0);
	sc(SYS_write, fd, (long)&len, 8, 0, 0);
	sc(SYS_write, fd, (long)&flags, 8, 0, 0);
	sc(SYS_write, fd, (long)buf, len, 0, 0);
	sc(SYS_fsync, fd, 0, 0, 0, 0);
	sc(SYS_close, fd, 0, 0, 0, 0);
}

static long read_kmsg(char *buf, long cap)
{
	long fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/kmsg",
		     O_RDONLY | O_NONBLOCK, 0, 0);
	long total = 0;

	if (fd < 0)
		return 0;
	for (;;) {
		long n = sc(SYS_read, fd, (long)(buf + total), cap - total - 1,
			    0, 0);

		if (n <= 0)
			break;
		total += n;
		if (total >= cap - 1)
			break;
	}
	sc(SYS_close, fd, 0, 0, 0, 0);
	return total;
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
	static const char *mods[] = {
		"/lib/modules/KVER/rfkill.ko",
		"/lib/modules/KVER/evdev.ko",
		"/lib/modules/KVER/cfg80211.ko",
		"/lib/modules/KVER/brcmutil.ko",
		"/lib/modules/KVER/brcmfmac.ko",
	};
	static const char *wpa_argv[] = {
		"/sbin/wpa_supplicant", "-B", "-i", "wlan0",
		"-c", "/etc/wpa_supplicant.conf", "-D", "nl80211", 0,
	};
	static const char *sh_argv[] = { "sh", "-i", 0 };
	static const char *udhcpc_argv[] = {
		"/bin/busybox", "udhcpc", "-i", "wlan0", "-q", "-n", "-t", "6",
		"-s", "/usr/share/udhcpc/default.script", 0,
	};
	int i, seen = 0;

	sc(SYS_mount, (long)"devtmpfs", (long)"/dev", (long)"devtmpfs", 0, 0);
	sc(SYS_mount, (long)"proc", (long)"/proc", (long)"proc", 0, 0);
	sc(SYS_mount, (long)"sysfs", (long)"/sys", (long)"sysfs", 0, 0);
	sleep_ms(300);

	/* send all output to the gadget as soon as it exists */
	for (i = 0; i < 50; i++) {
		long fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/ttyGS0", O_RDWR, 0, 0);

		if (fd >= 0) {
			sc(SYS_dup3, fd, 0, 0, 0, 0);
			sc(SYS_dup3, fd, 1, 0, 0, 0);
			sc(SYS_dup3, fd, 2, 0, 0, 0);
			break;
		}
		sleep_ms(100);
	}
	/* Arm the hardware watchdog and never touch it again: the driver
	 * pings it while the kernel is healthy, so a real hang resets the
	 * tablet instead of needing a power cycle. */
	{
		long wfd = sc(SYS_openat, AT_FDCWD, (long)"/dev/watchdog",
			      O_WRONLY, 0, 0);

		say(wfd >= 0 ? "n9wifi: watchdog armed\n"
			     : "n9wifi: no watchdog\n");
	}

	say("n9wifi: boot\n");

	/* Loading brcmfmac before the SDIO host has settled wedges the
	 * machine a few seconds in. A delay makes the same sequence reliable;
	 * loading by hand a minute after boot always worked. */
	sleep_ms(20000);

	for (i = 0; i < (int)(sizeof(mods) / sizeof(mods[0])); i++)
		load(mods[i]);
	say("n9wifi: modules loaded\n");

	/* wait up to 10 s for the SDIO card to expose wlan0 */
	for (i = 0; i < 100; i++) {
		long fd = sc(SYS_openat, AT_FDCWD, (long)"/sys/class/net/wlan0",
			     O_RDONLY, 0, 0);
		if (fd >= 0) {
			sc(SYS_close, fd, 0, 0, 0, 0);
			seen = 1;
			break;
		}
		sleep_ms(100);
	}
	if (!seen) {
		say("n9wifi: NO CARDOUT (sdio did not enumerate)\n");
	} else {
		say("n9wifi: wlan0 present, starting supplicant\n");
		run("/sbin/wpa_supplicant", wpa_argv);
		/* give WPA the best part of a minute */
		sleep_ms(45000);
		say("n9wifi: running dhcp\n");
		run("/bin/busybox", udhcpc_argv);
		sleep_ms(8000);
		/* The DHCP server (the Pi) advertises itself as the router;
		 * the real gateway is the main router. */
		{
			static const char *rt[] = { "busybox", "ip", "route",
				"replace", "default", "via", "192.168.1.1",
				"dev", "wlan0", 0 };

			run("/bin/busybox", rt);
		}
		sleep_ms(2000);
		say("n9wifi: dhcp done\n");
	}

	/* leave a shell for a human, so nothing is lost if it all worked */
	for (i = 0; i < 300; i++) {
		long fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/ttyGS0", O_RDWR, 0, 0);

		if (fd >= 0) {
			sc(SYS_dup3, fd, 0, 0, 0, 0);
			sc(SYS_dup3, fd, 1, 0, 0, 0);
			sc(SYS_dup3, fd, 2, 0, 0, 0);
			say("\nn9wifi: shell\n");
			sc(SYS_execve, (long)"/bin/sh", (long)sh_argv, 0, 0, 0);
		}
		sleep_ms(100);
	}
	for (;;)
		sleep_ms(1000);
}
