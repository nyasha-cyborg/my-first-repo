# Plan: rebuilding the LineageOS 16 kernel with security fixes (research, 2026-10-26)

Research only. Nothing was built, flashed, or touched on the tablet. Work area:
`/tmp/n9kernelsurvey` (blobless clone of the flounder kernel, ~410 MB; throw-away).

## Plain-language summary

- The kernel on the tablet is **Linux 3.10.103**. The Linux project stopped
  fixing the 3.10 line at **3.10.108** (Nov 2017). We are **5 stable releases
  (3.10.104 to 3.10.108), 995 commits, 827 files** behind that final release.
- Good news: we do not need to start from scratch. The same GitHub repo
  (`linckandrea/android_kernel_htc_flounder`) already has branches that contain
  3.10.108 merged into the flounder tree, and one branch (`DiverOS-patches`)
  that also has the DivestOS CVE patch collection applied (as of Feb 2022).
  Those are ready-made references for how every conflict was resolved.
- A trial merge of 3.10.108 into our exact tree (`git merge-tree`, no checkout)
  gives **33 conflicting files, none in Tegra/NVIDIA code** (no `mach-tegra`,
  `drivers/video/tegra`, `nvgpu`). The conflicts are generic code where Google's
  android-3.10 branch had already cherry-picked the same fixes.
- 3.10.108 is not the end: after November 2017 there were hundreds of CVE fixes
  that never reached 3.10. The only maintained source is the **DivestOS
  `Kernel_Patches` collection** (archived Dec 2024, last list check 2024-12-07).
  Its flounder script applies about 723 patches (CVE IDs up to CVE-2024-53104).
  Expect a large share to fail or be irrelevant on this tree; budget for hand
  fixes.
- Some famous bugs are not fixed in our tree: e.g. the binder use-after-free
  CVE-2019-2215 ("Bad Binder") fix is absent (no `POLLFREE` in `binder.c`).
- Not realistically fixable: Spectre/Meltdown-class CPU mitigations for arm64
  (nothing like `array_index_nospec`/KPTI exists in this tree).
- Build with the **old AOSP GCC 4.9** (what built the current kernel), not the
  host's GCC 16 / clang 23. Result is `Image.gz-dtb`, which our existing
  `tools/bootimg-repack.py` can drop into the backed-up Lineage boot image.
  Test with `fastboot boot` first; flash only after the owner agrees.

## Facts measured

| Item | Value |
|---|---|
| Running kernel (from `boot-backup-lineage16.img`, split with `tools/bootimg-split.py`) | `Linux version 3.10.103-g5cef0dc1890 ... gcc version 4.9.x 20150123 (prerelease) ... #13 SMP PREEMPT Fri Dec 20 12:52:38 MST 2024` (the task brief said Aug 2025; the backup file is the Dec 2024 build; confirm which is flashed) |
| Source tree | `https://github.com/linckandrea/android_kernel_htc_flounder`, branch `lineage-16.0`, HEAD `5cef0dc1890` ("binder: Quiet Binder"). `git describe` base is v3.10.103 (tag merge `98c9a26ed62`, "Merge tag 'v3.10.103'") |
| Base merges in the tree | Google `android-7.1.1_r0.53` (`0ccd327b9cc`), `deprecated/android-3.10` (last merge 2020-11-04, `94ff0db65ef`) |
| Merge base with stable | `2ecaf1d025a` = "Linux 3.10.103" |
| Missing stable commits | **995** (all non-merge): 3.10.104 +17, .105 +315, .106 +252, .107 +270, .108 +141 |
| Stable tip | `e7a59c7f266` "Linux 3.10.108" = branch `linux-3.10.y` in the same repo (no tags there; canonical source is `https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git`, tags `v3.10.103` ... `v3.10.108`) |
| Diff size | 827 files, +8467 / -3882 |
| Biggest areas touched | drivers/usb (63 files), drivers/net (46), arch/x86 (33, irrelevant to us), include/linux, drivers/scsi, net/ipv4, net/ipv6, drivers/gpu (15), drivers/media (14) |
| Kernel is monolithic | `# CONFIG_MODULES is not set`, so no module ABI/vermagic problems when swapping the kernel |

