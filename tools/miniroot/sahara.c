/* Minimal Qualcomm Sahara image loader over usbfs (freestanding, aarch64 Linux).
 * Talks to a PBL/SBL in download mode (05c6:9008, 2 bulk endpoints: 0x81 IN, 0x01 OUT).
 * usage: sahara /dev/bus/usb/BBB/DDD <id>:<file> [<id>:<file> ...]
 * Prints every packet it receives and serves READ_DATA/READ_DATA_64 requests from the files
 * by image id (the same id:file pairs the stock `ks -s` takes).  Nothing else is written
 * to the modem; no EFS partition is touched.
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -fno-builtin -o sahara tools/miniroot/sahara.c
 */
#define SYS_openat 56
#define SYS_close 57
#define SYS_read 63
#define SYS_write 64
#define SYS_ioctl 29
#define SYS_exit 93
#define AT_FDCWD (-100)
#define USBDEVFS_CLAIMINTERFACE 0x8004550fUL
#define USBDEVFS_BULK 0xc0185502UL
#define EP_IN 0x81
#define EP_OUT 0x01
#define MAXIMG 16
#define BUFSZ (4u << 20)

typedef unsigned int u32;
typedef unsigned long long u64;

struct bulk { u32 ep, len, timeout; void *data; };

static struct { long id; const char *path; long size; } img[MAXIMG];
static int nimg;
static unsigned char fbuf[BUFSZ];
static unsigned char pkt[8192];
static long usbfd;

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

static void sayn(u64 v, int base)
{
	char b[24];
	int i = 23;

	b[i] = 0;
	do {
		b[--i] = "0123456789abcdef"[v % base];
		v /= base;
	} while (v);
	say(&b[i]);
}

static void die(const char *m, long code)
{
	say(m);
	say(" ");
	sayn(code < 0 ? -code : code, 10);
	say("\n");
	sc(SYS_exit, 1, 0, 0);
}

static long bulk(u32 ep, void *p, u32 len, u32 tmo)
{
	struct bulk b = { ep, len, tmo, p };

	return sc(SYS_ioctl, usbfd, USBDEVFS_BULK, (long)&b);
}

static void send_all(const void *p, u32 len)
{
	const unsigned char *c = p;

	while (len) {
		u32 n = len > 16384 ? 16384 : len;
		long r = bulk(EP_OUT, (void *)c, n, 5000);

		if (r < 0)
			die("bulk out failed", r);
		c += r;
		len -= r;
	}
}

static long load(int i)
{
	long fd, n, tot = 0;

	if (img[i].size >= 0)
		return img[i].size;
	fd = sc(SYS_openat, AT_FDCWD, (long)img[i].path, 0);
	if (fd < 0)
		die("cannot open image", fd);
	while ((n = sc(SYS_read, fd, (long)fbuf + tot, BUFSZ - tot)) > 0)
		tot += n;
	sc(SYS_close, fd, 0, 0);
	img[i].size = tot;
	return tot;
}

static int cur = -1;

static void serve(u64 id, u64 off, u64 len)
{
	int i;

	for (i = 0; i < nimg; i++)
		if (img[i].id == (long)id)
			break;
	if (i == nimg)
		die("device asked for an image id we do not have:", id);
	if (cur != i) {
		load(i);
		cur = i;
	}
	if (off + len > (u64)img[i].size)
		die("read beyond end of image", off + len);
	send_all(fbuf + off, len);
}

void __attribute__((naked)) _start(void)
{
	__asm__ volatile("mov x0, sp\n bl main2\n");
}

void main2(long *sp)
{
	char **argv = (char **)(sp + 1);
	long argc = sp[0], i, r;
	u32 *w = (u32 *)pkt;
	u32 ifn = 0;

	if (argc < 3)
		die("usage: sahara /dev/bus/usb/BBB/DDD id:file ...", 0);
	for (i = 2; i < argc && nimg < MAXIMG; i++) {
		char *s = argv[i];
		long id = 0;

		while (*s >= '0' && *s <= '9')
			id = id * 10 + (*s++ - '0');
		if (*s != ':')
			die("bad id:file", 0);
		img[nimg].id = id;
		img[nimg].path = s + 1;
		img[nimg].size = -1;
		nimg++;
	}
	usbfd = sc(SYS_openat, AT_FDCWD, (long)argv[1], 2);
	if (usbfd < 0)
		die("cannot open usb device node", usbfd);
	r = sc(SYS_ioctl, usbfd, USBDEVFS_CLAIMINTERFACE, (long)&ifn);
	if (r < 0)
		die("claim interface failed", r);
	say("sahara: waiting for HELLO\n");
	for (;;) {
		r = bulk(EP_IN, pkt, sizeof(pkt), 15000);
		if (r < 0)
			die("bulk in failed/timeout", r);
		if (r < 8)
			continue;
		say("rx cmd=");
		sayn(w[0], 16);
		say(" len=");
		sayn(w[1], 16);
		for (i = 2; i < (r / 4) && i < 8; i++) {
			say(" ");
			sayn(w[i], 16);
		}
		say("\n");
		switch (w[0]) {
		case 1: { /* HELLO -> HELLO_RESP, image transfer pending */
			u32 resp[12] = { 2, 0x30, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0 };

			send_all(resp, sizeof(resp));
			say("tx HELLO_RESP\n");
			break;
		}
		case 3:
			serve(w[2], w[3], w[4]);
			break;
		case 0x12:
			serve(*(u64 *)&w[2], *(u64 *)&w[4], *(u64 *)&w[6]);
			break;
		case 4: { /* END_IMAGE_TRANSFER: w[2]=image id, w[3]=status */
			u32 done[2] = { 5, 8 };

			say("END_IMAGE_TRANSFER id=");
			sayn(w[2], 10);
			say(" status=");
			sayn(w[3], 10);
			say("\n");
			if (w[3])
				die("image transfer failed, status", w[3]);
			send_all(done, sizeof(done));
			break;
		}
		case 6:
			say("DONE_RESP: ");
			sayn(w[2], 10);
			say("\nsahara: done\n");
			sc(SYS_exit, 0, 0, 0);
			break;
		default:
			say("unhandled command, stopping\n");
			sc(SYS_exit, 2, 0, 0);
		}
	}
}
