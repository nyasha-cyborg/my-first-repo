# Kernel security, Step 2 Wave A (3.10.108 + Divest CVE patches)

**Summary (plain):** Branch `n9-3.10.108-sec` in `~/n9kernel/kernel` (HEAD `09fe51e6f51`)
adds 53 commits on top of the working 3.10.108 kernel: the binder fix used by
real Android root exploits (CVE-2019-2215) plus 51 Divest patches for binder-adjacent
areas, raw sockets, netfilter, USB gadget, sound, ext4/f2fs and keyrings. 30 patches
were skipped (fix already in the tree, or the code is not built for flounder). None
failed. The kernel builds with no new errors or warnings (270 warnings, same as the base).
**Not boot-tested yet.**

- Image: `~/n9kernel/out/boot-3.10.108-secA.img` (9,019,392 bytes, sha256 `b53b0d03b2b6442d...`),
  uname `3.10.108-g09fe51e6f51`. bootimg-split: ramdisk `961b8af0` unchanged, ROM cmdline kept.
- Build log: `~/n9kernel/out/build-108-secA.log`; build dir `~/n9kernel/build-108` (reused).
- Scripts: `/tmp/divkp/w/{sel.py,run.sh,b.sh}`; Kernel_Patches clone `/tmp/divkp/kp` (713 MB, depth 1).

## Method
- Patch list = `CVE-*` lines of the flounder Divest script (`/tmp/n9kernelsurvey/divest_flounder.sh`)
  whose files touch the Wave A areas. Hardening dirs (0005/0006 etc.) left for Wave D.
- "Compiled in" = the patched `.c` has a `.o` in `build-108` (lineage_flounder_defconfig build).
  If none do: SKIP not compiled, not applied.
- `git apply --check` -> apply + one commit (`Divest: <CVE> <first file>`); else `--check -R` ok -> SKIP already present; else FAIL.
- Afterwards each OK patch's upstream sha was checked against the base log. One hit,
  CVE-2014-8086 ext4, had applied at an offset as a duplicate of the fix already in 3.10.108
  (`30d8c835`); it was dropped from the branch and is listed as SKIP.

## Binder (CVE-2019-2215)
- Our binder lives in `drivers/android/binder.c` (old single-lock binder), so the 3.10 patch
  was applied with the path rewritten. Verified: `BINDER_LOOPER_STATE_POLL` set in `binder_poll`,
  and `wake_up_poll(&thread->wait, POLLHUP | POLLFREE)` lands in `binder_free_thread` (the
  thread-release path for BINDER_THREAD_EXIT and process release) before `kfree(thread)`.
- Extra hand commit: `synchronize_rcu()` before `kfree(thread)` when the thread polled.
  3.10 `ep_remove_wait_queue()` reads the waitqueue under RCU, so freeing right after POLLFREE
  is still a race (what upstream later fixed with `wake_up_pollfree`). Cost: one RCU grace
  period when a polling binder thread exits; runs under the global binder mutex.

