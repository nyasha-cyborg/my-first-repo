# Kernel security, Wave B fix-ups + Wave C (Divest CVEs 2022-2024)

**Summary (plain):** Branch `n9-3.10.108-sec` in `~/n9kernel/kernel`. Of the 3 Wave B failures,
2 turned out to be already fixed in our tree (they came in with the 3.10.105/106 stable merges;
Wave B tried the wrong-version patch files). The third (tty session race, the most serious) was
hand-ported as one commit. Then Wave C added 37 more Divest fixes from 2022-2024, one commit
each. 236 skipped (218 code not built for flounder, 18 already present), 1 failed. Both kernels
build cleanly with GCC 4.9, no new warnings (271, same as Wave B). **Neither is boot-tested.**

| Image | Tree HEAD | Size | sha256 (16) | kernel / ramdisk |
|---|---|---|---|---|
| `~/n9kernel/out/boot-3.10.108-secB3.img` (safe midpoint: Wave B + tty hand-port) | `64048e55f1b` | 9,029,632 | `46a83be688afc9c9` | 7,282,331 / `961b8af0` unchanged |
| `~/n9kernel/out/boot-3.10.108-secC.img` (+ Wave C) | `bb3052c7115` | 9,031,680 | `3554259ba63b024a` | 7,284,029 / `961b8af0` unchanged |

bootimg-split on both: page 2048, ROM cmdline kept. Build logs: `~/n9kernel/out/build-108-sec{B3,C}.log`.
Scripts and raw results: `/tmp/divkp/wc/{selC.py,run.sh,b.sh,results.tsv,fn.txt,table.md}`.
Suggested test order: secB3 first (only one change vs. tested secB), then secC.

## Part 1: the 3 Wave B FAILs
1. **CVE-2020-29660** tty `->session` locking: **hand-ported**, commit `64048e55f1b` (on top of
   `bcaa06b1c42`). The 3.18 patch failed only because our 3.10 `disassociate_ctty()` already drops
   `siglock` before reading the tty (it uses `get_current_tty()`, which takes a ref under siglock).
   Ported upstream c8bcd9c5be24 by meaning:
   - `disassociate_ctty`: `tty_lock()`/`tty_unlock()` around clearing `session`/`pgrp`
     (checked: no caller holds tty_lock: `no_tty()` from TIOCNOTTY and SELinux, `do_exit`).
   - `tiocspgrp`: session check + pgrp update now under `ctrl_lock` (`spin_lock_irq`), new
     `out_unlock_ctrl` label; `get_user` moved before the lock (may sleep).
   - `tiocgsid`: reads `session` under `ctrl_lock`, `put_user` after unlock.
   - `__do_SAK`: takes a pid reference under `ctrl_lock`, `put_pid` at end.
   - `__proc_set_tty`: `session` assignment moved inside `ctrl_lock` (hunk from the 4.14 backport;
     the 3.18 file lacked it).
   - `include/linux/tty.h`: locking comment. Compile-checked (`tty_io.o` no warnings).
2. **CVE-2017-2671** ping_unhash locking: **already present**. `ping_unhash()` already takes
   `ping_table.lock` outside `sk_hashed()` (stable 3.10 backport). Wave B used the `^4.11` file,
   whose context (`ping_unhash` debug string) differs. No commit.
3. **CVE-2016-20022** USB wMaxPacket validation: **already present** (stable commit `2226a520b3c`,
   plus the later 1023->1024 HS interrupt typo fix). No commit.

## Part 2: Wave C method
- List = every `CVE-*` `git apply` line in `/tmp/n9kernelsurvey/divest_flounder.sh` with CVE year
  2022-2024 (274 entries, script order). Same rules as Wave B: no `.o` in `build-108` for any patched
  `.c` -> SKIP not compiled; `apply --check` -> commit; `--check -R` -> SKIP present; else FAIL. No hand-ports.
- Hunk check (`fn.py`): 34/37 matched exactly. Read by hand, all in the intended function:
  CVE-2024-39501 (3.10 name `show_uevent` vs `uevent_show`), CVE-2024-47679 (`evict_inodes`,
  context was a label), CVE-2024-49959 (`__jbd2_log_wait_for_space`, context was an annotation).

## FAILs by severity (not hand-ported)
1. **CVE-2022-Misc2** `drivers/tty/tty_io.c` ("tty: fix memleak in alloc_pid", 3.4 patch). Low: it
   reads `signal->tty` under siglock in `disassociate_ctty`; our tree's `get_current_tty()` already
   does that read under siglock, and the Part 1 hand-port covers the session race. Effectively moot.

## Risks / open items
- Not boot-tested. Wave C touches USB (cdc-wdm, uvc), net (ipv4/ipv6, xfrm, af_key, nl80211,
  mac80211, ppp), fs (inode, exec, open, jbd2, fat), input/HID, mm (mmap, memblock), pstore.
  Check USB/adb, LTE, Wi-Fi, camera, `sys.boot_completed`, 0 oops.

