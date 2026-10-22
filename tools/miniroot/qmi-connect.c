/* Bring up an LTE data call over QMI (freestanding, no libc).
 * usage: qmi-connect /dev/cdc-wdm0 <apn>
 * 1. sets 3GPP profile 1 (the LTE attach PDN) to <apn> / IPv4 (the unit's EFS ships Verizon profiles;
 *    RAM-only change: efsks never runs, nothing is written to EF1/EF2),
 * 2. switches the modem data format to raw IP (the 802.3 default gets no downlink; this ends any active call),
 * 3. sets the radio online, retries WDS START_NETWORK every 5 s until the modem is attached (~150 s max),
 * 4. prints shell variables: QMI_IP QMI_PREFIX QMI_GW QMI_DNS1 QMI_DNS2 QMI_MTU
 * The WDS client is never released: releasing it ends the call.  Exit 0 = call up.  Progress goes to stderr.
 * The host side must set /sys/class/net/<if>/qmi/raw_ip = Y (see tools/mdm-net.sh).
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o qmi-connect tools/miniroot/qmi-connect.c
 */
#define SYS_openat 56
#define SYS_write 64
#define SYS_read 63
#define SYS_ppoll 73
#define SYS_exit 93
#define SYS_nanosleep 101
#define AT_FDCWD (-100)

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

static long fd;
static unsigned txn;
static unsigned char tx[512], rx[4096], pl[300];
static unsigned char *body;
static long blen;

static long slen(const char *s)
{
	long n = 0;

	while (s[n])
		n++;
	return n;
}

static void out(int f, const char *s)
{
	sc(SYS_write, f, (long)s, slen(s), 0);
}

static void outn(int f, unsigned long v)
{
	char b[24];
	int i = 23;

	b[i] = 0;
	do {
		b[--i] = '0' + v % 10;
		v /= 10;
	} while (v);
	out(f, b + i);
}

static void sleep_s(long s)
{
	long ts[2] = { s, 0 };

	sc(SYS_nanosleep, (long)ts, 0, 0, 0);
}

static void die(const char *s)
{
	out(2, "qmi-connect: ");
	out(2, s);
	out(2, "\n");
	sc(SYS_exit, 1, 0, 0, 0);
}

/* one request/response; returns the QMI error code (0 = success), -1 on timeout */
static long qmi(int svc, int cid, int msg, const unsigned char *p, int plen, int secs)
{
	int h = svc ? 7 : 6, n = 0, i, tries;
	unsigned t;

	txn++;
	t = svc ? (txn & 0xffff) : (txn & 0xff);
	if (!t)
		t = txn = 1;
	tx[n++] = 1;
	n += 2;				/* length, below */
	tx[n++] = 0;
	tx[n++] = svc;
	tx[n++] = cid;
	tx[n++] = 0;			/* SDU flags: request */
	tx[n++] = t & 0xff;
	if (svc)
		tx[n++] = t >> 8;
	tx[n++] = msg & 0xff;
	tx[n++] = msg >> 8;
	tx[n++] = plen & 0xff;
	tx[n++] = plen >> 8;
	for (i = 0; i < plen; i++)
		tx[n++] = p[i];
	tx[1] = (n - 1) & 0xff;
	tx[2] = (n - 1) >> 8;
	if (sc(SYS_write, fd, (long)tx, n, 0) != n)
		return -1;
	for (tries = 0; tries < secs * 4; tries++) {
		struct { int fd; short ev, rev; } pfd = { (int)fd, 1, 0 };
		long ts[2] = { 0, 250000000 };
		long r;
		unsigned rt, rm, rl, fl;

		if (sc(SYS_ppoll, (long)&pfd, 1, (long)ts, 0) <= 0)
			continue;
		r = sc(SYS_read, fd, (long)rx, sizeof(rx), 0);
		if (r < 6 + h || rx[0] != 1 || rx[3] != 0x80 || rx[4] != svc)
			continue;
		fl = rx[6];
		if (svc) {
			rt = rx[7] | rx[8] << 8;
			rm = rx[9] | rx[10] << 8;
			rl = rx[11] | rx[12] << 8;
			if (!(fl & 2) || (fl & 4))	/* not a response / indication */
				continue;
		} else {
			rt = rx[7];
			rm = rx[8] | rx[9] << 8;
			rl = rx[10] | rx[11] << 8;
			if (!(fl & 1) || (fl & 2))
				continue;
		}
		if (rt != t || rm != (unsigned)msg || 6 + h + rl > (unsigned long)r)
			continue;
		body = rx + 6 + h;
		blen = rl;
		for (i = 0; i + 3 <= blen; i += 3 + (body[i + 1] | body[i + 2] << 8))
			if (body[i] == 2 && (body[i + 1] | body[i + 2] << 8) >= 4)
				return (body[i + 3] | body[i + 4] << 8) ? (body[i + 5] | body[i + 6] << 8) : 0;
		return 0;
	}
	return -1;
}

static unsigned char *tlv(int type, long *len)
{
	long i;

	for (i = 0; i + 3 <= blen; i += 3 + (body[i + 1] | body[i + 2] << 8))
		if (body[i] == type) {
			*len = body[i + 1] | body[i + 2] << 8;
			return body + i + 3;
		}
	return 0;
}

