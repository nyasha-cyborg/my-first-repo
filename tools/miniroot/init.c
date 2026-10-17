/* Freestanding aarch64 init: wait for probing, dump /dev/kmsg into the unused
 * DTB partition (mmcblk0p5), flush, reboot into the bootloader.
 *
 * Three things went wrong in earlier versions, all fixed here.
 *
 * 1. It relied on devtmpfs to publish the block node. If devtmpfs never gets
 *    mounted, that path simply does not exist and the write silently does
 *    nothing. This version mknodat()s the node itself from the major/minor
 *    the kernel assigned (mmcblk = 179, p5 = minor 5). Same trick for
 *    /dev/kmsg (char 1:11).
 *
 * 2. It called reboot() immediately after write(). Writes to a block device
 *    are buffered; RB_AUTOBOOT does not flush them, so the pages were dropped
 *    and the partition stayed zeros. It now fsync()s after every record and
 *    sync()s before rebooting.
 *
 * 3. Nothing distinguished "init never ran" from "init ran and the write
 *    failed". The record is now written at every stage, each overwriting the
 *    last, so whatever survives is the furthest point reached.
 *
 * Record, all little-endian:
 *
 *     "N9LOG2\n"
 *     u64 length of the log that follows
 *     u64 flags
 *     log bytes
 *
 * flags bits:
 *     0x001  kmsg opened
 *     0x002  block node opened
 *     0x004  block node had to be mknod'ed rather than found in /dev
 *     0x008  written to the raw disk at the DTB offset, no partition node
 *     0x100  init started          0x200  devtmpfs mount attempted
 *     0x400  sleep finished        0x800  kmsg read finished
 *
 * An all-zero partition means this init never ran at all.
 */
#define SYS_mknodat   33
#define SYS_mount     40
#define SYS_openat    56
#define SYS_close     57
#define SYS_lseek     62
#define SYS_read      63
#define SYS_write     64
#define SYS_sync      81
#define SYS_fsync     82
#define SYS_exit      93
#define SYS_nanosleep 101
#define SYS_reboot    142

#define AT_FDCWD    (-100)
#define O_RDONLY    0
#define O_WRONLY    1
#define O_NONBLOCK  04000
#define S_IFBLK     0060000
#define S_IFCHR     0020000
#define RB_AUTOBOOT 0x01234567
#define RB_RESTART2 0xa1b2c3d4

#define MMC_MAJOR 179
#define DTB_MINOR 5

/* sector 79872 on this device, from /sys/class/block/mmcblk0p5/start */
#define DTB_OFFSET (79872LL * 512)

#define F_KMSG    0x001
#define F_BLK     0x002
#define F_MKNOD   0x004
#define F_RAW     0x008
#define F_START   0x100
#define F_MOUNTED 0x200
#define F_SLEPT   0x400
#define F_READ    0x800

static long sc(long n, long a, long b, long c, long d, long e)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b;
	register long x2 __asm__("x2") = c, x3 __asm__("x3") = d, x4 __asm__("x4") = e;
	__asm__ volatile("svc 0" : "+r"(x0)
			 : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4) : "memory");
	return x0;
}

static char log[768 * 1024];
static const char hdr[] = "N9LOG2\n";

/* old-style dev_t: (major << 8) | minor, which is what mknodat wants here */
static long dev_of(int major, int minor)
{
	return ((long)major << 8) | (minor & 0xff);
}

static void sleep_s(long sec)
{
	struct { long s, ns; } ts = { sec, 0 };
	sc(SYS_nanosleep, (long)&ts, 0, 0, 0, 0);
}

/* Write the record at the current file position of fd. */
static void put(long fd, long flags, const char *buf, long len)
{
	sc(SYS_write, fd, (long)hdr, sizeof(hdr) - 1, 0, 0);
	sc(SYS_write, fd, (long)&len, 8, 0, 0);
	sc(SYS_write, fd, (long)&flags, 8, 0, 0);
	if (len > 0)
		sc(SYS_write, fd, (long)buf, len, 0, 0);
	sc(SYS_fsync, fd, 0, 0, 0, 0);
	sc(SYS_close, fd, 0, 0, 0, 0);
}

/* Write one record into the DTB partition. Always from its start, so the
 * newest record wins.
 *
 * Three ways in, tried in order, because we do not yet know which the kernel
 * supports:
 *
 *   1. /dev/mmcblk0p5 -- needs devtmpfs plus a parsed partition table
 *   2. mknod 179:5    -- needs the partition table but not devtmpfs
 *   3. /dev/mmcblk0 at byte offset DTB_OFFSET -- needs neither. This tablet's
 *      real partition table lives inside a partition called GPT; Android has
 *      a bespoke parser for it and mainline does not, so the partitions may be
 *      invisible even though the disk works. Same bytes either way.
 */