## Wave C results
| CVE | patch | file | result | detail |
|---|---|---|---|---|
| CVE-2022-0850 | CVE-2022-0850/3.18/0001.patch | fs/ext4/extents.c | SKIP | already present |
| CVE-2022-1353 | CVE-2022-1353/4.4/0001.patch | net/key/af_key.c | OK | e41ae85e937 |
| CVE-2022-1516 | CVE-2022-1516/4.4/0008.patch | net/x25/af_x25.c | SKIP | not compiled |
| CVE-2022-1652 | CVE-2022-1652/4.4/0008.patch | drivers/block/floppy.c | SKIP | not compiled |
| CVE-2022-1836 | CVE-2022-1836/4.4/0001.patch | drivers/block/Kconfig | SKIP | not compiled |
| CVE-2022-2153 | CVE-2022-2153/^5.17/0002.patch | arch/x86/kvm/lapic.c | SKIP | not compiled |
| CVE-2022-2318 | CVE-2022-2318/4.4/0008.patch | net/rose/rose_timer.c | SKIP | not compiled |
| CVE-2022-2663 | CVE-2022-2663/4.4/0012.patch | net/netfilter/nf_conntrack_irc.c | SKIP | already present |
| CVE-2022-2663 | CVE-2022-2663/4.4/0013.patch | net/netfilter/nf_conntrack_irc.c | SKIP | already present |
| CVE-2022-3028 | CVE-2022-3028/4.4/0008.patch | net/key/af_key.c | OK | c524b48c9a6 |
| CVE-2022-3111 | CVE-2022-3111/4.4/0001.patch | drivers/power/wm8350_power.c | SKIP | not compiled |
| CVE-2022-3424 | CVE-2022-3424/4.4/0008.patch | drivers/misc/sgi-gru/grufault.c | SKIP | not compiled |
| CVE-2022-3542 | CVE-2022-3542/3.8-^6.0/0001.patch | drivers/net/ethernet/broadcom/bnx2x/bnx2x_cmn.c | SKIP | not compiled |
| CVE-2022-3621 | CVE-2022-3621/4.4/0008.patch | fs/nilfs2/inode.c | SKIP | not compiled |
| CVE-2022-3628 | CVE-2022-3628/4.4/0008.patch | drivers/net/wireless/brcm80211/brcmfmac/fweh.c | SKIP | not compiled |
| CVE-2022-3635 | CVE-2022-3635/4.4/0008.patch | drivers/atm/idt77252.c | SKIP | not compiled |
| CVE-2022-4378 | CVE-2022-4378/4.4/0015.patch | kernel/sysctl.c | OK | b81ee3230a0 |
| CVE-2022-20141 | CVE-2022-20141/3.4/0008.patch | net/ipv4/igmp.c | OK | c9383fee6cd |
| CVE-2022-24958 | CVE-2022-24958/3.4/0017.patch | drivers/usb/gadget/inode.c | SKIP | not compiled |
| CVE-2022-25258 | CVE-2022-25258/3.4/0009.patch | drivers/usb/gadget/composite.c | SKIP | already present |
| CVE-2022-25375 | CVE-2022-25375/3.4/0009.patch | drivers/usb/gadget/rndis.c | SKIP | not compiled |
| CVE-2022-28390 | CVE-2022-28390/4.4/0008.patch | drivers/net/can/usb/ems_usb.c | SKIP | not compiled |
| CVE-2022-36123 | CVE-2022-36123/4.4/0008.patch | arch/x86/kernel/head64.c | SKIP | not compiled |
| CVE-2022-36280 | CVE-2022-36280/4.4/0008.patch | drivers/gpu/drm/vmwgfx/vmwgfx_kms.c | SKIP | not compiled |
| CVE-2022-39188 | CVE-2022-39188/4.4/0010.patch | mm/mmap.c | OK | 6f8adf7df01 |
| CVE-2022-41850 | CVE-2022-41850/4.4/0008.patch | drivers/hid/hid-roccat.c | OK | f02fa06906a |
| CVE-2022-41858 | CVE-2022-41858/4.4/0001.patch | drivers/net/slip/slip.c | SKIP | not compiled |
| CVE-2022-42895 | CVE-2022-42895/4.4/0008.patch | net/bluetooth/l2cap_core.c | SKIP | not compiled |
| CVE-2022-43750 | CVE-2022-43750/4.4/0008.patch | drivers/usb/mon/mon_bin.c | SKIP | not compiled |
| CVE-2022-45887 | CVE-2022-45887/4.4/0001.patch | drivers/media/usb/ttusb-dec/ttusb_dec.c | SKIP | not compiled |
| CVE-2022-45919 | CVE-2022-45919/4.4/0001.patch | drivers/media/dvb-core/dvb_ca_en50221.c | SKIP | not compiled |
| CVE-2022-45934 | CVE-2022-45934/4.4/0008.patch | net/bluetooth/l2cap_core.c | SKIP | not compiled |
| CVE-2022-48619 | CVE-2022-48619/4.4/0001.patch | drivers/input/input.c | OK | aaf57675f4d |
| CVE-2022-48627 | CVE-2022-48627/4.4/0006.patch | drivers/tty/vt/vt.c | SKIP | not compiled |
| CVE-2022-48701 | CVE-2022-48701/4.4/0001.patch | sound/usb/stream.c | SKIP | already present |
| CVE-2022-48702 | CVE-2022-48702/4.4/0001.patch | sound/pci/emu10k1/emupcm.c | SKIP | not compiled |
| CVE-2022-48710 | CVE-2022-48710/4.4/0001.patch | drivers/gpu/drm/radeon/radeon_connectors.c | SKIP | not compiled |
| CVE-2022-48781 | CVE-2022-48781/^5.17/0001.patch | crypto/af_alg.c | SKIP | not compiled |
| CVE-2022-48795 | CVE-2022-48795/4.4/0001.patch | drivers/parisc/sba_iommu.c | SKIP | not compiled |
| CVE-2022-48919 | CVE-2022-48919/4.4/0001.patch | fs/cifs/cifsfs.c | SKIP | not compiled |
| CVE-2022-48930 | CVE-2022-48930/4.4/0001.patch | drivers/infiniband/ulp/srp/ib_srp.c | SKIP | not compiled |
| CVE-2022-48946 | CVE-2022-48946/4.4/0001.patch | fs/udf/truncate.c | SKIP | not compiled |
| CVE-2022-48958 | CVE-2022-48958/4.4/0001.patch | drivers/net/ethernet/aeroflex/greth.c | SKIP | not compiled |
| CVE-2022-48967 | CVE-2022-48967/4.4/0001.patch | net/nfc/nci/ntf.c | SKIP | not compiled |
| CVE-2022-48992 | CVE-2022-48992/4.4/0001.patch | sound/soc/soc-pcm.c | SKIP | already present |
| CVE-2022-48994 | CVE-2022-48994/4.4/0001.patch | sound/core/seq/seq_memory.c | SKIP | not compiled |
| CVE-2022-49007 | CVE-2022-49007/4.4/0001.patch | fs/nilfs2/dat.c | SKIP | not compiled |
| CVE-2022-49029 | CVE-2022-49029/4.4/0001.patch | drivers/hwmon/ibmpex.c | SKIP | not compiled |
| CVE-2022-Misc2 | CVE-2022-Misc2/3.4/0004.patch | sound/soc/soc-pcm.c | SKIP | already present |
| CVE-2022-Misc2 | CVE-2022-Misc2/3.4/0008.patch | drivers/tty/tty_io.c | FAIL | patch does not apply |
| CVE-2023-0394 | CVE-2023-0394/4.4/0007.patch | net/ipv6/raw.c | OK | c33a4d529e8 |
| CVE-2023-0590 | CVE-2023-0590/4.4/0007.patch | net/sched/sch_api.c | OK | d0c2cb3ae58 |
| CVE-2023-1073 | CVE-2023-1073/4.4/0007.patch | drivers/hid/hid-core.c | OK | 1140a051146 |
| CVE-2023-1074 | CVE-2023-1074/4.4/0007.patch | net/sctp/bind_addr.c | SKIP | not compiled |
| CVE-2023-1118 | CVE-2023-1118/4.4/0007.patch | drivers/media/rc/ene_ir.c | SKIP | not compiled |
| CVE-2023-1670 | CVE-2023-1670/4.4/0008.patch | drivers/net/ethernet/xircom/xirc2ps_cs.c | SKIP | not compiled |
| CVE-2023-1989 | CVE-2023-1989/4.4/0012.patch | drivers/bluetooth/btsdio.c | SKIP | not compiled |
| CVE-2023-1989 | CVE-2023-1989/^6.3/0002.patch | drivers/bluetooth/btsdio.c | SKIP | not compiled |
| CVE-2023-2248 | CVE-2023-2248/4.4/0008.patch | net/sched/sch_qfq.c | SKIP | not compiled |
| CVE-2023-2985 | CVE-2023-2985/4.4/0001.patch | fs/hfsplus/super.c | SKIP | not compiled |
| CVE-2023-3141 | CVE-2023-3141/4.4/0001.patch | drivers/memstick/host/r592.c | SKIP | not compiled |
| CVE-2023-3159 | CVE-2023-3159/4.4/0001.patch | drivers/firewire/core-cdev.c | SKIP | not compiled |
| CVE-2023-3161 | CVE-2023-3161/4.4/0001.patch | drivers/video/console/fbcon.c | SKIP | not compiled |
| CVE-2023-3212 | CVE-2023-3212/4.4/0008.patch | fs/gfs2/super.c | SKIP | not compiled |
| CVE-2023-3567 | CVE-2023-3567/4.4/0008.patch | drivers/tty/vt/vc_screen.c | SKIP | not compiled |
| CVE-2023-3772 | CVE-2023-3772/4.4/0008.patch | net/xfrm/xfrm_user.c | OK | 025469a990f |
| CVE-2023-4385 | CVE-2023-4385/4.4/0001.patch | fs/jfs/jfs_dmap.c | SKIP | not compiled |
| CVE-2023-4459 | CVE-2023-4459/4.4/0001.patch | drivers/net/vmxnet3/vmxnet3_drv.c | SKIP | not compiled |
| CVE-2023-4623 | CVE-2023-4623/4.4/0008.patch | net/sched/sch_hfsc.c | SKIP | not compiled |
| CVE-2023-6270 | CVE-2023-6270/4.4/0008.patch | drivers/block/aoe/aoecmd.c | SKIP | not compiled |
| CVE-2023-7192 | CVE-2023-7192/4.4/0001.patch | net/netfilter/nf_conntrack_netlink.c | SKIP | already present |
| CVE-2023-23559 | CVE-2023-23559/4.4/0007.patch | drivers/net/wireless/rndis_wlan.c | SKIP | not compiled |
| CVE-2023-28328 | CVE-2023-28328/4.4/0001.patch | drivers/media/usb/dvb-usb/az6027.c | SKIP | not compiled |
| CVE-2023-31085 | CVE-2023-31085/4.4/0008.patch | drivers/mtd/ubi/build.c | SKIP | not compiled |
| CVE-2023-32269 | CVE-2023-32269/4.4/0001.patch | net/netrom/af_netrom.c | SKIP | not compiled |
| CVE-2023-35824 | CVE-2023-35824/4.4/0001.patch | drivers/media/pci/dm1105/dm1105.c | SKIP | not compiled |
| CVE-2023-39192 | CVE-2023-39192/4.4/0001.patch | net/netfilter/xt_u32.c | SKIP | already present |
| CVE-2023-39193 | CVE-2023-39193/4.4/0001.patch | net/netfilter/xt_sctp.c | SKIP | not compiled |
| CVE-2023-45862 | CVE-2023-45862/4.4/0001.patch | drivers/usb/storage/ene_ub6250.c | SKIP | not compiled |
| CVE-2023-51780 | CVE-2023-51780/4.4/0009.patch | net/atm/ioctl.c | SKIP | not compiled |
| CVE-2023-51782 | CVE-2023-51782/4.4/0009.patch | net/rose/af_rose.c | SKIP | not compiled |
| CVE-2023-52436 | CVE-2023-52436/4.4/0008.patch | fs/f2fs/xattr.c | SKIP | already present |
| CVE-2023-52445 | CVE-2023-52445/4.4/0008.patch | drivers/media/usb/pvrusb2/pvrusb2-context.c | SKIP | not compiled |
| CVE-2023-52449 | CVE-2023-52449/4.4/0008.patch | drivers/mtd/mtd_blkdevs.c | SKIP | not compiled |
| CVE-2023-52475 | CVE-2023-52475/4.4/0001.patch | drivers/input/misc/powermate.c | SKIP | not compiled |
| CVE-2023-52507 | CVE-2023-52507/4.4/0001.patch | net/nfc/nci/core.c | SKIP | not compiled |
| CVE-2023-52566 | CVE-2023-52566/4.4/0001.patch | fs/nilfs2/gcinode.c | SKIP | not compiled |
| CVE-2023-52594 | CVE-2023-52594/4.4/0008.patch | drivers/net/wireless/ath/ath9k/htc_drv_txrx.c | SKIP | not compiled |
| CVE-2023-52599 | CVE-2023-52599/4.4/0008.patch | fs/jfs/jfs_imap.c | SKIP | not compiled |
| CVE-2023-52602 | CVE-2023-52602/4.4/0008.patch | fs/jfs/jfs_dtree.c | SKIP | not compiled |
| CVE-2023-52603 | CVE-2023-52603/4.4/0008.patch | fs/jfs/jfs_dtree.c | SKIP | not compiled |
| CVE-2023-52604 | CVE-2023-52604/4.4/0008.patch | fs/jfs/jfs_dmap.c | SKIP | not compiled |
| CVE-2023-52685 | CVE-2023-52685/4.4/0001.patch | fs/pstore/ram_core.c | OK | 524978b2e3f |
| CVE-2023-52699 | CVE-2023-52699/4.4/0001.patch | fs/sysv/itree.c | SKIP | not compiled |
| CVE-2023-52703 | CVE-2023-52703/4.4/0001.patch | drivers/net/usb/kalmia.c | SKIP | not compiled |
| CVE-2023-52705 | CVE-2023-52705/4.4/0001.patch | fs/nilfs2/ioctl.c | SKIP | not compiled |
| CVE-2023-52742 | CVE-2023-52742/4.4/0001.patch | drivers/net/usb/plusb.c | SKIP | not compiled |
| CVE-2023-52764 | CVE-2023-52764/4.4/0001.patch | drivers/media/usb/gspca/cpia1.c | SKIP | not compiled |
| CVE-2023-52774 | CVE-2023-52774/4.4/0001.patch | drivers/s390/block/dasd.c | SKIP | not compiled |
| CVE-2023-52804 | CVE-2023-52804/4.4/0001.patch | fs/jfs/jfs_dmap.c | SKIP | not compiled |
| CVE-2023-52805 | CVE-2023-52805/4.4/0001.patch | fs/jfs/jfs_imap.c | SKIP | not compiled |
| CVE-2023-52809 | CVE-2023-52809/4.4/0001.patch | drivers/scsi/libfc/fc_lport.c | SKIP | not compiled |
| CVE-2023-52813 | CVE-2023-52813/4.4/0001.patch | crypto/pcrypt.c | SKIP | not compiled |
| CVE-2023-52832 | CVE-2023-52832/4.4/0001.patch | net/mac80211/cfg.c | OK | c6dbbdb343a |
| CVE-2023-52843 | CVE-2023-52843/4.4/0001.patch | net/llc/llc_input.c | SKIP | not compiled |
| CVE-2023-52847 | CVE-2023-52847/^6.6/0001.patch | drivers/media/pci/bt8xx/bttv-driver.c | SKIP | not compiled |
| CVE-2023-52880 | CVE-2023-52880/^6.5/0002.patch | drivers/tty/n_gsm.c | SKIP | not compiled |
| CVE-2023-52893 | CVE-2023-52893/4.4/0001.patch | drivers/firmware/google/gsmi.c | SKIP | not compiled |
| CVE-2023-52900 | CVE-2023-52900/4.4/0001.patch | fs/nilfs2/btree.c | SKIP | not compiled |
| CVE-2023-52922 | CVE-2023-52922/4.4/0001.patch | net/can/bcm.c | SKIP | not compiled |
| CVE-2024-22099 | CVE-2024-22099/4.4/0008.patch | net/bluetooth/rfcomm/core.c | SKIP | not compiled |
| CVE-2024-24855 | CVE-2024-24855/^6.4/0001.patch | drivers/scsi/lpfc/lpfc_hbadisc.c | SKIP | not compiled |
| CVE-2024-24861 | CVE-2024-24861/4.4/0001.patch | drivers/media/tuners/xc4000.c | SKIP | not compiled |
| CVE-2024-25739 | CVE-2024-25739/4.4/0001.patch | drivers/mtd/ubi/vtbl.c | SKIP | not compiled |
| CVE-2024-26625 | CVE-2024-26625/4.4/0008.patch | net/llc/af_llc.c | SKIP | not compiled |
| CVE-2024-26635 | CVE-2024-26635/4.4/0001.patch | include/net/llc_pdu.h | SKIP | not compiled |
| CVE-2024-26675 | CVE-2024-26675/4.4/0001.patch | drivers/net/ppp/ppp_async.c | OK | 8aa9e7a4d01 |
| CVE-2024-26696 | CVE-2024-26696/4.4/0001.patch | fs/nilfs2/file.c | SKIP | not compiled |
| CVE-2024-26697 | CVE-2024-26697/4.4/0001.patch | fs/nilfs2/recovery.c | SKIP | not compiled |
| CVE-2024-26704 | CVE-2024-26704/4.4/0001.patch | fs/ext4/move_extent.c | SKIP | already present |
| CVE-2024-26772 | CVE-2024-26772/4.4/0001.patch | fs/ext4/mballoc.c | SKIP | already present |
| CVE-2024-26816 | CVE-2024-26816/4.4/0001.patch | arch/x86/tools/relocs.c | SKIP | not compiled |
| CVE-2024-26851 | CVE-2024-26851/4.4/0001.patch | net/netfilter/nf_conntrack_h323_asn1.c | SKIP | already present |
| CVE-2024-26875 | CVE-2024-26875/4.4/0001.patch | drivers/media/usb/pvrusb2/pvrusb2-context.c | SKIP | not compiled |
| CVE-2024-26894 | CVE-2024-26894/4.4/0001.patch | drivers/acpi/processor_idle.c | SKIP | not compiled |
| CVE-2024-26901 | CVE-2024-26901/4.4/0001.patch | fs/fhandle.c | SKIP | not compiled |
| CVE-2024-26955 | CVE-2024-26955/4.4/0001.patch | fs/nilfs2/inode.c | SKIP | not compiled |
| CVE-2024-26956 | CVE-2024-26956/4.4/0001.patch | fs/nilfs2/btree.c | SKIP | not compiled |
| CVE-2024-26973 | CVE-2024-26973/4.4/0001.patch | fs/fat/nfs.c | OK | 63bf0010c96 |
| CVE-2024-26981 | CVE-2024-26981/4.4/0008.patch | fs/nilfs2/dir.c | SKIP | not compiled |
| CVE-2024-26994 | CVE-2024-26994/4.4/0008.patch | drivers/staging/speakup/main.c | SKIP | not compiled |
| CVE-2024-26999 | CVE-2024-26999/4.4/0008.patch | drivers/tty/serial/pmac_zilog.c | SKIP | not compiled |
| CVE-2024-27008 | CVE-2024-27008/4.4/0008.patch | drivers/gpu/drm/nouveau/nouveau_bios.c | SKIP | not compiled |
| CVE-2024-27009 | CVE-2024-27009/^6.9/0001.patch | drivers/s390/cio/device.c | SKIP | not compiled |
| CVE-2024-27059 | CVE-2024-27059/4.4/0001.patch | drivers/usb/storage/isd200.c | SKIP | not compiled |
| CVE-2024-27401 | CVE-2024-27401/4.4/0008.patch | drivers/firewire/nosy.c | SKIP | not compiled |
| CVE-2024-27410 | CVE-2024-27410/4.4/0001.patch | net/wireless/nl80211.c | OK | b8582e56879 |
| CVE-2024-27419 | CVE-2024-27419/4.4/0001.patch | net/netrom/af_netrom.c | SKIP | not compiled |
| CVE-2024-27420 | CVE-2024-27420/4.4/0001.patch | net/netrom/nr_route.c | SKIP | not compiled |
| CVE-2024-27421 | CVE-2024-27421/4.4/0001.patch | net/netrom/nr_route.c | SKIP | not compiled |
| CVE-2024-27426 | CVE-2024-27426/4.4/0001.patch | net/netrom/af_netrom.c | SKIP | not compiled |
| CVE-2024-27427 | CVE-2024-27427/4.4/0001.patch | net/netrom/af_netrom.c | SKIP | not compiled |
| CVE-2024-27428 | CVE-2024-27428/4.4/0001.patch | net/netrom/nr_dev.c | SKIP | not compiled |
| CVE-2024-27429 | CVE-2024-27429/4.4/0001.patch | net/netrom/nr_route.c | SKIP | not compiled |
| CVE-2024-27430 | CVE-2024-27430/4.4/0001.patch | net/netrom/nr_route.c | SKIP | not compiled |
| CVE-2024-35821 | CVE-2024-35821/4.4/0001.patch | fs/ubifs/file.c | SKIP | not compiled |
| CVE-2024-35828 | CVE-2024-35828/4.4/0001.patch | drivers/net/wireless/libertas/cmd.c | SKIP | not compiled |
| CVE-2024-35849 | CVE-2024-35849/4.4/0001.patch | fs/btrfs/backref.c | SKIP | not compiled |
| CVE-2024-35886 | CVE-2024-35886/4.4/0001.patch | net/ipv6/ip6_fib.c | OK | e1b63954526 |
| CVE-2024-35930 | CVE-2024-35930/4.4/0001.patch | drivers/scsi/lpfc/lpfc_nportdisc.c | SKIP | not compiled |
| CVE-2024-35935 | CVE-2024-35935/4.4/0001.patch | fs/btrfs/send.c | SKIP | not compiled |
| CVE-2024-35944 | CVE-2024-35944/4.4/0001.patch | drivers/misc/vmw_vmci/vmci_datagram.c | SKIP | not compiled |
| CVE-2024-35947 | CVE-2024-35947/4.4/0008.patch | lib/dynamic_debug.c | OK | afc166a6ae7 |
| CVE-2024-35962 | CVE-2024-35962/^6.9/0001.patch | net/ipv4/netfilter/arp_tables.c | SKIP | already present |
| CVE-2024-36016 | CVE-2024-36016/4.4/0008.patch | drivers/tty/n_gsm.c | SKIP | not compiled |
| CVE-2024-36484 | CVE-2024-36484/4.4/0008.patch | net/ipv4/af_inet.c | OK | cca60c35bcf |
| CVE-2024-36902 | CVE-2024-36902/4.4/0008.patch | net/ipv6/fib6_rules.c | OK | e473aece023 |
| CVE-2024-36919 | CVE-2024-36919/4.4/0008.patch | drivers/scsi/bnx2fc/bnx2fc_tgt.c | SKIP | not compiled |
| CVE-2024-36946 | CVE-2024-36946/4.4/0008.patch | net/phonet/pn_netlink.c | SKIP | not compiled |
| CVE-2024-36960 | CVE-2024-36960/4.4/0008.patch | drivers/gpu/drm/vmwgfx/vmwgfx_fence.c | SKIP | not compiled |
| CVE-2024-36964 | CVE-2024-36964/4.4/0008.patch | fs/9p/vfs_inode.c | SKIP | not compiled |
| CVE-2024-37078 | CVE-2024-37078/4.4/0008.patch | fs/nilfs2/segment.c | SKIP | not compiled |
| CVE-2024-38565 | CVE-2024-38565/4.4/0001.patch | drivers/net/wireless/ath/ar5523/ar5523.c | SKIP | not compiled |
| CVE-2024-38567 | CVE-2024-38567/4.4/0001.patch | drivers/net/wireless/ath/carl9170/usb.c | SKIP | not compiled |
| CVE-2024-38578 | CVE-2024-38578/4.4/0001.patch | fs/ecryptfs/keystore.c | SKIP | not compiled |
| CVE-2024-38587 | CVE-2024-38587/4.4/0001.patch | drivers/staging/speakup/main.c | SKIP | not compiled |
| CVE-2024-38589 | CVE-2024-38589/4.4/0001.patch | net/netrom/nr_route.c | SKIP | not compiled |
| CVE-2024-38599 | CVE-2024-38599/4.4/0001.patch | fs/jffs2/xattr.c | SKIP | not compiled |
| CVE-2024-38601 | CVE-2024-38601/4.4/0001.patch | kernel/trace/ring_buffer.c | OK | fab51f4664b |
| CVE-2024-38607 | CVE-2024-38607/4.4/0001.patch | drivers/macintosh/via-macii.c | SKIP | not compiled |
| CVE-2024-38613 | CVE-2024-38613/4.4/0001.patch | arch/m68k/kernel/entry.S | SKIP | not compiled |
| CVE-2024-38619 | CVE-2024-38619/4.4/0008.patch | drivers/usb/storage/alauda.c | SKIP | not compiled |
| CVE-2024-38621 | CVE-2024-38621/4.4/0008.patch | drivers/media/usb/stk1160/stk1160-video.c | SKIP | not compiled |
| CVE-2024-38633 | CVE-2024-38633/4.4/0008.patch | drivers/tty/serial/max3100.c | SKIP | not compiled |
| CVE-2024-38634 | CVE-2024-38634/4.4/0008.patch | drivers/tty/serial/max3100.c | SKIP | not compiled |
| CVE-2024-38659 | CVE-2024-38659/4.4/0008.patch | drivers/net/ethernet/cisco/enic/enic_main.c | SKIP | not compiled |
| CVE-2024-39292 | CVE-2024-39292/4.4/0008.patch | arch/um/drivers/line.c | SKIP | not compiled |
| CVE-2024-39469 | CVE-2024-39469/4.4/0008.patch | fs/nilfs2/dir.c | SKIP | not compiled |
| CVE-2024-39480 | CVE-2024-39480/4.4/0008.patch | kernel/debug/kdb/kdb_io.c | SKIP | not compiled |
| CVE-2024-39499 | CVE-2024-39499/4.4/0008.patch | drivers/misc/vmw_vmci/vmci_event.c | SKIP | not compiled |
| CVE-2024-39501 | CVE-2024-39501/4.4/0008.patch | drivers/base/core.c | OK | 86518e9cb70 |
| CVE-2024-39509 | CVE-2024-39509/4.4/0008.patch | drivers/hid/hid-core.c | OK | 56f49bd36f4 |
| CVE-2024-40902 | CVE-2024-40902/4.4/0008.patch | fs/jfs/xattr.c | SKIP | not compiled |
| CVE-2024-40904 | CVE-2024-40904/3.5-^6.10/0001.patch | drivers/usb/class/cdc-wdm.c | OK | aaba2846cf2 |
| CVE-2024-40917 | CVE-2024-40917/^6.10/0001.patch | mm/memblock.c | OK | 6c8ea3e9df5 |
| CVE-2024-40942 | CVE-2024-40942/4.4/0008.patch | net/mac80211/mesh_pathtbl.c | SKIP | not compiled |
| CVE-2024-40943 | CVE-2024-40943/4.4/0008.patch | fs/ocfs2/file.c | SKIP | not compiled |
| CVE-2024-40953 | CVE-2024-40953/4.4/0008.patch | virt/kvm/kvm_main.c | SKIP | not compiled |
| CVE-2024-40954 | CVE-2024-40954/^6.10/0001.patch | net/core/sock.c | OK | 406952279ef |
| CVE-2024-40968 | CVE-2024-40968/4.4/0008.patch | arch/mips/pci/pcie-octeon.c | SKIP | not compiled |
| CVE-2024-40974 | CVE-2024-40974/4.4/0008.patch | arch/powerpc/include/asm/hvcall.h | SKIP | not compiled |
| CVE-2024-40981 | CVE-2024-40981/4.4/0008.patch | net/batman-adv/originator.c | SKIP | not compiled |
| CVE-2024-41016 | CVE-2024-41016/4.4/0008.patch | fs/ocfs2/xattr.c | SKIP | not compiled |
| CVE-2024-41017 | CVE-2024-41017/4.4/0008.patch | fs/jfs/xattr.c | SKIP | not compiled |
| CVE-2024-41068 | CVE-2024-41068/4.4/0008.patch | drivers/s390/char/sclp.c | SKIP | not compiled |
| CVE-2024-41089 | CVE-2024-41089/4.4/0008.patch | drivers/gpu/drm/nouveau/dispnv04/tvnv17.c | SKIP | not compiled |
| CVE-2024-41095 | CVE-2024-41095/4.4/0008.patch | drivers/gpu/drm/nouveau/dispnv04/tvnv17.c | SKIP | not compiled |
| CVE-2024-41097 | CVE-2024-41097/4.4/0008.patch | drivers/usb/atm/cxacru.c | SKIP | not compiled |
| CVE-2024-42084 | CVE-2024-42084/4.4/0008.patch | fs/open.c | OK | c0b7cb3d943 |
| CVE-2024-42090 | CVE-2024-42090/4.4/0008.patch | drivers/pinctrl/core.c | OK | faaef7f8856 |
| CVE-2024-42097 | CVE-2024-42097/4.4/0008.patch | sound/synth/emux/soundfont.c | SKIP | not compiled |
| CVE-2024-42101 | CVE-2024-42101/4.4/0008.patch | drivers/gpu/drm/nouveau/nouveau_connector.c | SKIP | not compiled |
| CVE-2024-42104 | CVE-2024-42104/4.4/0008.patch | fs/nilfs2/dir.c | SKIP | not compiled |
| CVE-2024-42115 | CVE-2024-42115/4.4/0008.patch | fs/jffs2/super.c | SKIP | not compiled |
| CVE-2024-42145 | CVE-2024-42145/4.4/0008.patch | drivers/infiniband/core/user_mad.c | SKIP | not compiled |
| CVE-2024-42148 | CVE-2024-42148/4.4/0008.patch | drivers/net/ethernet/broadcom/bnx2x/bnx2x.h | SKIP | not compiled |
| CVE-2024-42223 | CVE-2024-42223/4.4/0008.patch | drivers/media/dvb-frontends/tda10048.c | SKIP | not compiled |
| CVE-2024-42271 | CVE-2024-42271/4.4/0008.patch | net/iucv/af_iucv.c | SKIP | not compiled |
| CVE-2024-42280 | CVE-2024-42280/4.4/0008.patch | drivers/isdn/hardware/mISDN/hfcmulti.c | SKIP | not compiled |
| CVE-2024-42309 | CVE-2024-42309/4.4/0008.patch | drivers/gpu/drm/gma500/psb_intel_lvds.c | SKIP | not compiled |
| CVE-2024-42310 | CVE-2024-42310/4.4/0008.patch | drivers/gpu/drm/gma500/cdv_intel_lvds.c | SKIP | not compiled |
| CVE-2024-42311 | CVE-2024-42311/4.4/0008.patch | fs/hfs/inode.c | SKIP | not compiled |
| CVE-2024-43839 | CVE-2024-43839/4.4/0008.patch | drivers/net/ethernet/brocade/bna/bna_types.h | SKIP | not compiled |
| CVE-2024-43858 | CVE-2024-43858/4.4/0008.patch | fs/jfs/jfs_imap.c | SKIP | not compiled |
| CVE-2024-43882 | CVE-2024-43882/4.4/0008.patch | fs/exec.c | OK | 3bc16ccc02f |
| CVE-2024-43893 | CVE-2024-43893/4.4/0008.patch | drivers/tty/serial/serial_core.c | OK | 129aa0fe70d |
| CVE-2024-44939 | CVE-2024-44939/^6.9/0001.patch | fs/jfs/jfs_dtree.c | SKIP | not compiled |
| CVE-2024-44998 | CVE-2024-44998/4.4/0008.patch | drivers/atm/idt77252.c | SKIP | not compiled |
| CVE-2024-45008 | CVE-2024-45008/4.4/0008.patch | drivers/input/input-mt.c | OK | 19f0408acd6 |
| CVE-2024-45028 | CVE-2024-45028/4.4/0008.patch | drivers/mmc/card/mmc_test.c | OK | aabe0f7426b |
| CVE-2024-46673 | CVE-2024-46673/4.4/0008.patch | drivers/scsi/aacraid/comminit.c | SKIP | not compiled |
| CVE-2024-46738 | CVE-2024-46738/4.4/0008.patch | drivers/misc/vmw_vmci/vmci_resource.c | SKIP | not compiled |
| CVE-2024-46755 | CVE-2024-46755/4.4/0008.patch | drivers/net/wireless/mwifiex/main.h | SKIP | not compiled |
| CVE-2024-46756 | CVE-2024-46756/4.4/0008.patch | drivers/hwmon/w83627ehf.c | SKIP | not compiled |
| CVE-2024-46757 | CVE-2024-46757/4.4/0008.patch | drivers/hwmon/nct6775.c | SKIP | not compiled |
| CVE-2024-46758 | CVE-2024-46758/4.4/0008.patch | drivers/hwmon/lm95234.c | SKIP | not compiled |
| CVE-2024-46777 | CVE-2024-46777/4.4/0008.patch | fs/udf/super.c | SKIP | not compiled |
| CVE-2024-46781 | CVE-2024-46781/4.4/0008.patch | fs/nilfs2/recovery.c | SKIP | not compiled |
| CVE-2024-46830 | CVE-2024-46830/^6.11/0001.patch | arch/x86/kvm/x86.c | SKIP | not compiled |
| CVE-2024-46844 | CVE-2024-46844/4.4/0008.patch | arch/um/drivers/line.c | SKIP | not compiled |
| CVE-2024-47669 | CVE-2024-47669/4.4/0001.patch | fs/nilfs2/segment.c | SKIP | not compiled |
| CVE-2024-47670 | CVE-2024-47670/4.4/0008.patch | fs/ocfs2/xattr.c | SKIP | not compiled |
| CVE-2024-47679 | CVE-2024-47679/4.4/0008.patch | fs/inode.c | OK | 80c74aa11e4 |
| CVE-2024-47699 | CVE-2024-47699/4.4/0008.patch | fs/nilfs2/btree.c | SKIP | not compiled |
| CVE-2024-47709 | CVE-2024-47709/^6.11/0001.patch | net/can/bcm.c | SKIP | not compiled |
| CVE-2024-47747 | CVE-2024-47747/4.4/0008.patch | drivers/net/ethernet/seeq/ether3.c | SKIP | not compiled |
| CVE-2024-47757 | CVE-2024-47757/4.4/0008.patch | fs/nilfs2/btree.c | SKIP | not compiled |
| CVE-2024-49877 | CVE-2024-49877/4.4/0008.patch | fs/ocfs2/buffer_head_io.c | SKIP | not compiled |
| CVE-2024-49882 | CVE-2024-49882/4.4/0008.patch | fs/ext4/extents.c | SKIP | already present |
| CVE-2024-49883 | CVE-2024-49883/4.4/0008.patch | fs/ext4/extents.c | SKIP | already present |
| CVE-2024-49900 | CVE-2024-49900/4.4/0008.patch | fs/jfs/xattr.c | SKIP | not compiled |
| CVE-2024-49903 | CVE-2024-49903/4.4/0008.patch | fs/jfs/jfs_discard.c | SKIP | not compiled |
| CVE-2024-49944 | CVE-2024-49944/4.4/0008.patch | net/sctp/socket.c | SKIP | not compiled |
| CVE-2024-49957 | CVE-2024-49957/4.4/0008.patch | fs/ocfs2/journal.c | SKIP | not compiled |
| CVE-2024-49959 | CVE-2024-49959/^6.11/0001.patch | fs/jbd2/checkpoint.c | OK | 8cf0c7ec22a |
| CVE-2024-49967 | CVE-2024-49967/4.4/0008.patch | fs/ext4/namei.c | SKIP | already present |
| CVE-2024-49975 | CVE-2024-49975/^6.11/0001.patch | kernel/events/uprobes.c | SKIP | not compiled |
| CVE-2024-49982 | CVE-2024-49982/4.4/0008.patch | drivers/block/aoe/aoecmd.c | SKIP | not compiled |
| CVE-2024-49995 | CVE-2024-49995/4.4/0008.patch | net/tipc/bearer.c | SKIP | not compiled |
| CVE-2024-50006 | CVE-2024-50006/4.4/0008.patch | fs/ext4/migrate.c | SKIP | already present |
| CVE-2024-50007 | CVE-2024-50007/4.4/0008.patch | sound/pci/asihpi/hpimsgx.c | SKIP | not compiled |
| CVE-2024-50035 | CVE-2024-50035/4.4/0008.patch | drivers/net/ppp/ppp_async.c | OK | 9718c1d0137 |
| CVE-2024-50040 | CVE-2024-50040/4.4/0008.patch | drivers/net/ethernet/intel/igb/igb_main.c | SKIP | not compiled |
| CVE-2024-50044 | CVE-2024-50044/4.4/0008.patch | net/bluetooth/rfcomm/sock.c | SKIP | not compiled |
| CVE-2024-50076 | CVE-2024-50076/4.4/0008.patch | drivers/tty/vt/vt.c | SKIP | not compiled |
| CVE-2024-50143 | CVE-2024-50143/^6.12/0001.patch | fs/udf/inode.c | SKIP | not compiled |
| CVE-2024-50148 | CVE-2024-50148/4.4/0008.patch | net/bluetooth/bnep/core.c | SKIP | not compiled |
| CVE-2024-50168 | CVE-2024-50168/4.4/0008.patch | drivers/net/ethernet/i825xx/sun3_82586.c | SKIP | not compiled |
| CVE-2024-50186 | CVE-2024-50186/^6.12/0001.patch | net/socket.c | OK | 9025f749574 |
| CVE-2024-50201 | CVE-2024-50201/^6.12/0001.patch | drivers/gpu/drm/radeon/radeon_encoders.c | SKIP | not compiled |
| CVE-2024-50218 | CVE-2024-50218/4.4/0008.patch | fs/ocfs2/file.c | SKIP | not compiled |
| CVE-2024-50230 | CVE-2024-50230/4.4/0008.patch | fs/nilfs2/page.c | SKIP | not compiled |
| CVE-2024-50234 | CVE-2024-50234/4.4/0008.patch | drivers/net/wireless/iwlegacy/common.c | SKIP | not compiled |
| CVE-2024-50265 | CVE-2024-50265/4.4/0008.patch | fs/ocfs2/xattr.c | SKIP | not compiled |
| CVE-2024-50267 | CVE-2024-50267/4.4/0008.patch | drivers/usb/serial/io_edgeport.c | SKIP | not compiled |
| CVE-2024-50290 | CVE-2024-50290/4.4/0008.patch | drivers/media/dvb-frontends/cx24116.c | SKIP | not compiled |
| CVE-2024-50299 | CVE-2024-50299/4.4/0008.patch | net/sctp/sm_statefuns.c | SKIP | not compiled |
| CVE-2024-53066 | CVE-2024-53066/4.4/0008.patch | fs/nfs/inode.c | SKIP | not compiled |
| CVE-2024-53101 | CVE-2024-53101/4.4/0008.patch | fs/ocfs2/file.c | SKIP | not compiled |
| CVE-2024-53104 | CVE-2024-53104/4.4/0008.patch | drivers/media/usb/uvc/uvc_driver.c | OK | bb3052c7115 |
| CVE-2022-20423 | CVE-2022-20423/3.4/0010.patch | drivers/usb/gadget/rndis.c | SKIP | not compiled |
| CVE-2023-52601 | CVE-2023-52601/4.4/0008.patch | fs/jfs/jfs_dmap.c | SKIP | not compiled |
| CVE-2024-27424 | CVE-2024-27424/4.4/0001.patch | net/netrom/af_netrom.c | SKIP | not compiled |
| CVE-2024-27425 | CVE-2024-27425/4.4/0001.patch | net/netrom/af_netrom.c | SKIP | not compiled |
- 10:47-11:00 boot-3.10.108-secB3 x1 and boot-3.10.108-secC (3.10.108-gbb3052c7115) x2: all USB OK (20 s), LTE OK (Spark NZ/LTE/IP), Wi-Fi on, cameraserver running, 0 oops. **secC is the current release candidate.**

## 2026-10-26 11:00 — FLASHED (owner approved): secC is now in LNX
- Backup first: `~/Downloads/nexus9/boot-backups/lnx-lineage16-20251224-3.10.103.img` (full 32 MiB LNX dump, sha256 4748dc9e...,
  verified on tablet and host; kernel 3.10.103 + ramdisk 961b8af0). Restore: `fastboot flash boot <that file>`.
- `fastboot flash boot ~/n9kernel/out/boot-3.10.108-secC.img` (sha256 3554259b...), LNX head verified to match.
- First boot from flash: adb 25 s, `3.10.108-gbb3052c7115`, boot_completed, Wi-Fi on, 0 oops, LTE Spark NZ / LTE / IP at 5 min.