static int alloc(int svc)
{
	unsigned char p[4] = { 1, 1, 0, (unsigned char)svc };
	unsigned char *v;
	long l;

	if (qmi(0, 0, 0x22, p, 4, 5))
		return -1;
	v = tlv(1, &l);
	return v && l >= 2 ? v[1] : -1;
}

static void release(int svc, int cid)
{
	unsigned char p[5] = { 1, 2, 0, (unsigned char)svc, (unsigned char)cid };

	qmi(0, 0, 0x23, p, 5, 3);
}

static int apn_tlv(int at, const char *apn)
{
	int n = slen(apn), i;

	if (n > 100)
		die("APN too long");
	pl[at] = 0x14;
	pl[at + 1] = n;
	pl[at + 2] = 0;
	for (i = 0; i < n; i++)
		pl[at + 3 + i] = apn[i];
	return at + 3 + n;
}

static void ip4(const char *name, int type)
{
	unsigned char *v;
	long l;
	int i;

	out(1, name);
	out(1, "=");
	v = tlv(type, &l);
	if (v && l == 4)
		for (i = 3; i >= 0; i--) {
			outn(1, v[i]);
			if (i)
				out(1, ".");
		}
	out(1, "\n");
}

void main2(long *sp)
{
	char **argv = (char **)(sp + 1);
	int cdms, cwds, cwda, n, i;
	long e = -1, l;
	unsigned char *v;

	if (sp[0] < 3)
		die("usage: qmi-connect /dev/cdc-wdmN <apn>");
	fd = sc(SYS_openat, AT_FDCWD, (long)argv[1], 2, 0);
	if (fd < 0)
		die("cannot open the cdc-wdm node");
	cdms = alloc(2);
	cwds = alloc(1);
	cwda = alloc(0x1a);
	if (cdms < 0 || cwds < 0 || cwda < 0)
		die("QMI client allocation failed");

	/* profile 1: APN + PDP type IPv4 */
	pl[0] = 1; pl[1] = 2; pl[2] = 0; pl[3] = 0; pl[4] = 1;
	n = apn_tlv(5, argv[2]);
	pl[n++] = 0x11; pl[n++] = 1; pl[n++] = 0; pl[n++] = 0;
	e = qmi(1, cwds, 0x28, pl, n, 5);
	out(2, "qmi-connect: profile 1 apn set, error ");
	outn(2, e < 0 ? 999 : e);
	out(2, "\n");

	/* WDA data format: link layer protocol 2 = raw IP */
	pl[0] = 0x11; pl[1] = 4; pl[2] = 0; pl[3] = 2; pl[4] = 0; pl[5] = 0; pl[6] = 0;
	e = qmi(0x1a, cwda, 0x20, pl, 7, 5);
	out(2, "qmi-connect: raw IP data format, error ");
	outn(2, e < 0 ? 999 : e);
	out(2, "\n");

	/* DMS operating mode 0 = online */
	pl[0] = 1; pl[1] = 1; pl[2] = 0; pl[3] = 0;
	e = qmi(2, cdms, 0x2e, pl, 4, 5);
	out(2, "qmi-connect: radio online, error ");
	outn(2, e < 0 ? 999 : e);
	out(2, "\n");
	release(2, cdms);
	release(0x1a, cwda);

	/* start the call once the modem is attached; 0x1a = NO_EFFECT (already connected) */
	n = apn_tlv(0, argv[2]);
	pl[n++] = 0x19; pl[n++] = 1; pl[n++] = 0; pl[n++] = 4;
	for (i = 1; i <= 30; i++) {
		sleep_s(5);
		e = qmi(1, cwds, 0x20, pl, n, 20);
		if (e == 0 || e == 0x1a)
			break;
		out(2, "qmi-connect: start network try ");
		outn(2, i);
		out(2, ": error ");
		outn(2, e < 0 ? 999 : e);
		out(2, "\n");
	}
	if (e != 0 && e != 0x1a)
		die("no data call (not attached?)");

	/* runtime settings: DNS 0x10 | IP 0x100 | gateway/subnet 0x200 | MTU 0x2000 */
	pl[0] = 0x10; pl[1] = 4; pl[2] = 0; pl[3] = 0x10; pl[4] = 0x23; pl[5] = 0; pl[6] = 0;
	if (qmi(1, cwds, 0x2d, pl, 7, 5))
		die("runtime settings failed");
	ip4("QMI_IP", 0x1e);
	ip4("QMI_GW", 0x20);
	ip4("QMI_DNS1", 0x15);
	ip4("QMI_DNS2", 0x16);
	out(1, "QMI_PREFIX=");
	v = tlv(0x21, &l);
	n = 0;
	if (v && l == 4)
		for (i = 0; i < 32; i++)
			n += (v[i / 8] >> (i % 8)) & 1;
	outn(1, n ? n : 32);
	out(1, "\nQMI_MTU=");
	v = tlv(0x29, &l);
	outn(1, v && l == 4 ? (unsigned long)(v[0] | v[1] << 8 | v[2] << 16 | (unsigned long)v[3] << 24) : 1500);
	out(1, "\n");
	sc(SYS_exit, 0, 0, 0, 0);
}