### Other branches in the same repo (all fetched and compared)

| Branch | SUBLEVEL | vs `lineage-16.0` | Notes |
|---|---|---|---|
| `3.10.108` (`172ba3ccea5`) | 108 | +1170 / -11 | 3.10.108 merged (merge `7d2636f5f56`), plus gcc9 fixups, lz4 fixes, sdfat 2.4.5, state_notifier, fsync toggle, AnyKernel3. Missing 11 commits we have (below) |
| `lineage-17.1` (`0ce7b30797e`) | 108 | +1197 / -11 | same idea, LOS 17.1 flavour |
| `DiverOS-patches` (`9b806e2f64d`) | 108 | +1220 / -11 | `3.10.108` + commit `a44eb76013c` "Flounder: merge DiverOS CVE patches" (279 files, +2576/-1321, 2022-02-25) + non-security tuning |
| `linux-3.10.y` (`e7a59c7f266`) | 108 | pure stable | the merge source |
| `lineage-15.1` | 103 | +16 / -11 | older |

The 11 commits `lineage-16.0` has that `3.10.108` lacks (must be kept):
`5cef0dc1890` binder quiet, `f15abadb60d` ashmem ASHMEM_SET_SIZE race fix,
`c2aacdc6d49` `__BITS_PER_LONG` from compiler target, and the O_TMPFILE series
(`d71e244b5e5` `08741476ed1` `1acbbfce36a` `b3831dd2bd9` `76f10f8423e`
`98325a08ca7` `c471532a3d9` `b6cfbc2e6d4`). Because Lineage 16 userspace is
tuned to these, **start from `lineage-16.0`, not from `3.10.108`.**

Non-security tuning in `DiverOS-patches` we should NOT take wholesale (it
changes behaviour and heat): `-O3` on touchscreen, `vm_swappiness=100`, KSM
defaults, "drop caches on screen off", USB fastcharge / "2.0A charging v4",
`zram` hard-coded lz4, devfreq watermark governor, Makefile optimisation flags.

## Community sources of CVE patches for 3.10

1. **Divest-Mobile/Kernel_Patches** (the authoritative collection)
   `https://github.com/Divested-Mobile/Kernel_Patches` (archived, last commit 2024-12-08).
   Layout: one directory per CVE, then per kernel generation (`3.4`, `3.10`,
   `3.16`, `3.18`, `4.4`, `4.9`, `^3.18` meaning "for versions newer than...",
   `ANY`), numbered patch files. Also `0001-LinuxIncrementals/3.10/`
   (108 files, `3.10.0001-0002.patch` ... `3.10.0107-0108.patch` plus
   `download.sh`; these are stable increments against vanilla 3.10, useful only
   as a cross-check), hardening sets `0005-*`, `0006-AndroidHardening-*`,
   `0008-Graphene-*`, and `CIP.txt` / `CIP_Update.sh` (a tracker of what is still unpatched).
