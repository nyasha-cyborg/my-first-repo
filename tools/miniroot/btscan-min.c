/* Minimal Bluetooth radio check for the flounder: bring hci0 up on a raw HCI
 * socket, run an LE scan and a classic inquiry, and log every device seen to
 * /dev/kmsg ("n9scan: ..."), so the boot record shows whether the radio
 * actually hears anything.  Freestanding aarch64, no libc.
 *
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -o btscan-min tools/miniroot/btscan-min.c
 * usage: btscan-min            (hci0; ~6 s LE scan, ~8 s inquiry)
 */
#define SYS_openat   56
#define SYS_close    57
#define SYS_read     63
#define SYS_write    64
#define SYS_ioctl    29
#define SYS_exit     93
#define SYS_socket   198
#define SYS_bind     200
#define SYS_setsockopt 208
#define SYS_recvfrom 207

#define AT_FDCWD (-100)
#define O_WRONLY 1

#define AF_BLUETOOTH 31
#define SOCK_RAW 3
#define BTPROTO_HCI 1
#define SOL_HCI 0
#define HCI_FILTER 2
#define SOL_SOCKET 1
#define SO_RCVTIMEO 20
#define HCIDEVUP 0x400448c9

static long sc(long n, long a, long b, long c, long d, long e)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b, x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d, x4 __asm__("x4") = e;

	__asm__ volatile("svc 0" : "+r"(x0)
			 : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4)
			 : "memory");
	return x0;
}

static long kmsg = -1;

/* One write = one kmsg record: build the whole line first. */
static void logf(const char *tag, long v1, long v2, const char *extra)
{
	static const char hex[] = "0123456789abcdef";
	char b[160];
	int n = 0, i;
	const char *p = "<6>n9scan: ";

	for (i = 0; p[i]; i++)
		b[n++] = p[i];
	for (i = 0; tag[i]; i++)
		b[n++] = tag[i];
	b[n++] = ' ';
	for (i = 28; i >= 0; i -= 4)
		b[n++] = hex[(v1 >> i) & 15];
	b[n++] = ' ';
	for (i = 28; i >= 0; i -= 4)
		b[n++] = hex[(v2 >> i) & 15];
	if (extra) {
		b[n++] = ' ';
		for (i = 0; extra[i] && n < 150; i++)
			b[n++] = extra[i];
	}
	b[n++] = '\n';
	if (kmsg >= 0)
		sc(SYS_write, kmsg, (long)b, n, 0, 0);
}

static void send_cmd(long s, unsigned short op, const unsigned char *par, int len)
{
	unsigned char b[64];
	int i;

	b[0] = 1;
	b[1] = op & 0xff;
	b[2] = op >> 8;
	b[3] = len;
	for (i = 0; i < len; i++)
		b[4 + i] = par[i];
	logf("write", sc(SYS_write, s, (long)b, 4 + len, 0, 0) & 0xffff, op, 0);
}

static long mon = -1;

/* Drain the HCI monitor socket (like btmon): log opcode, index and the
 * first payload bytes of every packet the kernel sent or received. */
static void drain_mon(void)
{
	unsigned char b[300];
	static const char hex[] = "0123456789abcdef";
	char h[40];
	int k, i, n;

	if (mon < 0)
		return;
	for (k = 0; k < 40; k++) {
		long r = sc(SYS_recvfrom, mon, (long)b, sizeof(b), 0x40, 0);

		if (r < 6)
			break;
		n = r - 6 > 12 ? 12 : r - 6;
		for (i = 0; i < n; i++) {
			h[i * 2] = hex[b[6 + i] >> 4];
			h[i * 2 + 1] = hex[b[6 + i] & 15];
		}
		h[n * 2] = 0;
		logf("mon", b[0] | (b[1] << 8), r - 6, h);
	}
}

