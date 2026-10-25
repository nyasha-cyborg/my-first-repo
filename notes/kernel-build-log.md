# Kernel build log: LineageOS 16 kernel, baseline and 3.10.108 merge (2026-10-26)

Spec: `notes/kernel-security-plan.md` (Step 0 and Step 1). Tablet not touched.

## Plain summary

- We can now build the tablet's kernel ourselves with the original compiler
  (GCC 4.9). The unchanged build packs into a boot image that differs from
  the shipped one only in the build timestamp (same 4 device trees, byte for byte).
- The same kernel with all Linux stable updates up to 3.10.108 also builds.
  It is in `~/n9kernel/out/boot-3.10.108.img`. **It has not been booted yet.**
  Next: `fastboot boot` the baseline first, then the 3.10.108 image.
- Nothing committed in this repo; the kernel branch `n9-3.10.108` lives only
  in `~/n9kernel/kernel` (local, per the "kernel tree stays local" rule).

## Setup

| Item | Value |
|---|---|
| Work dir | `~/n9kernel` (5.8 GB incl. two build dirs; home disk 13 GB free after) |
| Source | `~/n9kernel/kernel`, blobless clone of `linckandrea/android_kernel_htc_flounder` `lineage-16.0` (HEAD `5cef0dc1890`), plus `origin/linux-3.10.y` (`e7a59c7f266`) and `origin/3.10.108` fetched |
| Toolchain | `~/n9kernel/gcc49` (LineageOS `android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9`, `lineage-17.1`, depth 1) |
| Build command | `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- O=<builddir> HOSTCFLAGS=-fcommon lineage_flounder_defconfig` then `... -j$(nproc) Image.gz-dtb` (PATH includes `gcc49/bin`) |
| Build dirs | `~/n9kernel/build-base`, `~/n9kernel/build-108`; logs `~/n9kernel/out/build-*.log` (~270 warnings each, no errors) |
| Stock boot.img | `~/n9kernel/rom/boot.img` from `lineage-16.0-20251224-UNOFFICIAL-flounder.zip` (9,013,248 bytes, no HTC wrapper) |
| Stable tag commits (no tags in repo) | 104 `7828a965895`, 105 `ec55e7c2bf4`, 106 `a07ea939d7e`, 107 `0e3d5747a3e`, 108 `e7a59c7f266` |

`HOSTCFLAGS=-fcommon` was enough for the host tools; `bc` is installed. A
blobless clone's first `git merge` of a tag sometimes exits without merging
while it lazily fetches blobs; re-running it works.

## Results

| Image | Kernel version | Kernel region | sha256 (image) |
|---|---|---|---|
| ROM `boot.img` (reference) | 3.10.103 | 7,265,947 | kernel `d1763ba8...` |
| `out/boot-baseline.img` | `3.10.103-g5cef0dc1890` | 7,265,683, 4 DTBs | `5e251899a2af5a71...` |
| `out/boot-3.10.108.img` | `3.10.108-gd70b80d5d56` | 7,271,704, 4 DTBs | `6362b382f0be6fb9...` |

Both: header and cmdline kept from the ROM image, ramdisk sha256
`961b8af0...` unchanged (checked with `tools/bootimg-split.py`). Baseline DTB
bytes are identical to the ROM's. Sizes are far below the 32 MiB `LNX` limit.

## Merge (branch `n9-3.10.108`, first-parent history)

`f5c4c0b62de` 104, `4aceb5e1f15` 105, `759b8cfd131` 106, `701bc9dc8ac` 107,
`30b558a9cf4` 108, `d70b80d5d56` posix_acl fix. The 11 extra lineage-16.0
commits are kept (they are ancestors; no conflict touched their files).

Conflict method (`~/n9kernel/scripts/resolve.sh`): for each conflicted file,
take the version from the reference merge `7d2636f5f56`, then reverse-apply the
stable commits newer than the tag being merged. Guarded: a file touched by the
11 extras or by non-stable commits on the reference branch would be flagged for
hand work (none were).

- 104: `include/linux/mm.h` by hand (kept our `FOLL_DURABLE`).
- 105: 11 files (arm64 spinlock/traps, blkcipher, thermal_core, u_ether,
  pstore, if_inet6.h, genalloc, wireless/scan, ipv6 addrconf + tcp_ipv6).
- 106: 14 files (ACL set, cpu.c/cpu.h, inet_connection_sock, ping, af_packet,
  tuner-xc2028, char/Kconfig). The DEVPORT Kconfig prompt (from 107) came in
  one tag early; harmless (needs ISA/PCI).
- 107: 6 files (mm/memory.c, mm/mmap.c, x86 mmap, ext4 super, xpad, char/Kconfig).
- 108: `net/core/dev.c`.
- Build failure after merge: `posix_acl_update_mode` defined twice (Android
  had already backported it as `7cf54a589ca`; git auto-merged a second copy).
  Fixed by taking `fs/posix_acl.c` and `include/linux/posix_acl.h` from the reference.

