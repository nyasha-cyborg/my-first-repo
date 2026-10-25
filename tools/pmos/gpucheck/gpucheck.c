// GPU data-integrity check (GLES2 via GBM on the tegra/nouveau stack the compositor uses).
// Each iteration: upload a fresh pseudo-random CPU texture, sample it 1:1 into an FBO with a full-screen quad,
// read the pixels back and compare. Any mismatch = CPU->GPU coherency / cache / sync corruption.
// usage: gpucheck [iterations] [size] [card]   (needs LD_LIBRARY_PATH=/opt/mesa-n9/lib; run without a compositor owning
// the card is NOT required: rendering needs no DRM master)
#define EGL_NO_X11
#define MESA_EGL_NO_X11_HEADERS
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *sym(void *h, const char *n) { void *p = dlsym(h, n); if (!p) { fprintf(stderr, "no %s\n", n); exit(2); } return p; }
static uint32_t xs(uint32_t *s) { uint32_t x = *s; x ^= x << 13; x ^= x >> 17; x ^= x << 5; return *s = x; }

#define L(n) static __typeof__(n) *p_##n
L(glGenTextures); L(glBindTexture); L(glTexImage2D); L(glTexSubImage2D); L(glTexParameteri); L(glGenFramebuffers);
L(glBindFramebuffer); L(glFramebufferTexture2D); L(glViewport); L(glCreateShader); L(glShaderSource); L(glCompileShader);
L(glCreateProgram); L(glAttachShader); L(glLinkProgram); L(glUseProgram); L(glGetAttribLocation); L(glVertexAttribPointer);
L(glEnableVertexAttribArray); L(glDrawArrays); L(glReadPixels); L(glFinish); L(glGetUniformLocation); L(glUniform1i);
L(glCheckFramebufferStatus); L(glGetString); L(glActiveTexture); L(glFlush);

