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

static void emit(const char *buf, long len, long flags)
{
	long fd;

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

/* seconds since boot, as a boot marker in the record's flags word */
static long uptime_s(void)
{
	char b[64];
	long fd, n, v = 0, i = 0;

	fd = sc(SYS_openat, AT_FDCWD, (long)"/proc/uptime", O_RDONLY, 0, 0);
	if (fd < 0)
		return 0;
	n = sc(SYS_read, fd, (long)b, sizeof(b) - 1, 0, 0);
	sc(SYS_close, fd, 0, 0, 0, 0);
	if (n <= 0)
		return 0;
	while (i < n && b[i] >= '0' && b[i] <= '9')
		v = v * 10 + (b[i++] - '0');
	return v;
}

static void monitor(void)
{
	for (;;) {
		long n;

		/* 10 s rather than 2: the frequent raw eMMC writes are the
		 * prime suspect for the stalls (heavy, always in flight). */
		sleep_ms(10000);
		n = read_kmsg(log, (long)sizeof(log));
		emit(log, n, uptime_s());
	}
}

/* Independent liveness channel: print a counter to the framebuffer console
 * every 5 s. If the USB serial dies while this keeps ticking, userspace is
 * still running and the stall is in the gadget path, not the machine. */
static void heartbeat_loop(void)
{
	static const char hex[] = "0123456789abcdef";
	long fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/tty0", O_WRONLY, 0, 0);
	long n = 0;
	char b[24];

	if (fd < 0)
		for (;;)
			sleep_ms(60000);
	for (;;) {
		/* b = "HB " + 6 hex digits + "\n" */
		long i = 0, j = 16;

		b[i++] = 'H';
		b[i++] = 'B';
		b[i++] = ' ';
		while (j >= 0) {
			b[i++] = hex[(n >> j) & 0xf];
			j -= 4;
		}
		b[i++] = '\n';
		sc(SYS_write, fd, (long)b, i, 0, 0);
		n++;
		sleep_ms(5000);
	}
}

/* Keep the armed watchdog alive from userspace. A healthy system pings every
 * 20 s; if userspace is stuck the pings stop and the hardware resets the
 * tablet after the 120 s timeout, so a stalled test recovers without a human
 * power cycle. If only the tty path is dead while userspace still runs, the
 * machine stays up - that distinction is itself useful. */
static void watchdog_ping_loop(long fd)
{
	static const char b = 0;

	for (;;) {
		sleep_ms(20000);
		/* /stop-ping: the harness asked the test to end; drop the magic
		 * keepalive so the hardware resets us back to Android. */
		if (sc(SYS_openat, AT_FDCWD, (long)"/stop-ping", O_RDONLY, 0, 0) >= 0)
			break;
		sc(SYS_write, fd, (long)&b, 1, 0, 0);
	}
	for (;;)
		sleep_ms(60000);
}

static void wifi_bringup(void)
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
	static const char *udhcpc_argv[] = {
		"/bin/busybox", "udhcpc", "-i", "wlan0", "-q", "-n", "-t", "6",
		"-s", "/usr/share/udhcpc/default.script", 0,
	};
	int i, seen = 0;

	/* Loading brcmfmac before the SDIO host has settled wedges the
	 * machine a few seconds in; a delay makes it reliable. */
	sleep_ms(20000);

	for (i = 0; i < (int)(sizeof(mods) / sizeof(mods[0])); i++)
		load(mods[i]);

	for (i = 0; i < 200; i++) {
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
		say("n9wifi: NO CARDOUT\n");
		return;
	}
	say("n9wifi: wlan0 present\n");
	/* The chip comes up with a placeholder MAC; hboot passes the real
	 * one on the kernel command line. */
	{
		static const char *mac[] = { "busybox", "sh", "-c",
			"M=$(busybox sed -n 's/.*flounder.wifimacaddr=\\([^ ]*\\).*/\\1/p' /proc/cmdline); "
			"[ -n \"$M\" ] && busybox ip link set wlan0 address $M",
			0 };

		run("/bin/busybox", mac);
	}
	run("/sbin/wpa_supplicant", wpa_argv);
	sleep_ms(45000);
	run("/bin/busybox", udhcpc_argv);
	sleep_ms(8000);
	{
		static const char *rt[] = { "busybox", "ip", "route",
			"replace", "default", "via", "192.168.1.1",
			"dev", "wlan0", 0 };

		run("/bin/busybox", rt);
	}
	say("n9wifi: done\n");
}