2. **DivestOS-Build per-device patch scripts** (the exact list for our device)
   `https://github.com/Divested-Mobile/DivestOS-Build` (archived 2024-12-18).
   Flounder script: `Scripts/LineageOS-15.1/CVE_Patchers/android_kernel_htc_flounder.sh`
   (raw: `https://raw.githubusercontent.com/Divested-Mobile/DivestOS-Build/master/Scripts/LineageOS-15.1/CVE_Patchers/android_kernel_htc_flounder.sh`;
   copy saved at `/tmp/n9kernelsurvey/divest_flounder.sh`). 763 lines, **723
   `git apply` lines** (34 commented out), ends with `editKernelLocalversion "-dos.p757"`.
   Year spread of the referenced CVE IDs (lines): 2013:8, 2014:5, 2015:22,
   2016:29, 2017:91, 2018:51, 2019:98, 2020:49, 2021:97, 2022:54, 2023:63,
   2024:169. It is only in the **15.1** script folder; 16.0 has no flounder
   script (16.0 folder holds only msm8916, msm8974, yellowstone, apq8084).
   Note it contains no Spectre/Meltdown patches and **does not apply
   CVE-2019-2215**, although `CVE-2019-2215/3.10/0011.patch` exists in the
   patch repo (it adds the `POLLFREE` wakeup in binder thread exit). Add it by hand.
   The script is flounder-specific because it was generated against the 3.10.103 tree
   (the 15.1 branch), so patch order matters; `git apply` fails whole patches
   atomically, which is how they handle non-applicable ones (just skipped).
3. **linckandrea flounder branches** (already applied once, Feb 2022)
   `DiverOS-patches` branch in `linckandrea/android_kernel_htc_flounder`
   (commit `a44eb76013c`). Applies the patch list as of early 2022 on top of
   3.10.108. Everything newer in the Divest list (roughly the 2022 to 2024 CVE
   IDs, about 280 of the 723 lines) is unapplied there.
4. **Official LineageOS 3.10.108 tree for comparison**:
   `https://github.com/LineageOS/android_kernel_samsung_apq8084` branch
   `lineage-16.0` / `lineage-17.1` (SUBLEVEL 108, last push 2021-02-03).
   Useful to see how Lineage resolved the same 3.10.y merge conflicts in
   generic code (not Tegra). Other LineageOS 3.10 trees checked
   (`android_kernel_cyanogen_msm8974`, `android_kernel_google_msm`) are 3.4.113, not helpful.
   `LineageOS/android_kernel_nvidia_shieldtablet` does not exist on GitHub under that name.
5. **Linux stable 3.10.y**: `https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git`,
   branch `linux-3.10.y`, EOL at `v3.10.108` (2017-11-04).
6. **Google android-3.10** (`deprecated/android-3.10` in
   `https://android.googlesource.com/kernel/common`): already merged (last 2020-11-04).
   Nothing newer exists.
7. **Android Hardening / GrapheneOS ports** are carried inside Kernel_Patches
   (`0005-AndroidHardening-Deny_USB`, `0006-AndroidHardening-Kernel_Hardening`,
   `0008-Graphene-Kernel_Hardening-*`).

## Recommended order of work

Work in a **separate clone/branch** (never in the pmOS `linux-flounder` tree).
Disk: the home disk is nearly full; use `/tmp` or another volume (~1.5 GB for
a full checkout plus output). Keep the original `lineage-16.0` HEAD as rollback.

### Step 0 - baseline (do first, 30 min)
- Clone: `git clone -b lineage-16.0 https://github.com/linckandrea/android_kernel_htc_flounder.git` (full history is 405k commits, ~700 MB; `--filter=blob:none` works but needs network when checking out).
- Build **unchanged** `lineage-16.0` with the chosen toolchain and boot it with
  `fastboot boot`. Compare against the running kernel (`/proc/config.gz`,
  `dmesg`, same behaviour). This proves the toolchain and packaging before any
  patch is added. Keep that `Image.gz-dtb` as the known-good test.

