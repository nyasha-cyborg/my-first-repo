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

## 2026-10-26 — 108-step split images (built, not booted)
- Step = first-parent of stable side `701bc9dc8ac^2..e7a59c7f266` (141 commits, list in `/tmp/step.txt`). Script `/tmp/b108.sh`, log `~/n9kernel/out/b108.log`. Branches in ~/n9kernel: n9-108-usbrevert, n9-108-q1..q3. All passed bootimg-split (ramdisk 961b8af0, cmdline kept).
- None of 15668b4354b/2226a520b3c/bb9a7c518fd/48091078f77 is in this step, and the step does not touch drivers/usb/core. (A) therefore reverts every drivers/usb commit of the step instead (only the gadget composite one is plausibly built for flounder).

| Image | Base | Linux version | sha256 |
|---|---|---|---|
| out/boot-108-usbrevert.img | n9-3.10.108 tip minus 11 USB commits | 3.10.108 | e9a11a95f7d3fd1b |
| out/boot-108-q1.img | 701bc9dc8ac + acl fix + step 1-35 | 3.10.107 | 14d4e4e7be411ef0 |
| out/boot-108-q2.img | ... + step 1-70 | 3.10.107 | f979cbc50cb19bc2 |
| out/boot-108-q3.img | ... + step 1-106 | 3.10.107 | 2987a0ae5c1403c2 |

Reverted in (A):
- 40216270c67 usb: gadget: composite: Fix use-after-free in usb_composite_overwrite_options
- 779ec20b951 usb: r8a66597-hcd: decrease timeout
- e1bdf20be95 usb: r8a66597-hcd: select a different endpoint on timeout
- be3e7b176c2 USB: serial: console: fix use-after-free after failed setup
- 5abdd6e8304 usb: renesas_usbhs: fix usbhsf_fifo_clear() for RX direction
- b974ab50791 usb: renesas_usbhs: fix the BCLR setting condition for non-DCP pipe
- a2555cd3e61 usb: renesas_usbhs: fix usbhsc_resume() for !USBHSF_RUNTIME_PWCTRL
- 54fd65c0763 usb: chipidea: debug: check before accessing ci_role
- 9a95fe3d74d usb: renesas_usbhs: Fix DMAC sequence for receiving zero-length packet
- b2453bd445b usb: renesas_usbhs: fix the sequence in xfer_work()
- 58e47d437d9 usb: renesas_usbhs: fix the behavior of some usbhs_pkt_handle

Skipped (cherry-pick conflict; likely already in the n9 tree or merge-resolved): 1bff8a2960f, 69ddef7b41f, 3937c2c918c, 7136ca73ff3 (q1+), be3e7b176c2 (q2+), 78da094deb3 (q3).