int main(int argc, char **argv) {
	int iters = argc > 1 ? atoi(argv[1]) : 500, N = argc > 2 ? atoi(argv[2]) : 512;
	const char *card = argc > 3 ? argv[3] : "/dev/dri/card0";
	void *gbm = dlopen("libgbm.so.1", RTLD_NOW | RTLD_GLOBAL), *egl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_GLOBAL), *gl = dlopen("libGLESv2.so.2", RTLD_NOW | RTLD_GLOBAL);
	if (!gbm || !egl || !gl) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 2; }
	void *(*gbm_create)(int) = sym(gbm, "gbm_create_device");
	PFNEGLGETPLATFORMDISPLAYEXTPROC gpd = (void *)((void *(*)(const char *))sym(egl, "eglGetProcAddress"))("eglGetPlatformDisplayEXT");
	EGLBoolean (*einit)(EGLDisplay, EGLint *, EGLint *) = sym(egl, "eglInitialize");
	EGLBoolean (*ebind)(EGLenum) = sym(egl, "eglBindAPI");
	EGLContext (*ectx)(EGLDisplay, EGLConfig, EGLContext, const EGLint *) = sym(egl, "eglCreateContext");
	EGLBoolean (*emake)(EGLDisplay, EGLSurface, EGLSurface, EGLContext) = sym(egl, "eglMakeCurrent");
	int fd = open(card, O_RDWR); if (fd < 0) { perror("open card"); return 2; }
	void *dev = gbm_create(fd);
	EGLDisplay dpy = gpd(EGL_PLATFORM_GBM_KHR, dev, NULL);
	EGLint maj, min; if (!einit(dpy, &maj, &min)) { fprintf(stderr, "eglInitialize failed\n"); return 2; }
	ebind(EGL_OPENGL_ES_API);
	EGLint ca[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
	EGLContext cx = ectx(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ca);
	if (cx == EGL_NO_CONTEXT || !emake(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, cx)) { fprintf(stderr, "no context\n"); return 2; }
#define G(n) p_##n = sym(gl, #n)
	G(glGenTextures); G(glBindTexture); G(glTexImage2D); G(glTexSubImage2D); G(glTexParameteri); G(glGenFramebuffers); G(glBindFramebuffer);
	G(glFramebufferTexture2D); G(glViewport); G(glCreateShader); G(glShaderSource); G(glCompileShader); G(glCreateProgram); G(glAttachShader);
	G(glLinkProgram); G(glUseProgram); G(glGetAttribLocation); G(glVertexAttribPointer); G(glEnableVertexAttribArray); G(glDrawArrays);
	G(glReadPixels); G(glFinish); G(glGetUniformLocation); G(glUniform1i); G(glCheckFramebufferStatus); G(glGetString); G(glActiveTexture); G(glFlush);
	printf("GL_RENDERER=%s size=%d iters=%d\n", p_glGetString(GL_RENDERER), N, iters);
	const char *vs = "attribute vec2 p; varying vec2 t; void main(){t=p*0.5+0.5; gl_Position=vec4(p,0.,1.);}";
	const char *fs = "precision highp float; varying vec2 t; uniform sampler2D s; void main(){gl_FragColor=texture2D(s,t);}";
	GLuint v = p_glCreateShader(GL_VERTEX_SHADER), f = p_glCreateShader(GL_FRAGMENT_SHADER), pr = p_glCreateProgram();
	p_glShaderSource(v, 1, &vs, 0); p_glCompileShader(v); p_glShaderSource(f, 1, &fs, 0); p_glCompileShader(f);
	p_glAttachShader(pr, v); p_glAttachShader(pr, f); p_glLinkProgram(pr); p_glUseProgram(pr);
	GLuint tex[2], fbo; p_glGenTextures(2, tex); p_glGenFramebuffers(1, &fbo);
	p_glActiveTexture(GL_TEXTURE0); p_glBindTexture(GL_TEXTURE_2D, tex[1]);
	p_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, N, N, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
	p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	p_glBindFramebuffer(GL_FRAMEBUFFER, fbo); p_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex[1], 0);
	if (p_glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) { fprintf(stderr, "fbo incomplete\n"); return 2; }
	p_glBindTexture(GL_TEXTURE_2D, tex[0]);
	p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE); p_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	p_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, N, N, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
	p_glUniform1i(p_glGetUniformLocation(pr, "s"), 0);
	static const float quad[] = {-1, -1, 1, -1, -1, 1, 1, 1};
	GLint a = p_glGetAttribLocation(pr, "p"); p_glEnableVertexAttribArray(a); p_glVertexAttribPointer(a, 2, GL_FLOAT, 0, 0, quad);
	p_glViewport(0, 0, N, N);
	uint32_t *src = malloc((size_t)N * N * 4), *dst = malloc((size_t)N * N * 4), seed = 0x1234567;
	long bad_iters = 0, bad_px = 0; int minx = N, maxx = -1, miny = N, maxy = -1;
	for (int it = 0; it < iters; it++) {
		for (size_t i = 0; i < (size_t)N * N; i++) src[i] = xs(&seed) | 0xff000000u;
		p_glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, N, N, GL_RGBA, GL_UNSIGNED_BYTE, src);
		p_glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		p_glReadPixels(0, 0, N, N, GL_RGBA, GL_UNSIGNED_BYTE, dst);
		long bad = 0;
		for (int y = 0; y < N; y++) for (int x = 0; x < N; x++) if (dst[(size_t)y * N + x] != src[(size_t)y * N + x]) {
			bad++; if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y; }
		if (bad) { bad_iters++; bad_px += bad; if (bad_iters <= 5) printf("iter %d: %ld bad pixels\n", it, bad); }
	}
	printf("RESULT bad_iterations=%ld/%d bad_pixels=%ld bbox=x[%d..%d] y[%d..%d]\n", bad_iters, iters, bad_px, minx, maxx, miny, maxy);
	return bad_iters ? 1 : 0;
}