### Step 1 - merge Linux 3.10.y up to 3.10.108
- `git remote add stable https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git`
  (or `git fetch origin linux-3.10.y` from linckandrea's repo, same content), then
  merge the tags in order so conflicts stay small: `v3.10.104`, `v3.10.105`,
  `v3.10.106`, `v3.10.107`, `v3.10.108`. (Merge tag by tag rather than the tip:
  smaller, bisectable.)
- **Measured conflicts** with the tip (`git merge-tree --write-tree` of
  `origin/lineage-16.0` and `origin/linux-3.10.y`; 33 files):
  - arm64: `arch/arm64/include/asm/spinlock.h`, `arch/arm64/kernel/traps.c`
  - core/mm: `mm/memory.c`, `mm/mmap.c`, `include/linux/mm.h`, `kernel/cpu.c`, `include/linux/cpu.h`, `lib/genalloc.c`, `arch/x86/mm/mmap.c` (Dirty COW and mmap-limit fixes that android-3.10 had already cherry-picked; `FOLL_COW` is already present, so take ours or the stable hunk after checking they are equivalent)
  - net: `net/core/dev.c`, `net/packet/af_packet.c`, `net/ipv4/inet_connection_sock.c`, `net/ipv4/ping.c`, `net/ipv6/addrconf.c`, `net/ipv6/tcp_ipv6.c`, `include/net/if_inet6.h`, `net/wireless/scan.c`
  - fs/ACL: `fs/9p/acl.c`, `fs/ext3/acl.c`, `fs/generic_acl.c`, `fs/gfs2/acl.c`, `fs/jfs/xattr.c`, `fs/ocfs2/acl.c`, `fs/xfs/xfs_acl.c`, `fs/ext4/super.c`, `fs/pstore/ram_core.c`
  - drivers: `drivers/usb/gadget/u_ether.c`, `drivers/thermal/thermal_core.c`, `drivers/input/joystick/xpad.c`, `drivers/media/tuners/tuner-xc2028.c`, `drivers/char/Kconfig`, `crypto/blkcipher.c`
  - **None** in `arch/arm/mach-tegra`, `drivers/video/tegra`, `drivers/gpu/nvgpu`, `drivers/media/platform/tegra`, `sound/soc/tegra`. The stable range changes no Tegra-only paths, so NVIDIA-code merge risk is low. Higher-risk generic spots for our hardware: `drivers/usb/gadget/u_ether.c` and `composite.c` (USB gadget/ADB, and the LTE modem uses USB host), `drivers/thermal/thermal_core.c` (thermal throttling), `net/wireless` plus bcmdhd-adjacent `nl80211.c`, and `kernel/cpu.c` (CPU hotplug used by the Denver/A-cluster governor).
- Reference answers: `git diff origin/lineage-16.0 origin/3.10.108 -- <file>` and
  the merge `7d2636f5f56`; also `git log origin/3.10.108` for the gcc9 fixups.
- Re-add the 11 commits listed above only if a conflict resolution dropped
  them (they are in `lineage-16.0`, so a merge keeps them).
- Compile-fix needed in Tegra code after the merge (known from the 3.10.108 branch): gcc9 warnings only (`f3abf6c0e53`, `5dfa1b46651`, `a69f3e54c89`); not needed with GCC 4.9.
- Expected result: version string becomes `3.10.108-g<hash>`. Boot-test with `fastboot boot` (Wi-Fi, BT, audio jack, LTE modem on USB2, display, touch, charging, 4K H.264 decode via VDE - the owner's priority).

### Step 2 - hardening/CVE patches from Divest (after Step 1 boots)
- Clone `Kernel_Patches` shallow into `/tmp`, set `DOS_PATCHES_LINUX_CVES=<clone>`.
- Take the flounder script, **drop the incrementals and anything already in
  3.10.108 (git apply will reject them)**, and run it as a loop using
  `git apply --check` first, then `git am`-style commit per patch (message
  `Divest: CVE-xxxx (dir/file)`), logging OK / SKIP / FAIL to a table. Doing it
  one patch per commit means a bad patch can be bisected.
- Suggested wave order (stop and boot-test after each wave):
  1. Wave A, tree-wide security fixes by severity: privilege escalation in code we actually run: binder (`CVE-2019-2215/3.10/0011.patch`, add by hand, not in the flounder script), ashmem, net/packet, netfilter, USB gadget, sound, f2fs/ext4, keys, ion/kgsl-equivalent (here: nvmap / nvhost / nvgpu; no upstream patches exist for these, must port by hand from Google bulletins).
  2. Wave B, remaining CVEs in the script from 2015 to 2021.
  3. Wave C, 2022 to 2024 CVEs (the part `DiverOS-patches` lacks), skipping
     anything for features not in `lineage_flounder_defconfig` (check with
     `grep` that the file is compiled: no namespaces, no modules, no eBPF in 3.10).
  4. Wave D, the hardening set (below), last because it changes behaviour.
- Realistic expectation: of ~723 entries, many apply cleanly, many are for
  code not present in 3.10 or already fixed, and some need hand porting. Count
  results in the table and record in this note.
- Do not take the Divest `editKernelLocalversion "-dos.p757"` suffix literally; set our own `CONFIG_LOCALVERSION`.

### Step 3 - hardening (code from Kernel_Patches plus config)
Config already set in `lineage_flounder_defconfig`: `CONFIG_SECURITY_SELINUX=y`,
`SECCOMP_FILTER=y`, `SECURITY_PERF_EVENTS_RESTRICT=y`, `# DEVMEM is not set`,
`# PROC_KCORE is not set`, `# NAMESPACES is not set`.
Config to consider (verify each symbol exists in 3.10 `make menuconfig` first; many modern options do not exist here):
- `CONFIG_SECURITY_DMESG_RESTRICT=y` (currently not set), `CONFIG_KALLSYMS_ALL` off if nothing in our tooling needs it (our `kallsyms-decode` tools use the image, not the running kernel), `CONFIG_DEBUG_FS`: keep ON while debugging, since our probes use debugfs; turn off for a "release" build.
- `CONFIG_PANIC_ON_OOPS=y` (hardening vs. availability; owner's choice), `CONFIG_SLUB_DEBUG` stays.
- No kernel stack protector, no `STRICT_KERNEL_RWX`/`DEBUG_RODATA`, no `HARDENED_USERCOPY`, no KASLR, no KPTI exist in arm64 3.10. The Divest/Graphene patches add some of the slab/page hardening back:
  - `0006-AndroidHardening-Kernel_Hardening/3.10/` patches 0004 (DEVICE_SIDECHANNEL), 0007 (page sanitization), 0008 (slub sanitization), 0009 (write-after-free), 0010 (no slab merging), 0011 (freelist XOR), 0012 (random cookies), 0013 to 0017 (cache_from_obj / ksize panics). These are the same patches the flounder script applies, in order.
  - `0005-AndroidHardening-Deny_USB/3.10/0001-Alt.patch` (grsecurity DENYUSB port, adds a sysctl): useful, but **do not enable it by default**; the LTE modem and keyboard use USB and ADB needs it.
  - `0002-Misc_Fixes`, `0003-syzkaller-Misc*`, `0009-rfc4941bis`, `0010-ksm_deferred_timers` are in the script.
- Boot parameters worth testing: `slub_debug=P` (poison) via cmdline after patches; avoid `vmalloc=400M` changes without the owner (backup image cmdline already has `vmalloc=400M`, Andrea's branch removed it from the DTS, do not copy blindly).

### Step 4 - what we cannot fix (state clearly in the release notes)
- Spectre v1/v2/v4, Meltdown: no arm64 mitigations in 3.10 (the script has none). Backporting KPTI/`array_index_nospec`/branch predictor hardening is weeks of work and Denver firmware behaviour is unknown; not recommended.
- NVIDIA closed or downstream drivers (nvmap, nvhost, nvgpu, tegra-profiler, BCM Wi-Fi/Bluetooth `bcmdhd`): no one publishes CVE patches for them; any known issue has to be audited by hand. Worth a list of the world-accessible device nodes (`/dev/nvmap`, `/dev/nvhost-*`, `/dev/tegra_*`) from the Lineage rootfs. Do this with REA on the vendor libs per the project rule.
- Userspace (Android 9 / LineageOS 16) is end of life as well; kernel fixes only reduce one layer.

## Build requirements

- **Defconfig**: `lineage_flounder_defconfig` (path `arch/arm64/configs/lineage_flounder_defconfig`, 4260 lines, last regen 2017-12). `flounder_defconfig` also exists (AOSP flavour); Lineage uses the `lineage_` one. Keep the original in `configs/` of this repo for comparison. A copy of the 16.0 one was saved at `/tmp/n9kernelsurvey/lineage_flounder_defconfig`.
- Key config facts: `CONFIG_MODULES` off; `CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y` with names `tegra132-flounder-xaxb tegra132-flounder-xc tegra132-flounder-xdxepvt tegra132-flounder_lte-xaxbxcxdpvt`; `CONFIG_CMDLINE="no_console_suspend=1 tegra_wdt.enable_on_probe=1 tegra_wdt.heartbeat=120 androidboot.hardware=flounder"` with `CMDLINE_EXTEND=y`.
- **Compiler**:
  - Preferred (it built the running kernel, per the `Linux version` string): AOSP **aarch64-linux-android-4.9** GCC 4.9.x. Available as `https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9` (branches `lineage-17.1`, `lineage-18.1` checked present; `lineage-16.0` branch is NOT in that repo; 4.9 is the same binary across them) or AOSP `platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9`.
    `make ARCH=arm64 CROSS_COMPILE=<path>/bin/aarch64-linux-android- O=out lineage_flounder_defconfig && make ... -j$(nproc) Image.gz-dtb`
  - Fallback: GCC 9 (`aarch64-elf`, e.g. Proton-GCC9, as Andrea used in `compile_script_gcc9.sh`). Needs the three gcc9 fix commits from the `3.10.108` branch (`f3abf6c0e53`, `5dfa1b46651`, `a69f3e54c89`; they only touch warnings/casts).
  - Not usable as-is: host **GCC 16.2.1 / clang 23.1.3** (CachyOS has no aarch64 cross-GCC installed either). `compiler-gcc.h` in 3.10 stops at gcc4.x-era feature gates and newer compilers hit many new errors. The pmOS tree builds with clang because it is mainline-ish; this downstream tree is not.
  - **Host tool quirks** (host `gcc` builds `scripts/`): `scripts/dtc` defines `YYLTYPE yylloc;` in `dtc-lexer.l`, `dtc-lexer.lex.c_shipped`, and `dtc-parser.tab.c_shipped` => "multiple definition of yylloc" with host GCC 10+ (default `-fno-common`). Use `make HOSTCFLAGS=-fcommon` or patch the shipped files. `kernel/timeconst.bc` requires `bc` on the host. Run with `python2`-free Perl; no other known blockers. Using a container with an old Debian/Ubuntu (gcc 7-9 host) is the lowest-effort alternative.
- **Boot image assembly** (confirmed by splitting `boot-backup-lineage16.img` with `tools/bootimg-split.py`):
  - Legacy header, page size 2048, kernel size 7,265,953, ramdisk 1,743,554, `second` 0.
  - The Lineage backup has **no 256-byte HTC wrapper** (header at offset 0); the stock HTC images do. Cmdline in header: `no_console_suspend=1 tegra_wdt.enable_on_probe=1 tegra_wdt.heartbeat=120 vmalloc=400M androidboot.hardware=flounder buildvariant=userdebug`.
  - Kernel region = `gzip(Image)` followed by 4 DTBs (FDT magic `d00dfeed` x4; measured: 16,679,928 bytes raw Image, 433,384 bytes of DTBs). This is exactly what the build's `arch/arm64/boot/Image.gz-dtb` is. hboot finds the DTB by scanning the kernel region (see `notes/evidence.md`, "The bootloader's DTB gate").
- **Reuse of our tools** (read both files):
  - `tools/bootimg-split.py <boot.img> <outdir>`: gives `kernel`, `ramdisk`, cmdline and SHA-256s; use it to diff the new image against `boot-backup-lineage16.img`.
  - `tools/bootimg-repack.py --stock <boot.img> --image <kernel> [--dtb ...] [--append-cmdline ...] [--ramdisk ...] -o out.img`: keeps the stock header verbatim and replaces only the kernel region (and optionally the ramdisk). Passing `Image.gz-dtb` as `--image` works without `--dtb`: it detects the gzip magic and uses the file as-is ("kernel input is already gzip-compressed"), and the DTBs are already inside. With a plain `Image` plus `--dtb` files it gzips and appends them itself. It prints a warning when the wrapper is absent but then proceeds (right for the Lineage backup). It re-parses the output and checks DTB bytes survive.
  - Suggested command (not run):
    `python3 -I tools/bootimg-repack.py --stock ~/Downloads/nexus9/boot-backup-lineage16.img --image out/arch/arm64/boot/Image.gz-dtb -o /tmp/boot-lineage16-3.10.108.img`
    then `python3 -I tools/bootimg-split.py` on the result, check the ramdisk SHA-256 equals the original (`ffbfe771...`), and only then `fastboot boot` it. Total must stay below the 32 MiB `LNX` partition.
  - A modern `mkbootimg` (host has `/usr/bin/mkbootimg`) would produce the new header layout; the existing tool avoids that on purpose (see `README.md`). For a Lineage boot image without the HTC wrapper either works in principle, but keep using the repack tool for consistency.
- Rollback: `boot-backup-lineage16.img` (sha256 `b26351cb...` per `notes/flash-plan.md`).

## Risks (ranked)

1. **Regressions from a big merge on a monolithic, vendor-tuned kernel**: 995
   stable commits plus hundreds of CVE patches in USB gadget, thermal, CPU hotplug,
   mm and net; any one can break LTE (USB2 modem), Wi-Fi/BT, charging or the VDE
   video path. Mitigation: build and boot the unchanged tree first, then tag-by-tag
   merges, then waves of patches, `fastboot boot` after each wave, one commit per
   CVE patch for bisecting.
2. **Patch applicability and silent semantic mismatch**: many Divest patches are
   written for 3.4/3.18/4.4 and applied with `git apply` fuzz on 3.10; a patch
   that applies can still be wrong. The script is also from the 15.1 tree and
   misses some famous bugs (CVE-2019-2215). Mitigation: prefer `3.10/` directories,
   review each hunk of 4.4-origin patches, add binder fix by hand, keep a table of
   applied/skipped.
3. **Toolchain and host drift**: GCC 4.9 prebuilts are old x86-64 binaries, and
   host tools (dtc `yylloc`, Perl/bc, GCC 16) fail on new distros; a changed
   compiler can alter timing-sensitive Tegra code (GCC 9 changes seen in the
   3.10.108 branch). Mitigation: use the same GCC 4.9, build in an old-distro container if needed, and compare
   against the unchanged baseline build first.
4. (Lower) Tuning commits in `DiverOS-patches` look like security work but are
   not; copying that branch wholesale also removes the `vmalloc` bootarg and
   adds `-O3`. And the hardware-level gaps (Spectre/Meltdown, NVIDIA drivers)
   stay unfixed.

## Open items / dead ends

- Not done: no test build, no patch dry-run (the clone is blobless and the home
  disk is nearly full). First action when building: dry-run the Divest script
  with `git apply --check` into a results table and add it to this note.
- Confirm which kernel build is flashed (Dec 2024 `#13` in the backup vs Aug 2025
  reported by the owner) with `uname -a`/`/proc/version` before comparing sizes.
- `LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9`
  has no `lineage-16.0` branch (checked via API); use `lineage-17.1`.
- Dead end: official LineageOS tegra 3.10 tree for the Shield tablet (not on GitHub); `cyanogen_msm8974` and `google_msm` are 3.4.
- Per project rule: before any kernel-side test of vendor behaviour, pull the
  vendor blobs and run REA (not needed for this plan, which is source-only).