/* Read events for up to `secs` seconds (1 s receive timeout per read). */
static int collect(long s, int secs, int le)
{
	unsigned char b[300];
	char mac[20];
	static const char hex[] = "0123456789abcdef";
	int seen = 0, t;

	for (t = 0; t < secs * 20; t++) {
		long r = sc(SYS_read, s, (long)b, sizeof(b), 0, 0);

		drain_mon();
		if (r < 0) {
			if (t < 3)
				logf("read-err", -r, t, 0);
			if (--secs < 0)
				break;
			continue;
		}
		if (r < 3 || b[0] != 4)
			continue;
		/* log command results / unknown events (first 16 only) */
		if (b[1] == 0x0e && r >= 7)
			logf("cmd-complete", b[5] | (b[6] << 8), b[r > 6 ? 6 : 0] ? b[7] : 0, 0);
		else if (b[1] == 0x0f && r >= 7)
			logf("cmd-status", b[4], b[5] | (b[6] << 8), 0);
		else if (!(b[1] == 0x3e && b[3] == 0x02) && b[1] != 0x02 &&
			 b[1] != 0x22 && b[1] != 0x2f)
			logf("event", b[1], r > 3 ? b[3] : 0, 0);
		if (le && b[1] == 0x3e && b[3] == 0x02) {
			/* LE advertising report: addr at b[7..12], rssi last */
			int i;

			for (i = 0; i < 6; i++) {
				mac[i * 3] = hex[b[12 - i] >> 4];
				mac[i * 3 + 1] = hex[b[12 - i] & 15];
				mac[i * 3 + 2] = i < 5 ? ':' : 0;
			}
			logf("le", b[6], (signed char)b[r - 1] & 0xff, mac);
			seen++;
		} else if (!le && (b[1] == 0x02 || b[1] == 0x22 || b[1] == 0x2f)) {
			int i;

			for (i = 0; i < 6; i++) {
				mac[i * 3] = hex[b[5 - i] >> 4];
				mac[i * 3 + 1] = hex[b[5 - i] & 15];
				mac[i * 3 + 2] = i < 5 ? ':' : 0;
			}
			logf("classic", b[1], 0, mac);
			seen++;
		}
	}
	return seen;
}

void _start(void)
{
	long s, rc;
	struct { unsigned short fam, dev, chan; } addr = { AF_BLUETOOTH, 0, 0 };
	struct { unsigned int type; unsigned int ev[2]; unsigned short op; } __attribute__((packed)) f =
		{ 0xffffffff, { 0xffffffff, 0xffffffff }, 0 };
	struct { long sec, usec; } tv = { 1, 0 };
	static const unsigned char le_par[7] = { 1, 0x10, 0, 0x10, 0, 0, 0 };
	static const unsigned char le_on[2] = { 1, 0 };
	static const unsigned char le_off[2] = { 0, 0 };
	static const unsigned char inq[5] = { 0x33, 0x8b, 0x9e, 8, 0 };
	int n;

	kmsg = sc(SYS_openat, AT_FDCWD, (long)"/dev/kmsg", O_WRONLY, 0, 0);
	{
		struct { unsigned short fam, dev, chan; } ma = { AF_BLUETOOTH, 0xffff, 2 };

		mon = sc(SYS_socket, AF_BLUETOOTH, SOCK_RAW, BTPROTO_HCI, 0, 0);
		if (mon >= 0 && sc(SYS_bind, mon, (long)&ma, sizeof(ma), 0, 0) < 0) {
			logf("mon-bind-failed", 0, 0, 0);
			mon = -1;
		}
	}
	s = sc(SYS_socket, AF_BLUETOOTH, SOCK_RAW, BTPROTO_HCI, 0, 0);
	if (s < 0) {
		logf("socket-failed", -s, 0, 0);
		sc(SYS_exit, 1, 0, 0, 0, 0);
	}
	rc = sc(SYS_ioctl, s, HCIDEVUP, 0, 0, 0);
	logf("devup", rc, 0, 0);
	drain_mon();
	rc = sc(SYS_bind, s, (long)&addr, sizeof(addr), 0, 0);
	logf("bind", rc & 0xffff, 0, 0);
	sc(SYS_setsockopt, s, SOL_HCI, HCI_FILTER, (long)&f, sizeof(f));
	sc(SYS_setsockopt, s, SOL_SOCKET, SO_RCVTIMEO, (long)&tv, sizeof(tv));

	send_cmd(s, 0x200b, le_par, 7);
	send_cmd(s, 0x200c, le_on, 2);
	n = collect(s, 6, 1);
	logf("le-total", n, 0, 0);
	send_cmd(s, 0x200c, le_off, 2);

	send_cmd(s, 0x0401, inq, 5);
	n = collect(s, 10, 0);
	logf("classic-total", n, 0, 0);
	logf("done", 0, 0, 0);
	sc(SYS_exit, 0, 0, 0, 0, 0);
	for (;;)
		;
}