void _start(void)
{
	static const char *sh_argv[] = { "sh", "-i", 0 };
	long fd = -1;
	int i;

	sc(SYS_mount, (long)"devtmpfs", (long)"/dev", (long)"devtmpfs", 0, 0);
	sc(SYS_mount, (long)"proc", (long)"/proc", (long)"proc", 0, 0);
	sc(SYS_mount, (long)"sysfs", (long)"/sys", (long)"sysfs", 0, 0);
	sleep_ms(300);

	/* A rolling record so a stall leaves the last messages behind.
	 * Disabled by /etc/no-record for stall bisection. */
	if (sc(SYS_openat, AT_FDCWD, (long)"/etc/no-record", O_RDONLY, 0, 0) < 0 &&
	    sc(SYS_clone, 17, 0, 0, 0, 0) == 0)
		monitor();

	/* Optional: disable runtime PM everywhere. Suspect for the idle
	 * stalls; enabled by the presence of /etc/no-runtime-pm. */
	if (sc(SYS_openat, AT_FDCWD, (long)"/etc/no-runtime-pm", O_RDONLY,
	       0, 0) >= 0) {
		static const char *pm[] = { "busybox", "sh", "-c",
			"for f in $(busybox find /sys/devices -path '*/power/control' 2>/dev/null); do echo on > $f 2>/dev/null; done",
			0 };

		run("/bin/busybox", pm);
		say("n9wifi: runtime pm disabled\n");
	}

	/* Give the console a face as soon as the gadget exists. Wait up to 60 s:
	 * hboot has been seen to enumerate the gadget ~20 s after the kernel
	 * starts, and a 5 s window left the shell attached to tty0 with no way
	 * to tell that apart from a stall. */
	for (i = 0; i < 600; i++) {
		fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/ttyGS0", O_RDWR, 0, 0);
		if (fd >= 0)
			break;
		sleep_ms(100);
	}
	if (fd >= 0) {
		sc(SYS_dup3, fd, 0, 0, 0, 0);
		sc(SYS_dup3, fd, 1, 0, 0, 0);
		sc(SYS_dup3, fd, 2, 0, 0, 0);
	}

	/* Independent display heartbeat: proves userspace is alive even when the
	 * USB serial console has gone silent. */
	if (sc(SYS_clone, 17, 0, 0, 0, 0) == 0)
		heartbeat_loop();

	/* Arm the hardware watchdog once the console can report the result. The
	 * driver does not ping on its own; a child does, so the timeout only
	 * fires when userspace stops. */
	{
		long wfd = sc(SYS_openat, AT_FDCWD, (long)"/dev/watchdog",
			      O_WRONLY, 0, 0);

		if (wfd >= 0) {
			say("n9wifi: watchdog opened\n");
			if (sc(SYS_clone, 17, 0, 0, 0, 0) == 0)
				watchdog_ping_loop(wfd);
		} else {
			say("n9wifi: watchdog open FAILED\n");
		}
	}

	/* WiFi runs in its own process: a blocking probe must never take the
	 * console away again. */
	if (sc(SYS_openat, AT_FDCWD, (long)"/etc/no-wifi", O_RDONLY, 0, 0) < 0 &&
	    sc(SYS_clone, 17, 0, 0, 0, 0) == 0) {
		wifi_bringup();
		for (;;)
			sleep_ms(1000);
	}

	/* Optional audio stack (flag file /etc/audio). */
	if (sc(SYS_openat, AT_FDCWD, (long)"/etc/audio", O_RDONLY, 0, 0) >= 0 &&
	    sc(SYS_clone, 17, 0, 0, 0, 0) == 0) {
		static const char *top[] = {
			"tegra30-ahub", "tegra30-i2s", "rt5677",
			"rt5677-spi", "tfa989x", "tegra-machine",
		};
		static char name[32];
		int k;

		sleep_ms(25000);
		for (k = 0; k < (int)(sizeof(top) / sizeof(top[0])); k++) {
			static const char *a[4];
			int j = 0, m = 0;

			a[j++] = "busybox";
			a[j++] = "modprobe";
			while (top[k][m] && m < 28) {
				name[m] = top[k][m];
				m++;
			}
			name[m++] = '.';
			name[m++] = 'k';
			name[m++] = 'o';
			name[m] = 0;
			a[j++] = name;
			a[j] = 0;
			run("/bin/busybox", a);
		}
		say("n9audio: modules requested\n");
		for (;;)
			sleep_ms(1000);
	}

	say("\nn9wifi: shell\n");
	sc(SYS_execve, (long)"/bin/sh", (long)sh_argv, 0, 0, 0);
	say("n9wifi: exec failed\n");
	for (;;)
		sleep_ms(1000);
}