Check for silent duplicates: for all 819 stable-touched files not touched by
our extras or by the reference branch's non-stable commits, HEAD equals
`7d2636f5f56` (only `kernel/rcutree_plugin.h` differs, because the reference
moved RCU into `kernel/rcu/`). The 8 overlapping files differ only by
reference-branch extras (DenyUSB sysctl, cfq SSD tweak, workqueue rescuer,
`PAGE_ALIGNED`) and our O_TMPFILE `d_tmpfile`.

## Next actions

1. `fastboot boot ~/n9kernel/out/boot-baseline.img`; compare `/proc/version`,
   `/proc/config.gz`, dmesg against the flashed kernel.
2. Then `fastboot boot` `boot-3.10.108.img`; test Wi-Fi, BT, audio, LTE
   (USB2 modem), display, touch, charging, VDE decode.
3. After it boots: Step 2 of the plan (Divest CVE patches).

## 2026-10-26 01:38 — boot tests (fastboot boot, nothing flashed)
- boot-baseline.img (our GCC 4.9 build of unchanged lineage-16.0): boots, `3.10.103-g5cef0dc1890 (nyasha@cachyos-asus)`, sys.boot_completed=1. Toolchain + packaging proven.
- boot-3.10.108.img: boots (`3.10.108-gd70b80d5d56`); adb only appeared late (~9 min uptime when first seen; gadget configured at 61 s/91 s);
  Wi-Fi on, cameraserver running, rt5677 card present, no oops. Repeated PM_SUSPEND_PREPARE/POST_SUSPEND cycles (19 in ~1 min).
  **LTE regression**: modem boots (ks.ready=1, rmnet_usb0..3, SIM LOADED) but never registers (`NOT_REG_MT_SEARCHING_OP`, LTE srv_status flapping, reg status 13).
- Control, same session: reboot to the installed 3.10.103 -> Spark NZ / LTE / rmnet_usb0 IP within ~7 min of boot. So 3.10.104..108 breaks LTE registration (or suspend/USB-HSIC behaviour that the modem needs).
- Next: bisect by tag (build v3.10.104..107 intermediate images), suspects: drivers/usb (host/ehci, cdc/qmi), kernel/power + PM QoS (suspend loop), net/core.

## 2026-10-26 — per-tag bisect images (built, not yet booted)
- Worktree `~/n9kernel/wt` (detached), shared build dir `~/n9kernel/build-bisect` (built one after another), logs `out/build-10[4-7].log` (warnings only). Script `/tmp/bis.sh`.
- 106 and 107 need the posix_acl duplicate fix (`d70b80d5d56`, applied to the working tree, not committed); 104/105 have no duplicate.
- The worktree build has no `-g<hash>` suffix (setlocalversion does not see the `.git` file in a worktree).
- All checked with `bootimg-split.py`: ramdisk `961b8af0` unchanged, ROM header and cmdline kept.

| Image | Merge commit | `Linux version` | sha256 |
|---|---|---|---|
| `out/boot-3.10.104.img` | `f5c4c0b62de` | `3.10.104` | `e1d521a7f38ca6e5` |
| `out/boot-3.10.105.img` | `4aceb5e1f15` | `3.10.105` | `ccbc7a145c6a3527` |
| `out/boot-3.10.106.img` | `759b8cfd131` + acl fix | `3.10.106` | `51bb66abb7610b30` |
| `out/boot-3.10.107.img` | `701bc9dc8ac` + acl fix | `3.10.107` | `3d843344fea2cbba` |

- Next: `fastboot boot` each one and check LTE registration (start with 106 to split the range in half).

## 2026-10-26 02:00-02:40 — bisect by stable tag (fastboot boot only; /tmp/n9watch/lte-try.sh)
| image | adb after | LTE |
|---|---|---|
| 3.10.103 (installed) | normal | Spark NZ / LTE / IP |
| boot-3.10.106.img | 15 s | **OK** (Spark NZ, LTE, rmnet_usb0 IP) |
| boot-3.10.107.img | 20 s | **OK** |
| boot-3.10.108.img (try 1, 01:20) | ~9 min | **FAIL** (never registers, suspend churn) |
| boot-3.10.108.img (try 2, 02:04) | never (35+ min, 5 port power-cycles via tools/usb-kick.sh) | unknown, tablet unreachable (no USB, no Wi-Fi) |
=> The regression is inside the **v3.10.107 -> v3.10.108** step (141 commits). 104/105 untested (not needed).
Top suspects from notes/lte-regression-suspects.md that are in this step should be checked first (`git log v3.10.107..v3.10.108`
equivalent: merge 701bc9dc8ac..n9-3.10.108 tip). USB gadget late/absent + modem not registering + suspend churn point at USB core
(config.c endpoint parsing, hub reset wait) or PM/RTC changes.
- Safe state: nothing flashed. Tablet left hung in the 108 test kernel at ~02:40; a long power-button press returns it to the installed kernel.
- Next: build 107 + halves of the 108 step (git bisect within 701bc9dc8ac..tip), or revert the drivers/usb/core/config.c trio on 108 for one boot.