static long emit(long flags, const char *buf, long len)
{
	long fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/mmcblk0p5", O_WRONLY, 0, 0);

	if (fd < 0) {
		sc(SYS_mknodat, AT_FDCWD, (long)"/dtb", S_IFBLK | 0600,
		   dev_of(MMC_MAJOR, DTB_MINOR), 0);
		fd = sc(SYS_openat, AT_FDCWD, (long)"/dtb", O_WRONLY, 0, 0);
		flags |= F_MKNOD;
	}
	if (fd >= 0) {
		flags |= F_BLK;
		put(fd, flags, buf, len);
		return 1;
	}

	fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/mmcblk0", O_WRONLY, 0, 0);
	if (fd < 0) {
		sc(SYS_mknodat, AT_FDCWD, (long)"/mmc0", S_IFBLK | 0600,
		   dev_of(MMC_MAJOR, 0), 0);
		fd = sc(SYS_openat, AT_FDCWD, (long)"/mmc0", O_WRONLY, 0, 0);
		flags |= F_MKNOD;
	}
	if (fd < 0)
		return 0;
	if (sc(SYS_lseek, fd, DTB_OFFSET, 0, 0, 0) >= 0) {
		flags |= F_RAW;
		put(fd, flags, buf, len);
		return 1;
	}
	sc(SYS_close, fd, 0, 0, 0, 0);
	return 0;
}

void _start(void)
{
	long fd, n, total = 0, flags = F_START;

	emit(flags, log, 0);

	/* devtmpfs is normally auto-mounted; ask for it anyway, ignoring failure */
	sc(SYS_mount, (long)"devtmpfs", (long)"/dev", (long)"devtmpfs", 0, 0);
	sc(SYS_mount, (long)"proc", (long)"/proc", (long)"proc", 0, 0);
	flags |= F_MOUNTED;
	emit(flags, log, 0);

	/* 90 s: deferred probes can take ~60 s, and the panel needs time after */
	sleep_s(90);
	flags |= F_SLEPT;

	fd = sc(SYS_openat, AT_FDCWD, (long)"/dev/kmsg", O_RDONLY | O_NONBLOCK, 0, 0);
	if (fd < 0) {
		sc(SYS_mknodat, AT_FDCWD, (long)"/kmsg", S_IFCHR | 0600,
		   dev_of(1, 11), 0);
		fd = sc(SYS_openat, AT_FDCWD, (long)"/kmsg", O_RDONLY | O_NONBLOCK, 0, 0);
	}
	if (fd >= 0) {
		flags |= F_KMSG;
		while (total < (long)sizeof(log) - 8192) {
			n = sc(SYS_read, fd, (long)(log + total),
			       sizeof(log) - total - 1, 0, 0);
			if (n <= 0)
				break;
			total += n;
		}
		sc(SYS_close, fd, 0, 0, 0, 0);
	}
	flags |= F_READ;
	if (emit(flags, log, total))
		flags |= F_BLK;

	/*
	 * Paint the DRM framebuffer solid white. If the DSI video stream is
	 * working but nothing has drawn into the buffer yet, this is the
	 * difference between a black panel and a white one -- and it settles
	 * whether the display path is alive without needing a console.
	 */
	{
		static unsigned char white[65536];
		long fb = sc(SYS_openat, AT_FDCWD, (long)"/dev/fb0", O_WRONLY, 0, 0);
		int i;

		if (fb < 0) {
			sc(SYS_mknodat, AT_FDCWD, (long)"/fb0", S_IFCHR | 0600,
			   dev_of(29, 0), 0);
			fb = sc(SYS_openat, AT_FDCWD, (long)"/fb0", O_WRONLY, 0, 0);
		}
		if (fb >= 0) {
			for (i = 0; i < (int)sizeof(white); i++)
				white[i] = 0xff;
			for (i = 0; i < 256; i++)
				sc(SYS_write, fb, (long)white, sizeof(white), 0, 0);
			sc(SYS_fsync, fb, 0, 0, 0, 0);
			sc(SYS_close, fb, 0, 0, 0, 0);
		}
	}

	sc(SYS_sync, 0, 0, 0, 0, 0);
	sleep_s(10);

#ifdef PROBE
	/* Build with -DPROBE to answer one question with no log to read:
	 * did this init run, and did it find the eMMC?
	 *
	 *   eMMC found      -> reboot instantly, so the boot logo strobes
	 *   eMMC missing    -> sit still for 120 s, then reboot
	 *   init never ran  -> whatever the kernel does on its own
	 *
	 * So a fast-flickering logo means both are true, a logo that comes back
	 * after two minutes means init runs but the eMMC is not there, and a
	 * logo that comes back after ~20 s means this code never executed. */
	if (flags & F_BLK) {
		for (;;)
			sc(SYS_reboot, 0xfee1dead, 672274793, RB_AUTOBOOT, 0, 0);
	}
	sleep_s(120);
	for (;;)
		sc(SYS_reboot, 0xfee1dead, 672274793, RB_AUTOBOOT, 0, 0);
#endif

	/* Ask for the bootloader rather than a plain reboot. tegra-pmc's reboot
	 * notifier turns the string into PMC_SCRATCH0 bit 30, which hboot reads
	 * and uses to enter fastboot -- so the device comes back to us on its
	 * own instead of rebooting into this kernel forever. If the handler is
	 * not there, the syscall returns and the plain reboot runs instead. */
	sc(SYS_reboot, 0xfee1dead, 672274793, RB_RESTART2, (long)"bootloader", 0);
	sc(SYS_reboot, 0xfee1dead, 672274793, RB_AUTOBOOT, 0, 0);
	for (;;)
		sc(SYS_exit, 0, 0, 0, 0, 0);
}
