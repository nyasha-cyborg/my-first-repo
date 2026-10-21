/* Play a short sine tone on an ALSA PCM playback device. Freestanding
 * aarch64 (no libc, no alsa-lib): drives the kernel PCM ioctls directly.
 *
 * usage: tone-min <card> <device> [seconds=2] [freq=440] [amp-percent=10] [rate=48000]
 *   e.g. tone-min 0 0         (card 0 = the "speakers" card)
 * S16_LE, 2 channels, 48 kHz unless a rate is given.  Amplitude is a % of full scale; keep it low.
 * build: clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld \
 *              -fno-stack-protector -I<dir with empty stdlib.h> -idirafter /usr/include \
 *              -o tone-min tools/miniroot/tone-min.c
 */
#include <linux/types.h>
#include <linux/ioctl.h>
#include <sound/asound.h>

#define SYS_openat 56
#define SYS_close 57
#define SYS_write 64
#define SYS_ioctl 29
#define SYS_exit 93
#define AT_FDCWD (-100)
#define O_RDWR 2

/* the compiler turns the zeroing loops into memset/memcpy calls */
void *memset(void *d, int c, unsigned long n)
{
	volatile unsigned char *p = d;

	while (n--)
		*p++ = c;
	return d;
}

static long sc(long n, long a, long b, long c, long d, long e)
{
	register long x8 __asm__("x8") = n, x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b, x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d, x4 __asm__("x4") = e;

	__asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4) : "memory");
	return x0;
}

static void say(const char *s, long v)
{
	char b[96];
	int n = 0, i;
	static const char hx[] = "0123456789abcdef";

	for (i = 0; s[i] && n < 60; i++)
		b[n++] = s[i];
	b[n++] = ' ';
	for (i = 28; i >= 0; i -= 4)
		b[n++] = hx[(v >> i) & 15];
	b[n++] = '\n';
	sc(SYS_write, 1, (long)b, n, 0, 0);
}

static long num(const char *s, long def)
{
	long v = 0;

	if (!s)
		return def;
	for (; *s >= '0' && *s <= '9'; s++)
		v = v * 10 + (*s - '0');
	return v;
}

static void mask_set(struct snd_mask *m, unsigned int bit)
{
	unsigned int i;

	for (i = 0; i < 8; i++)
		m->bits[i] = 0;
	m->bits[bit >> 5] = 1u << (bit & 31);
}

static void ival(struct snd_interval *iv, unsigned int v)
{
	iv->min = iv->max = v;
	iv->openmin = iv->openmax = 0;
	iv->integer = 1;
}

/* triangle-ish sine approximation, no libm: 9-point table, linear interp. */
static int wave(unsigned int phase /* 0..4095 */)
{
	static const short t[17] = { 0, 12540, 23170, 30274, 32767, 30274, 23170, 12540, 0,
				     -12540, -23170, -30274, -32767, -30274, -23170, -12540, 0 };
	unsigned int i = phase >> 8, f = phase & 255;

	return t[i] + (((t[i + 1] - t[i]) * (int)f) >> 8);
}