Step commits in order (q1 = 1-35, q2 = 1-70, q3 = 1-106; 107-141 only in full 108):
```
1 f0dce905083 ipvs: SNAT packet replies only for NATed connections
2 1bff8a2960f net: reduce skb_warn_bad_offload() noise
3 bf98a1be38f net: skb_needs_check() accepts CHECKSUM_NONE for tx
4 b673e043f91 Staging: comedi: comedi_fops: Avoid orphaned proc entry
5 69ddef7b41f udp: consistently apply ufo or fragmentation
6 b8d57eb2f41 Bluetooth: bnep: bnep_add_connection() should verify that it's dealing with l2cap socket
7 ecce864b830 Bluetooth: cmtp: cmtp_add_connection() should verify that it's dealing with l2cap socket
8 42a858e036b tcp: introduce tcp_rto_delta_us() helper for xmit timer fix
9 aa923a7b8f7 tcp: enable xmit timer fix by having TLP use time when RTO should fire
10 01c577c922f tcp: fix xmit timer to only be reset if data ACKed/SACKed
11 7c11e178a64 mm/page_alloc: Remove kernel address exposure in free_reserved_area()
12 75894adb0c7 leak in O_DIRECT readv past the EOF
13 58e47d437d9 usb: renesas_usbhs: fix the behavior of some usbhs_pkt_handle
14 b2453bd445b usb: renesas_usbhs: fix the sequence in xfer_work()
15 9a95fe3d74d usb: renesas_usbhs: Fix DMAC sequence for receiving zero-length packet
16 4f54b2642d4 fs/exec.c: account for argv/envp pointers
17 978e42bd293 rxrpc: Fix several cases where a padded len isn't checked in ticket decode
18 7571b7478bc xfrm: policy: check policy direction value
19 44ec968933c nl80211: check for the required netlink attributes presence
20 3937c2c918c ALSA: seq: Fix use-after-free at creating a port
21 6c176369e70 MIPS: Send SIGILL for BPOSGE32 in `__compute_return_epc_for_insn'
22 e044ff5c05d serial: ifx6x60: fix use-after-free on module unload
23 f862c943645 KEYS: fix dereferencing NULL payload with nonzero length
24 54fd65c0763 usb: chipidea: debug: check before accessing ci_role
25 69e0576f170 cpufreq: conservative: Allow down_threshold to take values from 1 to 10
26 790d869bd9d powerpc/kprobes: Pause function_graph tracing during jprobes handling
27 fe7e5549d05 staging: comedi: fix clean-up of comedi_class in comedi_init()
28 7136ca73ff3 brcmfmac: fix possible buffer overflow in brcmf_cfg80211_mgmt_tx()
29 1fc0b43a1df vt: fix unchecked __put_user() in tioclinux ioctls
30 f9c9c73b86b crypto: talitos - Extend max key length for SHA384/512-HMAC and AEAD
31 c11c8fcaa2e PM / Domains: Fix unsafe iteration over modified list of device links
32 8e38d086b8b powerpc/64: Fix atomic64_inc_not_zero() to return an int
33 733c88d4da7 powerpc: Fix emulation of mfocrf in emulate_step()
34 ecac824c4d0 powerpc/asm: Mark cr0 as clobbered in mftb()
35 a2555cd3e61 usb: renesas_usbhs: fix usbhsc_resume() for !USBHSF_RUNTIME_PWCTRL
36 6aa23d16b4d MIPS: Actually decode JALX in `__compute_return_epc_for_insn'
37 2121b630f51 MIPS: Fix unaligned PC interpretation in `compute_return_epc'
38 4748ac3f70a MIPS: math-emu: Prevent wrong ISA mode instruction emulation
39 7e20e7b9910 libata: array underflow in ata_find_dev()
40 ae49cb71c5f workqueue: restore WQ_UNBOUND/max_active==1 to be ordered
41 bdc5fbb365b ext4: fix SEEK_HOLE/SEEK_DATA for blocksize < pagesize
42 c39dcbde387 ext4: fix overflow caused by missing cast in ext4_resize_fs()
43 a6a256f6125 media: platform: davinci: return -EINVAL for VPFE_CMD_S_CCDC_RAW_PARAMS ioctl
44 003bea4a702 target: Avoid mappedlun symlink creation during lun shutdown
45 c2ace3043fe fuse: initialize the flock flag in fuse_file on allocation
46 f609dac6507 scsi: zfcp: fix queuecommand for scsi_eh commands when DIX enabled
47 e7ab3bd99e2 scsi: zfcp: add handling for FCP_RESID_OVER to the fcp ingress path
48 2c7bfb3408a scsi: zfcp: fix missing trace records for early returns in TMF eh handlers
49 bb5cf573ea9 scsi: zfcp: fix payload with full FCP_RSP IU in SCSI trace records
50 4b106b91a0c scsi: zfcp: trace HBA FSF response by default on dismiss or timedout late response
51 b974ab50791 usb: renesas_usbhs: fix the BCLR setting condition for non-DCP pipe
52 5abdd6e8304 usb: renesas_usbhs: fix usbhsf_fifo_clear() for RX direction
53 544d7ba2c83 iommu/amd: Finish TLB flush in amd_iommu_unmap()
54 d75e8540fd8 direct-io: Prevent NULL pointer access in submit_page_section
55 be3e7b176c2 USB: serial: console: fix use-after-free after failed setup
56 20d94bc9406 KEYS: don't let add_key() update an uninstantiated key
57 ba850927667 FS-Cache: fix dereference of NULL user_key_payload
58 9c66c82c5fd ext4: keep existing extra fields when inode expands
59 f9e779c5387 MIPS: Fix mips_atomic_set() retry condition
60 e8705c4233f KEYS: prevent creating a different user's keyrings
61 a45d36761bc KEYS: encrypted: fix dereference of NULL user_key_payload
62 9ac5390b028 md/bitmap: disable bitmap_resize for file-backed bitmaps.
63 a77cf1b9831 lib/digsig: fix dereference of NULL user_key_payload
64 09ab11ebb7c netfilter: invoke synchronize_rcu after set the _hook_ to NULL
65 634fd953630 md/raid10: submit bio directly to replacement disk
66 7719043b415 md: fix super_offset endianness in super_1_rdev_size_change
67 303177699c7 lib/cmdline.c: fix get_options() overflow while parsing ranges
68 2f34aab1a87 ext4: fix SEEK_HOLE
69 4ef41964ac0 net: prevent sign extension in dev_get_stats()
70 7af6952b185 kernel/extable.c: mark core_kernel_text notrace
71 19cc6d98a6a wext: handle NULL extra data in iwe_stream_add_point better
72 159c95bdb52 netfilter: nf_ct_ext: fix possible panic after nf_ct_extend_unregister
73 ebb33aff58b ext4: in ext4_seek_{hole,data}, return -ENXIO for negative offsets
74 9f75306bea1 ext4: avoid deadlock when expanding inode size
75 3cb637d2295 sctp: don't dereference ptr before leaving _sctp_walk_{params, errors}()
76 2630e5a878f sctp: fix the check for _sctp_walk_params and _sctp_walk_errors
77 faa132ab557 sctp: fully initialize the IPv6 address in sctp_v6_to_addr()
78 08bd34b7527 sctp: potential read out of bounds in sctp_ulpevent_type_enabled()
79 946272f8a5f tcp: disallow cwnd undo when switching congestion control
80 72d7b83afbc netfilter: xt_TCPMSS: add more sanity tests on tcph->doff
81 6f85a887304 tcp: reset sk_rx_dst in tcp_disconnect()
82 37cb3624306 tcp: avoid setting cwnd to invalid ssthresh after cwnd reduction states
83 81d2ec20138 tcp: when rearming RTO, if RTO time is in past then fire RTO ASAP
84 83fef5222fb tcp: initialize rcv_mss to TCP_MIN_MSS instead of 0
85 055ad9609c6 net/packet: check length in getsockopt() called with PACKET_HDRLEN
86 78da094deb3 net: Set sk_prot_creator when cloning sockets to the right proto
87 bc3eedee113 net/mlx4_core: Fix VF overwrite of module param which disables DMFS on new probed PFs
88 61eea2752a1 net: 8021q: Fix one possible panic caused by BUG_ON in free_netdev
89 28968bccd81 x86/io: Add "memory" clobber to insb/insw/insl/outsb/outsw/outsl
90 ca58e312914 kvm: async_pf: fix rcu_irq_enter() with irqs enabled
91 f7eb769a8db net: ping: do not abuse udp_poll()
92 a72c279dfbf scsi: qla2xxx: don't disable a not previously enabled PCI device
93 7e25c935ec7 drm/vmwgfx: Handle vmalloc() failure in vmw_local_fifo_reserve()
94 f6b525b94bd net: xilinx_emaclite: fix receive buffer overflow
95 12d805b5903 serial: efm32: Fix parity management in 'efm32_uart_console_get_options()'
96 e52eca82d17 x86/mm/32: Set the '__vmalloc_start_set' flag in initmem_init()
97 1e7ae919899 mfd: omap-usb-tll: Fix inverted bit use for USB TLL mode
98 655e5ff7d64 pvrusb2: reduce stack usage pvr2_eeprom_analyze()
99 e1bdf20be95 usb: r8a66597-hcd: select a different endpoint on timeout
100 779ec20b951 usb: r8a66597-hcd: decrease timeout
101 240607692cd drivers/misc/c2port/c2port-duramar2150.c: checking for NULL instead of IS_ERR()
102 18144201ec7 net: phy: fix marvell phy status reading
103 6ac502ceabf net: korina: Fix NAPI versus resources freeing
104 f478b4264a3 xfrm: NULL dereference on allocation failure
105 04d00696302 xfrm: Oops on error in pfkey_msg2xfrm_state()
106 40cfe451deb cpufreq: s3c2416: double free on driver init error path
107 fe77accbd15 KVM: x86: zero base3 of unusable segments
108 98b9e94ba66 KEYS: Fix an error code in request_master_key()
109 fa69abfe6a0 ipv6: avoid unregistering inet6_dev for loopback
110 d4740818891 cfg80211: Validate frequencies nested in NL80211_ATTR_SCAN_FREQUENCIES
111 9efa3d52796 cfg80211: Check if PMKID attribute is of expected size
112 b569326cedf mm: fix overflow check in expand_upwards()
113 7fb443fa861 crypto: caam - fix signals handling
114 ad087167073 ir-core: fix gcc-7 warning on bool arithmetic
115 3a7578afc3a udf: Fix deadlock between writeback and udf_setsize()
116 c1327b455fd perf annotate: Fix broken arrow at row 0 connecting jmp instruction to its target
117 50602d3e499 net/mlx4: Remove BUG_ON from ICM allocation routine
118 ef6fa3f56c0 ipv4: initialize fib_trie prior to register_netdev_notifier call.
119 162f50e6914 workqueue: implicit ordered attribute should be overridable
120 fe1fd359c1d packet: fix tp_reserve race in packet_set_ring
121 b4824101fca staging:iio:resolver:ad2s1210 fix negative IIO_ANGL_VEL read
122 136211c2849 ALSA: core: Fix unexpected error at replacing user TLV
123 71bec91ec42 ACPI / APEI: Add missing synchronize_rcu() on NOTIFY_SCI removal
124 dd3e5010b97 qlge: avoid memcpy buffer overflow
125 4e39d5e48ba ipv6: fix memory leak with multiple tables during netns destruction
126 488ec7b227e ipv6: fix typo in fib6_net_exit()
127 6f47a87d154 ip6_gre: fix endianness errors in ip6gre_err
128 92e84b6aecc crypto: AF_ALG - remove SGL terminator indicator when chaining
129 c5378d27add scsi: qla2xxx: Fix an integer overflow in sysfs code
130 ec8c69ea454 tracing: Apply trace_clock changes to instance max buffer
131 7210062e8fc tracing: Erase irqsoff trace with empty write
132 827a5cb0a0a btrfs: prevent to set invalid default subvolid
133 90326945a4f IB/ipoib: rtnl_unlock can not come after free_netdev
134 f63d10b98de team: fix memory leaks
135 75840f10809 IB/qib: fix false-postive maybe-uninitialized warning
136 49218ad1217 KVM: nVMX: fix guest CR4 loading when emulating L2 to L1 exit
137 40216270c67 usb: gadget: composite: Fix use-after-free in usb_composite_overwrite_options
138 4de0e6b506b scsi: scsi_dh_emc: return success in clariion_std_inquiry()
139 541cbdc60ac can: esd_usb2: Fix can_dlc value for received RTR, frames
140 68cbe939621 x86/apic: fix build breakage caused by incomplete backport to 3.10
141 e7a59c7f266 Linux 3.10.108
```
- Next: boot q2; LTE OK -> q3, FAIL -> q1. Separately boot usbrevert.
- 09:00 108 tablet had been up 7 h on boot-3.10.108 with no USB gadget at all and LTE unregistered; physical replug brought adb back.
  tools/usb-kick.sh port "disable" does NOT replace a replug (VBUS stays on; the tablet's gadget never sees a disconnect).
- 09:13 boot-108-q2.img (step commits 1-70): **LTE OK** (Spark NZ/LTE/IP) but **USB gadget dead until physical replug** (adb at 635 s).
  => two separate regressions: USB-gadget enumeration in commits 1-70, LTE registration in commits 71-141.