## Results
| CVE | Patch | Area | First file | Result | Commit / reason |
|---|---|---|---|---|---|
| CVE-2019-2215 | CVE-2019-2215/3.10/0011.patch (path ported) | binder | drivers/android/binder.c | OK | c474f1b0058 |
| CVE-2019-2215 (follow-up) | hand | binder | drivers/android/binder.c | OK | c474f1b0058 |
| CVE-2012-6540 | CVE-2012-6540/3.4/0003.patch | netfilter | net/netfilter/ipvs/ip_vs_ctl.c | SKIP | not compiled |
| CVE-2014-8086 | CVE-2014-8086/3.10/0002.patch | ext4 | fs/ext4/file.c | SKIP | already present (30d8c835; applied at offset as duplicate, dropped) |
| CVE-2014-9892 | CVE-2014-9892/ANY/0001.patch | sound | sound/core/compress_offload.c | OK | ee05ab18ca0 |
| CVE-2015-0275 | CVE-2015-0275/^4.0/0001.patch | ext4 | fs/ext4/extents.c | OK | 395c6967e3e |
| CVE-2015-8539 | CVE-2015-8539/3.18/0002.patch | keys | security/keys/encrypted-keys/encrypted.c | SKIP | not compiled |
| CVE-2016-3135 | CVE-2016-3135/3.4/0003.patch | netfilter | net/netfilter/x_tables.c | OK | 90cb2c60386 |
| CVE-2016-7042 | CVE-2016-7042/3.10/0002.patch | keys | security/keys/proc.c | SKIP | not compiled |
| CVE-2016-9604 | CVE-2016-9604/3.10/0003.patch | keys | security/keys/keyctl.c | SKIP | not compiled |
| CVE-2016-10318 | CVE-2016-10318/3.18/0002.patch | ext4 | fs/ext4/crypto_policy.c | SKIP | not compiled |
| CVE-2017-16USB | CVE-2017-16USB/^4.13/0001.patch | sound | sound/usb/usx2y/usb_stream.c | SKIP | not compiled |
| CVE-2017-16USB | CVE-2017-16USB/^4.14/0006.patch | sound | sound/usb/usx2y/usb_stream.c | SKIP | not compiled |
| CVE-2017-0537 | CVE-2017-0537/ANY/0001.patch | usbgadget | drivers/usb/gadget/configfs.c | OK | 2e13b7ae5e6 |
| CVE-2017-0861 | CVE-2017-0861/3.10/0004.patch | sound | sound/core/pcm.c | OK | 4b0e91469ac |
| CVE-2017-6951 | CVE-2017-6951/^3.18/0002.patch | keys | security/keys/gc.c | SKIP | not compiled |
| CVE-2017-7472 | CVE-2017-7472/3.10/0003.patch | keys | security/keys/keyctl.c | SKIP | not compiled |
| CVE-2017-9984 | CVE-2017-9984/3.18/0002.patch | sound | sound/isa/msnd/msnd_midi.c | SKIP | not compiled |
| CVE-2017-13216 | CVE-2017-13216/3.10/0003.patch | ashmem | drivers/staging/android/ashmem.c | SKIP | already present |
| CVE-2017-13245 | CVE-2017-13245/ANY/0001.patch | sound | include/sound/rawmidi.h | OK | dfd74f80e11 |
| CVE-2017-13273 | CVE-2017-13273/ANY/0001.patch | netfilter | net/netfilter/xt_qtaguid.c | OK | 50c612b0033 |
| CVE-2017-13305 | CVE-2017-13305/3.10/0009.patch | keys | security/keys/encrypted-keys/encrypted.c | SKIP | not compiled |
| CVE-2017-15274 | CVE-2017-15274/3.10/0002.patch | keys | security/keys/keyctl.c | SKIP | not compiled |
| CVE-2017-15299 | CVE-2017-15299/3.10/0002.patch | keys | security/keys/key.c | SKIP | not compiled |
| CVE-2017-17450 | CVE-2017-17450/3.18/0003.patch | netfilter | net/netfilter/xt_osf.c | SKIP | not compiled |
| CVE-2017-18017 | CVE-2017-18017/3.10/0002.patch | netfilter | net/netfilter/xt_TCPMSS.c | SKIP | already present |
| CVE-2017-18241 | CVE-2017-18241/4.4/0004.patch | f2fs | fs/f2fs/segment.c | OK | f086b57cb15 |
| CVE-2017-18270 | CVE-2017-18270/3.10/0002.patch | keys | include/linux/key.h | SKIP | not compiled |
| CVE-2018-1068 | CVE-2018-1068/3.10/0008.patch | netfilter | net/bridge/netfilter/ebtables.c | SKIP | not compiled |
| CVE-2018-1068 | CVE-2018-1068/^4.16/0002.patch | netfilter | net/bridge/netfilter/ebtables.c | SKIP | not compiled |
| CVE-2018-7566 | CVE-2018-7566/3.18/0003.patch | sound | sound/core/seq/seq_clientmgr.c | SKIP | not compiled |
| CVE-2018-10876 | CVE-2018-10876/3.10/0017.patch | ext4 | fs/ext4/balloc.c | OK | de47bb7d97c |
| CVE-2018-10878 | CVE-2018-10878/3.18/0005.patch | ext4 | fs/ext4/balloc.c | OK | 9ef5b931db5 |
| CVE-2018-10879 | CVE-2018-10879/3.10/0006.patch | ext4 | fs/ext4/xattr.c | OK | 54643e69f4a |
| CVE-2018-10879 | CVE-2018-10879/3.10/0007.patch | ext4 | fs/ext4/xattr.c | OK | 904d46369b2 |
| CVE-2018-10880 | CVE-2018-10880/3.10/0004.patch | ext4 | fs/ext4/xattr.c | OK | 09f06382422 |
| CVE-2018-10881 | CVE-2018-10881/3.10/0007.patch | ext4 | fs/ext4/inline.c | OK | 1ac617a1d9b |
| CVE-2018-10882 | CVE-2018-10882/3.10/0003.patch | ext4 | fs/ext4/ext4.h | OK | 53ebcf3890b |
| CVE-2018-10883 | CVE-2018-10883/3.18/0007.patch | ext4 | fs/ext4/ext4.h | OK | 905188c01b7 |
| CVE-2018-19824 | CVE-2018-19824/3.10/0008.patch | sound | sound/usb/card.c | OK | 06ccba8e7ea |
| CVE-2019-11833 | CVE-2019-11833/^5.1/0001.patch | ext4 | fs/ext4/extents.c | OK | 5aeaf037373 |
| CVE-2019-15214 | CVE-2019-15214/3.4/0003.patch | sound | sound/core/init.c | OK | b6a62332ef4 |
| CVE-2019-19447 | CVE-2019-19447/3.10/0009.patch | ext4 | fs/ext4/namei.c | OK | 3b075b07f35 |
| CVE-2019-20812 | CVE-2019-20812/3.18/0003.patch | packet | net/packet/af_packet.c | OK | 40d15e8af89 |
| CVE-2020-13143 | CVE-2020-13143/3.18/0003.patch | usbgadget | drivers/usb/gadget/configfs.c | OK | 73ff5213c47 |
| CVE-2020-14305 | CVE-2020-14305/4.4/0003.patch | netfilter | net/netfilter/nf_conntrack_h323_main.c | OK | 430b41bc437 |
| CVE-2020-14314 | CVE-2020-14314/3.18/0002.patch | ext4 | fs/ext4/namei.c | OK | 799cf6d8e73 |
| CVE-2020-14386 | CVE-2020-14386/3.10-^4.4/0002.patch | packet | net/packet/af_packet.c | OK | 9f650cd7622 |
| CVE-2020-25211 | CVE-2020-25211/3.18/0007.patch | netfilter | net/netfilter/nf_conntrack_netlink.c | OK | ce37fa27a34 |
| CVE-2021-0399 | CVE-2021-0399/3.18/0001.patch | netfilter | net/netfilter/xt_qtaguid.c | OK | 4ee9bfc7f3a |
| CVE-2021-0695 | CVE-2021-0695/ANY/0001.patch | netfilter | net/netfilter/xt_qtaguid.c | OK | 6c06f196793 |
| CVE-2021-0961 | CVE-2021-0961/4.4/0004.patch | netfilter | net/netfilter/xt_quota2.c | OK | b101784b006 |
| CVE-2021-0961 | CVE-2021-0961/4.4/0005.patch | netfilter | net/netfilter/xt_quota2.c | OK | 21c9c5c97dc |
| CVE-2021-3428 | CVE-2021-3428/3.18/0001.patch | ext4 | fs/ext4/super.c | OK | 3d901c38a3b |
| CVE-2021-47117 | CVE-2021-47117/3.18/0001.patch | ext4 | fs/ext4/extents.c | OK | 6b6e0c1bda1 |
| CVE-2021-47207 | CVE-2021-47207/4.4/0004.patch | sound | sound/isa/gus/gus_dma.c | SKIP | not compiled |
| CVE-2021-47451 | CVE-2021-47451/^5.15/0001.patch | netfilter | net/netfilter/xt_IDLETIMER.c | OK | b9a09500d7a |
| CVE-2022-0850 | CVE-2022-0850/3.18/0001.patch | ext4 | fs/ext4/extents.c | OK | 3e3cfe3aca2 |
| CVE-2022-2663 | CVE-2022-2663/4.4/0012.patch | netfilter | net/netfilter/nf_conntrack_irc.c | OK | 905e6dc3f65 |
| CVE-2022-2663 | CVE-2022-2663/4.4/0013.patch | netfilter | net/netfilter/nf_conntrack_irc.c | OK | 2cc90fc77f0 |
| CVE-2022-24958 | CVE-2022-24958/3.4/0017.patch | usbgadget | drivers/usb/gadget/inode.c | SKIP | not compiled |
| CVE-2022-25258 | CVE-2022-25258/3.4/0009.patch | usbgadget | drivers/usb/gadget/composite.c | OK | 8eeaf88c1d9 |
| CVE-2022-25375 | CVE-2022-25375/3.4/0009.patch | usbgadget | drivers/usb/gadget/rndis.c | SKIP | not compiled |
| CVE-2022-48701 | CVE-2022-48701/4.4/0001.patch | sound | sound/usb/stream.c | OK | f7200757b16 |
| CVE-2022-48702 | CVE-2022-48702/4.4/0001.patch | sound | sound/pci/emu10k1/emupcm.c | SKIP | not compiled |
| CVE-2022-48992 | CVE-2022-48992/4.4/0001.patch | sound | sound/soc/soc-pcm.c | OK | 916026c6118 |
| CVE-2022-48994 | CVE-2022-48994/4.4/0001.patch | sound | sound/core/seq/seq_memory.c | SKIP | not compiled |
| CVE-2022-Misc2 | CVE-2022-Misc2/3.4/0004.patch | sound | sound/soc/soc-pcm.c | OK | 620a28261ba |
| CVE-2023-7192 | CVE-2023-7192/4.4/0001.patch | netfilter | net/netfilter/nf_conntrack_netlink.c | OK | 4f2c437ed20 |
| CVE-2023-39192 | CVE-2023-39192/4.4/0001.patch | netfilter | net/netfilter/xt_u32.c | OK | ca97f25b8ad |
| CVE-2023-39193 | CVE-2023-39193/4.4/0001.patch | netfilter | net/netfilter/xt_sctp.c | SKIP | not compiled |
| CVE-2023-52436 | CVE-2023-52436/4.4/0008.patch | f2fs | fs/f2fs/xattr.c | OK | aa7cc92efbf |
| CVE-2024-26704 | CVE-2024-26704/4.4/0001.patch | ext4 | fs/ext4/move_extent.c | OK | 8b6a6e85ffa |
| CVE-2024-26772 | CVE-2024-26772/4.4/0001.patch | ext4 | fs/ext4/mballoc.c | OK | ad8dd740bce |
| CVE-2024-26851 | CVE-2024-26851/4.4/0001.patch | netfilter | net/netfilter/nf_conntrack_h323_asn1.c | OK | 65eec689a74 |
| CVE-2024-35962 | CVE-2024-35962/^6.9/0001.patch | netfilter | net/ipv4/netfilter/arp_tables.c | OK | 830407d5213 |
| CVE-2024-42097 | CVE-2024-42097/4.4/0008.patch | sound | sound/synth/emux/soundfont.c | SKIP | not compiled |
| CVE-2024-49882 | CVE-2024-49882/4.4/0008.patch | ext4 | fs/ext4/extents.c | OK | e83e223d807 |
| CVE-2024-49883 | CVE-2024-49883/4.4/0008.patch | ext4 | fs/ext4/extents.c | OK | 32cc148f06e |
| CVE-2024-49967 | CVE-2024-49967/4.4/0008.patch | ext4 | fs/ext4/namei.c | OK | 64a118f38b4 |
| CVE-2024-50006 | CVE-2024-50006/4.4/0008.patch | ext4 | fs/ext4/migrate.c | OK | 09fe51e6f51 |
| CVE-2024-50007 | CVE-2024-50007/4.4/0008.patch | sound | sound/pci/asihpi/hpimsgx.c | SKIP | not compiled |
| CVE-2022-20423 | CVE-2022-20423/3.4/0010.patch | usbgadget | drivers/usb/gadget/rndis.c | SKIP | not compiled |

## FAILs worth hand-porting
- None in Wave A (0 FAIL). Divest's flounder patches are already rebased for this tree.

## Risks / open items
- Not boot-tested. Boot it and check binder (Android up, `sys.boot_completed`), USB gadget/adb,
  audio, LTE before Wave B.
- Ashmem, netfilter (incl. xt_qtaguid), sound and ext4 patches change behaviour in code Android
  uses every boot; a regression would show as boot loops or a missing adb.
- "Compiled in" check uses the old build dir's objects; header-only patches are counted by their .c files.
- nvmap / nvhost / nvgpu (the ion/kgsl equivalents) are still unpatched: no upstream patches,
  need hand-porting from Google bulletins (separate task).
- 10:10-10:22 boot-3.10.108-secA.img x2: USB OK (15/20 s), LTE OK (Spark NZ/LTE/IP), Wi-Fi on, cameraserver running, no oops. Wave A passes the boot test.