void c_main(long *sp)
{
	char **argv = (char **)(sp + 1);
	int argc = sp[0];
	char path[] = "/dev/snd/pcmC0D0p";
	struct snd_pcm_hw_params hw;
	struct snd_pcm_sw_params swp;
	struct snd_xferi xf;
	static short buf[1024 * 2];
	long fd, rc, secs, freq, amp, rate;
	unsigned int i, phase = 0, total, written = 0;
	unsigned char *p;

	if (argc < 3)
		sc(SYS_exit, 2, 0, 0, 0, 0);
	path[13] = argv[1][0];
	path[15] = argv[2][0];
	secs = num(argc > 3 ? argv[3] : 0, 2);
	freq = num(argc > 4 ? argv[4] : 0, 440);
	amp = num(argc > 5 ? argv[5] : 0, 10);
	rate = num(argc > 6 ? argv[6] : 0, 48000);

	fd = sc(SYS_openat, AT_FDCWD, (long)path, O_RDWR, 0, 0);
	say("open", fd);
	if (fd < 0)
		sc(SYS_exit, 3, 0, 0, 0, 0);

	/* "any": all mask bits set, full intervals */
	p = (unsigned char *)&hw;
	for (i = 0; i < sizeof(hw); i++)
		p[i] = 0;
	for (i = 0; i < 3; i++)
		for (rc = 0; rc < 8; rc++)
			hw.masks[i].bits[rc] = ~0u;
	for (i = 0; i < SNDRV_PCM_HW_PARAM_LAST_INTERVAL - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL + 1; i++) {
		hw.intervals[i].min = 0;
		hw.intervals[i].max = ~0u;
	}
	hw.rmask = ~0u;
	rc = sc(SYS_ioctl, fd, SNDRV_PCM_IOCTL_HW_REFINE, (long)&hw, 0, 0);
	say("hw_refine", rc);

	mask_set(&hw.masks[SNDRV_PCM_HW_PARAM_ACCESS], SNDRV_PCM_ACCESS_RW_INTERLEAVED);
	mask_set(&hw.masks[SNDRV_PCM_HW_PARAM_FORMAT], SNDRV_PCM_FORMAT_S16_LE);
	mask_set(&hw.masks[SNDRV_PCM_HW_PARAM_SUBFORMAT], SNDRV_PCM_SUBFORMAT_STD);
	ival(&hw.intervals[SNDRV_PCM_HW_PARAM_CHANNELS - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL], 2);
	ival(&hw.intervals[SNDRV_PCM_HW_PARAM_RATE - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL], rate);
	ival(&hw.intervals[SNDRV_PCM_HW_PARAM_PERIOD_SIZE - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL], 1024);
	ival(&hw.intervals[SNDRV_PCM_HW_PARAM_PERIODS - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL], 4);
	hw.rmask = ~0u;
	rc = sc(SYS_ioctl, fd, SNDRV_PCM_IOCTL_HW_PARAMS, (long)&hw, 0, 0);
	say("hw_params", rc);
	if (rc < 0)
		sc(SYS_exit, 4, 0, 0, 0, 0);

	p = (unsigned char *)&swp;
	for (i = 0; i < sizeof(swp); i++)
		p[i] = 0;
	swp.tstamp_mode = SNDRV_PCM_TSTAMP_NONE;
	swp.period_step = 1;
	swp.avail_min = 1024;
	swp.start_threshold = 2048;
	swp.stop_threshold = 4096;
	swp.boundary = 4096UL * 1024;
	rc = sc(SYS_ioctl, fd, SNDRV_PCM_IOCTL_SW_PARAMS, (long)&swp, 0, 0);
	say("sw_params", rc);
	rc = sc(SYS_ioctl, fd, SNDRV_PCM_IOCTL_PREPARE, 0, 0, 0);
	say("prepare", rc);

	total = secs * rate;
	while (written < total) {
		for (i = 0; i < 1024; i++) {
			int s = (wave(phase >> 8 & 4095) * (int)amp) / 100;

			buf[i * 2] = buf[i * 2 + 1] = s;
			phase += (unsigned int)((long)freq * 4096 * 256 / rate);
		}
		xf.buf = buf;
		xf.frames = 1024;
		xf.result = 0;
		rc = sc(SYS_ioctl, fd, SNDRV_PCM_IOCTL_WRITEI_FRAMES, (long)&xf, 0, 0);
		if (rc < 0) {
			say("write-failed", rc);
			break;
		}
		written += 1024;
	}
	say("written-frames", written);
	rc = sc(SYS_ioctl, fd, SNDRV_PCM_IOCTL_DRAIN, 0, 0, 0);
	say("drain", rc);
	sc(SYS_exit, 0, 0, 0, 0, 0);
}

__attribute__((naked)) void _start(void)
{
	__asm__("mov x0, sp\n\tbl c_main\n");
}
