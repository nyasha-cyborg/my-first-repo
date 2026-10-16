# Nexus 9 Linux projects, and where each one stopped

Checked 2026-10-16. "Abandoned" here means the last relevant activity is years old,
or the hosting project has formally retired it. Dates are last commit / last push.

## Upstream Linux: never started

There has never been a Nexus 9 device tree in the mainline kernel.

- `arch/arm64/boot/dts/nvidia/Makefile` builds exactly one Tegra 132 board:
  `dtb-$(CONFIG_ARCH_TEGRA_132_SOC) += tegra132-norrin.dtb`. The directory holds
  `tegra132-norrin.dts` (the NVIDIA dev board), `tegra132.dtsi`, and
  `tegra132-peripherals-opp.dtsi` — no `flounder`.
- Commit history for `arch/arm64/boot/dts/nvidia/tegra132-flounder.dts` in
  `torvalds/linux` is empty: no commit has ever touched that path.
- Nothing matching `flounder` in `arch/arm/boot/dts/nvidia` either.

So every Linux port for this tablet is out of tree, and none of them can be "the
upstream one". This is the root cause of everything below: each port has to carry a
whole device tree privately.

## Personal kernel forks (where the support actually lives)

| Project | Last activity | State |
|---|---|---|
| `TuxThePenguin0/linux`, branch `device/htc-flounder` | 2022-11-10 | The "ongoing mainline port" the postmarketOS wiki links to. Last commits are battery settings, thermal zones, PMIC interrupt cleanup; the blog series announcing it (`ansari.sh/posts/mainline-nexus-9-p1/`) has only a part 1, whose "next steps" were USB and a custom initramfs. Branch still exists; nothing since Nov 2022. |
| `yuka/linux` (`Yureka Lilian`) | 2026-10-12 | The fork postmarketOS's kernel package currently pins (`_commit=38ff6862…`, pkgver 6.19.0). Repo created 2026-01-20; the flounder support arrives as a single squashed `Initial master branch` commit. Active, but one person, one commit, one fork, no upstreaming. |
| `dcambie/linux` | 2023-04-14 | Single commit `60bc14ca`, message "Ugly hack — just to check if this is really the issue", `arch/arm64/boot/dts/nvidia/tegra132-flounder.dts` +1/-1: the `google,flounder64` → `google,flounder64_lte` change. Never followed up; the postmarketOS wiki cites it as the evidence for the LTE requirement. |
| `delaanthonio/linux-flounder` | 2019-08 (archived) | Custom Android kernel based on flar2's ElementalX. GitHub marks the repo archived. |

## postmarketOS

The device was retired in June 2026 and the split is worth knowing:

| Package | Location now | State |
|---|---|---|
| `device-htc-flounder` | `device/archived/device-htc-flounder` | Moved by `treewide: archive unmaintained packages under device/` (2026-06-22). APKBUILD now starts `# Archived: unmaintained`, `maintainer=""`. |
| `device-htc-flounder-downstream` | `device/archived/…` | The older port built on the Android 3.10 downstream kernel. Archived by the same commit. |
| `linux-htc-flounder` | still `device/testing/linux-htc-flounder` | 6.19.0, maintainer Szymon Graczyk, commits as recent as 2026-06-12 ("install modules to /usr", "add maintainer"). It builds `yuka/linux`, not upstream. |

So the kernel package is nominally maintained while the device package that consumes
it is archived with no maintainer — the port is not installable as a supported
device any more, and the wiki page is tagged `category = archived`.

Recorded device state (from the wiki page, so as of whenever it was last edited):

- working: booting, touch, Wi-Fi, OTG, battery, power sensor
- partial: screen
- not working: USB networking, 3D, audio, Bluetooth, camera, GPS, all sensors

Installation needs `pmbootstrap install --single-partition`, because the initramfs
cannot open the subpartitions.

History: pmbootstrap MR !1309 (initial), pmaports MR !3623 (mainline kernel,
TuxThePenguin0, Nov 2022), pmbootstrap issue !1384 (kernel panic).

The wiki's LTE note is the same finding as `patches/dts-compatible-flounder64-lte.patch`:
the bootloader only loads a kernel whose DTB `compatible` matches the board
(`google,flounder64` Wi-Fi, `google,flounder64_lte` LTE).

## Android projects (Linux-based, retired)

| Project | Last activity | State |
|---|---|---|
| LineageOS 14.1 `flounder` | 2019-02-25 (14.1 EOL) | Wiki banner: "no longer maintained"; build guide kept for private builds only. |
| `TeamWin/android_device_htc_flounder` (TWRP) | 2020-06-07 | Dormant device tree. |
| `AOSPA/android_device_htc_flounder` | 2020-04-08 | Dormant. |
| `SlimRoms/device_htc_flounder`, `SlimRoms/kernel_htc_flounder` | 2018-05-06 | SlimRoms is itself dead. |
| `SaberMod/flounder-kernel` | 2015-01-27 | Dead. |
| `bbedward/ZenKernel_Flounder` | 2015-04-20 | Dead. |
| `LiquidSmooth-Devices/android_device_htc_flounder` | 2015-08-16 | LiquidSmooth is dead. |
| `craigacgomez/device_htc_flounder` | 2016-01-05 | Dead. |
| `binkybear/flounder` | 2016-08-28 | Dormant. |
| XDA "[Guide] Linux on the Nexus 9" | ~2015 | The old hand-rolled approach: downstream kernel plus a Debian/Ubuntu rootfs. Superseded, never maintained. |

## Ubuntu Touch / UBports

No flounder port surfaced. The Ubuntu Touch device list and its API have no Nexus 9
entry, and searching the porting documentation returns only generic guides. Treat
this as "no evidence found" rather than proof that no one ever tried.

## Useful dormant resources

- `leddaz-dump-stash/google_flounder_dump`, `…/google_flounder_lte_dump` (2022-09-03):
  firmware/partition dumps for both variants. Dormant but still the reference for
  what the vendor partitions contain.

## What this means for this branch

The realistic target is not upstream and not the archived pmOS device package; it is
**`yuka/linux`**, because that is what the surviving kernel package builds. The
one-line LTE `compatible` fix belongs there (or in a fork of it), and the LTE board
file from the downstream tree — `tegra132-flounder_lte-xaxbxcxdpvt.dts`, i.e.
`hw-revision = "xa,xb,xc,xd,pvt"` — is the thing to port next, so that one tree
covers every revision instead of just the Wi-Fi board.
