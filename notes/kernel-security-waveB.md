# Kernel security, Step 2 Wave B (Divest CVEs 2015-2021)

**Summary (plain):** Branch `n9-3.10.108-sec` in `~/n9kernel/kernel` now has 94 more
commits on top of Wave A (`09fe51e6f51` -> HEAD `bcaa06b1c42`). They are the Divest flounder-script
CVE patches from 2015-2021 that Wave A did not cover: mostly core kernel, mm, filesystems,
networking (ipv4/ipv6, xfrm, wireless, nfc), HID/input/USB drivers. 266 were skipped (257 for
code not built for flounder, 9 already in the tree) and 3 failed to apply. The kernel builds;
one new harmless warning. **Not boot-tested.**

- Image: `~/n9kernel/out/boot-3.10.108-secB.img` (9,029,632 bytes, sha256 `e9d16f635a2e0a86...`),
  uname `3.10.108-gbcaa06b1c42`. bootimg-split: page 2048, kernel 7,282,355, ramdisk `961b8af0`
  unchanged, ROM cmdline kept.
- Build log: `~/n9kernel/out/build-108-secB.log` (271 warnings vs 270 in Wave A).
  New one: `arch/arm64/kernel/process.c:178` `%pS` given `unsigned long`, from CVE-2021-39715
  (`bea0b856d64`); cosmetic only.
- Scripts and raw results: `/tmp/divkp/wb/{selB.py,run.sh,fn.py,b.sh,results.tsv,fn.txt}`.

## Method
- List = every `CVE-*` `git apply` line of `/tmp/n9kernelsurvey/divest_flounder.sh` with CVE year
  2015-2021, minus patch paths already in Wave A's `results.tsv`. 363 entries, in script order.
- Same rules as Wave A: no `.o` in `build-108` for any patched `.c` -> SKIP not compiled
  (includes the 7 header/asm/Kconfig-only patches, all x86/jfs/Kconfig); `git apply --check` -> apply,
  one commit each; `--check -R` -> SKIP already present; else FAIL. No hand-porting.
- Hunk check (`fn.py`): for each OK commit, the `@@` function context of every hunk in the
  patch must appear in `git show` of the commit, with the same hunk count. 84/94 matched exactly.
  The other 10 were read by hand:
  - CVE-2017-7533 (`dcache.h` context is a header heuristic), CVE-2017-18208 (`madvise_willneed`
    spacing), CVE-2018-3561 (`diagchar_ioctl` signature wraps), CVE-2018-9422 (git shows label
    `again:` inside `get_futex_key`), CVE-2019-15239 (`__tcp_retransmit_skb` / `tcp_connect_init`
    names differ in 3.10), CVE-2021-47416, CVE-2021-47518 (`nfc_genl_dump_devices_done`, correct
    function, context line differs): all landed in the intended function.
  - `drivers/net/phy/mdio_bus.c`: CVE-2021-47472 (3 patches) and CVE-2019-12819 add, remove, add,
    remove `put_device()` in `mdiobus_register`. Net result: no `put_device` there, plus 47416's
    `bus->state = MDIOBUS_UNREGISTERED`. That is the upstream end state (put_device would double-free
    via `mdiobus_free`). Kept as Divest orders them.
- Upstream-sha duplicate check against the base log (Wave A found one): no hits.

## FAILs (ranked by severity, not hand-ported)
1. **CVE-2020-29660** `drivers/tty/tty_io.c` ("tty: Fix ->session locking", TIOCGSID race / use-after-free reachable
   by any app via a pty). High: local, unprivileged. Best candidate for a hand-port.
2. **CVE-2017-2671** `net/ipv4/ping.c` ("ping: implement proper locking", disconnect/unhash race, use-after-free). Medium-high:
   ping sockets are reachable from apps on Android (`ping_group_range`). Patch is the `^4.11` variant;
   3.10 has an older ping.c layout.
3. **CVE-2016-20022** `drivers/usb/core/config.c` ("USB: validate wMaxPacketValue entries in endpoint descriptors"). Low-medium: needs a
   malicious USB device plugged in (physical access).

## Risks / open items
- Not boot-tested. Check the usual: USB/adb, LTE (USB2 modem, touches usb core and cdc/net
  patches), Wi-Fi (`net/wireless` cfg80211 patches), camera (uvc patches are USB webcam only),
  audio, `sys.boot_completed`.
- Areas with behaviour change on every boot: mm, futex, tcp, xfrm, cfg80211, fs.
- Wave C (2022-2024 outside Wave A areas) and Wave D (hardening) remain.

## Results
| CVE | Patch | First file | Result | Commit / reason | Hunk check |
|---|---|---|---|---|---|
| CVE-2015-1339 | CVE-2015-1339/^4.3/0001.patch | fs/fuse/cuse.c | SKIP | not compiled |  |
| CVE-2015-3290 | CVE-2015-3290/3.18/0005.patch | arch/x86/kernel/entry_64.S | SKIP | not compiled |  |
| CVE-2015-3290 | CVE-2015-3290/3.18/0006.patch | arch/x86/kernel/entry_64.S | SKIP | not compiled |  |
| CVE-2015-4177 | CVE-2015-4177/3.18/0002.patch | fs/namespace.c | OK | e7d5d976b06 | ok |
| CVE-2015-5307 | CVE-2015-5307/3.18/0002.patch | arch/x86/include/uapi/asm/svm.h | SKIP | not compiled |  |
| CVE-2015-6937 | CVE-2015-6937/3.10/0002.patch | net/rds/connection.c | SKIP | not compiled |  |
| CVE-2015-7513 | CVE-2015-7513/3.18/0002.patch | arch/x86/kvm/x86.c | SKIP | not compiled |  |
| CVE-2015-7515 | CVE-2015-7515/^4.3/0002.patch | drivers/input/tablet/aiptek.c | OK | d9f56428922 | ok |
| CVE-2015-8215 | CVE-2015-8215/ANY/0001.patch | net/ipv6/addrconf.c | OK | d658b561daf | ok |
| CVE-2015-8551 | CVE-2015-8551/3.10/0006.patch | drivers/xen/xen-pciback/pciback_ops.c | SKIP | not compiled |  |
| CVE-2015-8551 | CVE-2015-8551/3.10/0007.patch | drivers/xen/xen-pciback/pciback_ops.c | SKIP | not compiled |  |
| CVE-2015-8551 | CVE-2015-8551/3.10/0008.patch | drivers/xen/xen-pciback/pciback_ops.c | SKIP | not compiled |  |
| CVE-2015-8551 | CVE-2015-8551/3.10/0009.patch | drivers/xen/xen-pciback/pciback_ops.c | SKIP | not compiled |  |
| CVE-2015-8551 | CVE-2015-8551/3.10/0010.patch | drivers/xen/xen-pciback/pciback_ops.c | SKIP | not compiled |  |
| CVE-2015-8553 | CVE-2015-8553/4.4/0004.patch | drivers/xen/xen-pciback/pciback_ops.c | SKIP | not compiled |  |
| CVE-2015-8746 | CVE-2015-8746/3.18/0002.patch | fs/nfs/nfs4proc.c | SKIP | not compiled |  |
| CVE-2015-8944 | CVE-2015-8944/ANY/0001.patch | kernel/resource.c | OK | 81dbbfef858 | ok |
| CVE-2015-8955 | CVE-2015-8955/3.18/0002.patch | arch/arm64/kernel/perf_event.c | OK | cdb27ecc305 | ok |
| CVE-2015-8962 | CVE-2015-8962/3.10/0002.patch | drivers/scsi/sg.c | SKIP | not compiled |  |
| CVE-2015-8970 | CVE-2015-8970/3.10/0002.patch | crypto/algif_skcipher.c | SKIP | not compiled |  |
| CVE-2016-2085 | CVE-2016-2085/3.10/0002.patch | security/integrity/evm/evm_main.c | SKIP | not compiled |  |
| CVE-2016-2188 | CVE-2016-2188/3.10/0003.patch | drivers/usb/misc/iowarrior.c | SKIP | not compiled |  |
| CVE-2016-2188 | CVE-2016-2188/3.10/0004.patch | drivers/usb/misc/iowarrior.c | SKIP | not compiled |  |
| CVE-2016-3961 | CVE-2016-3961/3.10/0002.patch | arch/x86/include/asm/hugetlb.h | SKIP | not compiled |  |
| CVE-2016-5244 | CVE-2016-5244/3.18/0005.patch | net/rds/recv.c | SKIP | not compiled |  |
| CVE-2016-6327 | CVE-2016-6327/3.18/0002.patch | drivers/infiniband/ulp/srpt/ib_srpt.c | SKIP | not compiled |  |
| CVE-2016-6480 | CVE-2016-6480/3.10/0002.patch | drivers/scsi/aacraid/commctrl.c | SKIP | not compiled |  |
| CVE-2016-7117 | CVE-2016-7117/^3.10/0002.patch | net/socket.c | SKIP | already present |  |
| CVE-2016-7425 | CVE-2016-7425/3.10/0002.patch | drivers/scsi/arcmsr/arcmsr_hba.c | SKIP | not compiled |  |
| CVE-2016-8453 | CVE-2016-8453/ANY/0001.patch | drivers/net/wireless/bcmdhd/dhd_pcie.c | SKIP | not compiled |  |
| CVE-2016-8464 | CVE-2016-8464/3.10/0001.patch | drivers/net/wireless/bcmdhd/wl_android.c | OK | b4d0d403603 | ok |
| CVE-2016-8633 | CVE-2016-8633/3.10/0002.patch | drivers/firewire/net.c | SKIP | not compiled |  |
| CVE-2016-8645 | CVE-2016-8645/3.10/0002.patch | include/linux/filter.h | SKIP | already present |  |
| CVE-2016-8650 | CVE-2016-8650/3.10/0003.patch | lib/mpi/mpi-pow.c | SKIP | not compiled |  |
| CVE-2016-8658 | CVE-2016-8658/3.10/0002.patch | drivers/net/wireless/brcm80211/brcmfmac/wl_cfg80211.c | SKIP | not compiled |  |
| CVE-2016-9083 | CVE-2016-9083/3.10/0002.patch | drivers/vfio/pci/vfio_pci.c | SKIP | not compiled |  |
| CVE-2016-9178 | CVE-2016-9178/3.10/0002.patch | arch/x86/include/asm/uaccess.h | SKIP | not compiled |  |
| CVE-2016-9555 | CVE-2016-9555/3.10/0002.patch | net/sctp/sm_statefuns.c | SKIP | not compiled |  |
| CVE-2016-9576 | CVE-2016-9576/3.10/0002.patch | block/bsg.c | SKIP | not compiled |  |
| CVE-2016-9576 | CVE-2016-9576/3.10/0003.patch | fs/open.c | OK | 08963112330 | ok |
| CVE-2016-9588 | CVE-2016-9588/3.10/0002.patch | arch/x86/kvm/vmx.c | SKIP | not compiled |  |
| CVE-2016-10153 | CVE-2016-10153/3.4/0003.patch | net/ceph/crypto.c | SKIP | not compiled |  |
| CVE-2016-10741 | CVE-2016-10741/3.18/0005.patch | fs/xfs/xfs_aops.c | SKIP | not compiled |  |
| CVE-2016-20022 | CVE-2016-20022/3.10/0003.patch | drivers/usb/core/config.c | FAIL | patch does not apply |  |
| CVE-2017-16USB | CVE-2017-16USB/^4.10/0005.patch | drivers/usb/core/config.c | SKIP | already present |  |
| CVE-2017-0449 | CVE-2017-0449/ANY/0001.patch | drivers/net/wireless/bcmdhd/dhd_pcie.c | SKIP | not compiled |  |
| CVE-2017-0627 | CVE-2017-0627/3.18/0005.patch | drivers/media/usb/uvc/uvc_ctrl.c | OK | 6d0079c0b41 | ok |
| CVE-2017-2583 | CVE-2017-2583/3.10/0002.patch | arch/x86/kvm/emulate.c | SKIP | not compiled |  |
| CVE-2017-2584 | CVE-2017-2584/3.10/0002.patch | arch/x86/kvm/emulate.c | SKIP | not compiled |  |
| CVE-2017-2671 | CVE-2017-2671/^4.11/0001.patch | net/ipv4/ping.c | FAIL | patch does not apply |  |
| CVE-2017-5549 | CVE-2017-5549/3.10/0002.patch | drivers/usb/serial/kl5kusb105.c | SKIP | not compiled |  |
| CVE-2017-5669 | CVE-2017-5669/3.10/0002.patch | ipc/shm.c | SKIP | not compiled |  |
| CVE-2017-5972 | CVE-2017-5972/3.10/0002.patch | net/ipv4/tcp_minisocks.c | OK | e19b8d28cef | ok |
| CVE-2017-5986 | CVE-2017-5986/3.10/0002.patch | net/sctp/socket.c | SKIP | not compiled |  |
| CVE-2017-6345 | CVE-2017-6345/3.18/0004.patch | net/llc/llc_conn.c | SKIP | not compiled |  |
| CVE-2017-6348 | CVE-2017-6348/3.10/0002.patch | net/irda/irqueue.c | SKIP | not compiled |  |
| CVE-2017-6353 | CVE-2017-6353/3.10/0002.patch | net/sctp/socket.c | SKIP | not compiled |  |
| CVE-2017-7261 | CVE-2017-7261/3.10/0002.patch | drivers/gpu/drm/vmwgfx/vmwgfx_surface.c | SKIP | not compiled |  |
| CVE-2017-7273 | CVE-2017-7273/3.10/0002.patch | drivers/hid/hid-cypress.c | SKIP | already present |  |
| CVE-2017-7294 | CVE-2017-7294/3.10/0002.patch | drivers/gpu/drm/vmwgfx/vmwgfx_surface.c | SKIP | not compiled |  |
| CVE-2017-7482 | CVE-2017-7482/3.10/0002.patch | net/rxrpc/ar-key.c | SKIP | not compiled |  |
| CVE-2017-7533 | CVE-2017-7533/3.10/0002.patch | fs/dcache.c | OK | 93894e7588c | reviewed, see below |
| CVE-2017-7533 | CVE-2017-7533/3.10/0003.patch | fs/namei.c | OK | 7abb018b646 | ok |
| CVE-2017-7645 | CVE-2017-7645/3.10/0002.patch | fs/nfsd/nfssvc.c | SKIP | not compiled |  |
| CVE-2017-8067 | CVE-2017-8067/3.10/0002.patch | drivers/char/virtio_console.c | SKIP | not compiled |  |
| CVE-2017-8068 | CVE-2017-8068/3.10/0002.patch | drivers/net/usb/pegasus.c | SKIP | not compiled |  |
| CVE-2017-8069 | CVE-2017-8069/3.10/0002.patch | drivers/net/usb/rtl8150.c | SKIP | not compiled |  |
| CVE-2017-8824 | CVE-2017-8824/3.10/0009.patch | net/dccp/proto.c | SKIP | not compiled |  |
| CVE-2017-8924 | CVE-2017-8924/3.10/0002.patch | drivers/usb/serial/io_ti.c | SKIP | not compiled |  |
| CVE-2017-8925 | CVE-2017-8925/3.10/0002.patch | drivers/usb/serial/omninet.c | SKIP | not compiled |  |
| CVE-2017-9242 | CVE-2017-9242/3.18/0003.patch | net/ipv6/ip6_output.c | OK | 2b401494e63 | ok |
| CVE-2017-10911 | CVE-2017-10911/3.18/0007.patch | drivers/block/xen-blkback/blkback.c | SKIP | not compiled |  |
| CVE-2017-10996 | CVE-2017-10996/ANY/0001.patch | arch/arm64/kernel/setup.c | OK | a1927d61592 | ok |
| CVE-2017-11089 | CVE-2017-11089/3.18/0003.patch | net/wireless/nl80211.c | OK | 550c029208e | ok |
| CVE-2017-11090 | CVE-2017-11090/ANY/0001.patch | net/wireless/nl80211.c | SKIP | already present |  |
| CVE-2017-11176 | CVE-2017-11176/3.18/0003.patch | ipc/mqueue.c | SKIP | not compiled |  |
| CVE-2017-11600 | CVE-2017-11600/3.10/0002.patch | net/xfrm/xfrm_policy.c | SKIP | already present |  |
| CVE-2017-12153 | CVE-2017-12153/3.10/0002.patch | net/wireless/nl80211.c | SKIP | already present |  |
| CVE-2017-12762 | CVE-2017-12762/3.18/0002.patch | drivers/isdn/i4l/isdn_common.c | SKIP | not compiled |  |
| CVE-2017-13168 | CVE-2017-13168/3.10/0002.patch | drivers/scsi/sg.c | SKIP | not compiled |  |
| CVE-2017-13215 | CVE-2017-13215/3.10/0003.patch | crypto/algif_skcipher.c | SKIP | not compiled |  |
| CVE-2017-13292 | CVE-2017-13292/ANY/0001.patch | drivers/net/wireless/bcmdhd/wl_cfg80211.c | OK | 32933181826 | ok |
| CVE-2017-13694 | CVE-2017-13694/^4.12.9/0001.patch | drivers/acpi/acpica/psobject.c | SKIP | not compiled |  |
| CVE-2017-13695 | CVE-2017-13695/3.18/0002.patch | drivers/acpi/acpica/nseval.c | SKIP | not compiled |  |
| CVE-2017-14051 | CVE-2017-14051/3.10/0002.patch | drivers/scsi/qla2xxx/qla_attr.c | SKIP | not compiled |  |
| CVE-2017-14106 | CVE-2017-14106/3.10/0002.patch | net/ipv4/tcp.c | SKIP | already present |  |
| CVE-2017-14489 | CVE-2017-14489/3.18/0003.patch | drivers/scsi/scsi_transport_iscsi.c | SKIP | not compiled |  |
| CVE-2017-15102 | CVE-2017-15102/3.10/0002.patch | drivers/usb/misc/legousbtower.c | SKIP | not compiled |  |
| CVE-2017-15121 | CVE-2017-15121/^3.10/0001.patch | mm/truncate.c | OK | 72d96d7749a | ok |
| CVE-2017-15837 | CVE-2017-15837/ANY/0002.patch | net/wireless/nl80211.c | OK | fe3c90aea3b | ok |
| CVE-2017-15868 | CVE-2017-15868/3.10/0003.patch | net/bluetooth/bnep/core.c | SKIP | not compiled |  |
| CVE-2017-15868 | CVE-2017-15868/3.10/0005.patch | net/bluetooth/cmtp/core.c | SKIP | not compiled |  |
| CVE-2017-16526 | CVE-2017-16526/3.18/0003.patch | drivers/uwb/uwbd.c | SKIP | not compiled |  |
| CVE-2017-16532 | CVE-2017-16532/3.18/0003.patch | drivers/usb/misc/usbtest.c | SKIP | not compiled |  |
| CVE-2017-16534 | CVE-2017-16534/3.10/0006.patch | drivers/net/usb/cdc-phonet.c | OK | 1c00e3a46d1 | ok |
| CVE-2017-16537 | CVE-2017-16537/3.18/0003.patch | drivers/media/rc/imon.c | SKIP | not compiled |  |
| CVE-2017-16538 | CVE-2017-16538/3.18/0005.patch | drivers/media/usb/dvb-usb-v2/lmedm04.c | SKIP | not compiled |  |
| CVE-2017-16538 | CVE-2017-16538/3.18/0006.patch | drivers/media/usb/dvb-usb-v2/lmedm04.c | SKIP | not compiled |  |
| CVE-2017-16643 | CVE-2017-16643/3.5-^4.13.11/0001.patch | drivers/input/tablet/gtco.c | OK | 503c93045da | ok |
| CVE-2017-16644 | CVE-2017-16644/3.18/0005.patch | drivers/media/usb/hdpvr/hdpvr-core.c | SKIP | not compiled |  |
| CVE-2017-16645 | CVE-2017-16645/3.18/0003.patch | drivers/input/misc/ims-pcu.c | SKIP | not compiled |  |
| CVE-2017-16650 | CVE-2017-16650/3.18/0006.patch | drivers/net/usb/qmi_wwan.c | SKIP | not compiled |  |
| CVE-2017-16994 | CVE-2017-16994/3.18/0006.patch | mm/pagewalk.c | OK | 1056793d975 | ok |
| CVE-2017-17558 | CVE-2017-17558/3.18/0004.patch | drivers/usb/core/config.c | OK | 3a3c38e24fd | ok |
| CVE-2017-17712 | CVE-2017-17712/3.10/0010.patch | net/ipv4/raw.c | OK | 67b2bd35810 | ok |
| CVE-2017-17805 | CVE-2017-17805/3.18/0003.patch | arch/x86/crypto/salsa20_glue.c | SKIP | not compiled |  |
| CVE-2017-18079 | CVE-2017-18079/3.18/0003.patch | drivers/input/serio/i8042.c | SKIP | not compiled |  |
| CVE-2017-18203 | CVE-2017-18203/3.18/0002.patch | drivers/md/dm.c | OK | 2cdc8bf2eca | ok |
| CVE-2017-18208 | CVE-2017-18208/3.18/0002.patch | mm/madvise.c | OK | 8c5510e0b38 | reviewed, see below |
| CVE-2017-18216 | CVE-2017-18216/3.18/0007.patch | fs/ocfs2/cluster/nodemanager.c | SKIP | not compiled |  |
| CVE-2017-18255 | CVE-2017-18255/3.18/0002.patch | kernel/events/core.c | OK | bb09d5a2f09 | ok |
| CVE-2017-18360 | CVE-2017-18360/3.18/0002.patch | drivers/usb/serial/io_ti.c | SKIP | not compiled |  |
| CVE-2017-18509 | CVE-2017-18509/3.18/0003.patch | net/ipv6/ip6mr.c | SKIP | not compiled |  |
| CVE-2017-18551 | CVE-2017-18551/3.18/0002.patch | drivers/i2c/i2c-core.c | OK | 419dc991011 | ok |
| CVE-2017-18595 | CVE-2017-18595/3.18/0002.patch | kernel/trace/trace.c | OK | 083804ade72 | ok |
| CVE-2017-1000252 | CVE-2017-1000252/^4.13/0002.patch | virt/kvm/eventfd.c | SKIP | not compiled |  |
| CVE-2017-1000365 | CVE-2017-1000365/3.10/0003.patch | fs/exec.c | SKIP | already present |  |
| CVE-2017-1000410 | CVE-2017-1000410/3.10/0008.patch | net/bluetooth/l2cap_core.c | SKIP | not compiled |  |
| CVE-2018-1130 | CVE-2018-1130/3.18/0003.patch | net/dccp/proto.c | SKIP | not compiled |  |
| CVE-2018-3561 | CVE-2018-3561/3.4/0002.patch | drivers/char/diag/diagchar_core.c | OK | e840082c048 | reviewed, see below |
| CVE-2018-3584 | CVE-2018-3584/ANY/0001.patch | drivers/net/usb/rmnet_usb_ctrl.c | OK | 0f0c3691b6f | ok |
| CVE-2018-5332 | CVE-2018-5332/3.18/0003.patch | net/rds/rdma.c | SKIP | not compiled |  |
| CVE-2018-5333 | CVE-2018-5333/3.18/0003.patch | net/rds/rdma.c | SKIP | not compiled |  |
| CVE-2018-5750 | CVE-2018-5750/3.18/0003.patch | drivers/acpi/sbshc.c | SKIP | not compiled |  |
| CVE-2018-5803 | CVE-2018-5803/3.10/0010.patch | net/sctp/sm_make_chunk.c | SKIP | not compiled |  |
| CVE-2018-7492 | CVE-2018-7492/3.18/0002.patch | net/rds/rdma.c | SKIP | not compiled |  |
| CVE-2018-7755 | CVE-2018-7755/3.18/0003.patch | drivers/block/floppy.c | SKIP | not compiled |  |
| CVE-2018-7757 | CVE-2018-7757/3.18/0003.patch | drivers/scsi/libsas/sas_expander.c | SKIP | not compiled |  |
| CVE-2018-8781 | CVE-2018-8781/3.18/0002.patch | drivers/gpu/drm/udl/udl_fb.c | SKIP | not compiled |  |
| CVE-2018-8822 | CVE-2018-8822/3.18/0002.patch | fs/ncpfs/ncplib_kernel.c | SKIP | not compiled |  |
| CVE-2018-9422 | CVE-2018-9422/4.4/0007.patch | kernel/futex.c | OK | 7b9ad5ed5e8 | ok |
| CVE-2018-9422 | CVE-2018-9422/4.4/0008.patch | kernel/futex.c | OK | 1bc6554ba15 | reviewed, see below |
| CVE-2018-9516 | CVE-2018-9516/3.18/0003.patch | drivers/hid/hid-debug.c | OK | 7c24c649a5e | ok |
| CVE-2018-10021 | CVE-2018-10021/3.18/0003.patch | drivers/scsi/libsas/sas_scsi_host.c | SKIP | not compiled |  |
| CVE-2018-10087 | CVE-2018-10087/3.18/0002.patch | kernel/exit.c | OK | 9b5d637acd8 | ok |
| CVE-2018-10124 | CVE-2018-10124/3.18/0002.patch | kernel/signal.c | OK | c5fbbaa6b4b | ok |
| CVE-2018-10675 | CVE-2018-10675/3.18/0003.patch | mm/mempolicy.c | SKIP | not compiled |  |
| CVE-2018-10883 | CVE-2018-10883/3.18/0006.patch | fs/jbd2/transaction.c | OK | e220d39effe | ok |
| CVE-2018-10940 | CVE-2018-10940/3.18/0003.patch | drivers/cdrom/cdrom.c | OK | d821c7ed711 | ok |
| CVE-2018-11506 | CVE-2018-11506/3.18/0003.patch | drivers/scsi/sr_ioctl.c | OK | 078bb94886f | ok |
| CVE-2018-11939 | CVE-2018-11939/ANY/0002.patch | net/wireless/util.c | OK | 1caa5a0f535 | ok |
| CVE-2018-12232 | CVE-2018-12232/3.10/0004.patch | net/socket.c | OK | 681f069204f | ok |
| CVE-2018-12233 | CVE-2018-12233/3.18/0003.patch | fs/jfs/xattr.c | SKIP | not compiled |  |
| CVE-2018-13053 | CVE-2018-13053/3.10/0008.patch | kernel/time/alarmtimer.c | OK | 3f78f23e4db | ok |
| CVE-2018-13405 | CVE-2018-13405/3.10/0007.patch | fs/inode.c | OK | bf378d75922 | ok |
| CVE-2018-14634 | CVE-2018-14634/3.10/0002.patch | fs/exec.c | OK | 3c547fbfa47 | ok |
| CVE-2018-14734 | CVE-2018-14734/3.18/0003.patch | drivers/infiniband/core/ucma.c | SKIP | not compiled |  |
| CVE-2018-15594 | CVE-2018-15594/3.18/0005.patch | arch/x86/kernel/paravirt.c | SKIP | not compiled |  |
| CVE-2018-16276 | CVE-2018-16276/3.18/0003.patch | drivers/usb/misc/yurex.c | SKIP | not compiled |  |
| CVE-2018-16658 | CVE-2018-16658/3.18/0002.patch | drivers/cdrom/cdrom.c | OK | f29cb601f39 | ok |
| CVE-2018-18710 | CVE-2018-18710/3.18/0003.patch | drivers/cdrom/cdrom.c | OK | bdd3083b384 | ok |
| CVE-2018-20511 | CVE-2018-20511/3.18/0004.patch | drivers/net/appletalk/ipddp.c | SKIP | not compiled |  |
| CVE-2018-20836 | CVE-2018-20836/3.18/0003.patch | drivers/scsi/libsas/sas_expander.c | SKIP | not compiled |  |
| CVE-2018-1000204 | CVE-2018-1000204/3.18/0004.patch | drivers/scsi/sg.c | SKIP | not compiled |  |
| CVE-2019-2001 | CVE-2019-2001/^3.10/0002.patch | kernel/resource.c | OK | c2445457901 | ok |
| CVE-2019-2054 | CVE-2019-2054/ANY/0003.patch | arch/x86/syscalls/syscalltbl.sh | SKIP | not compiled |  |
| CVE-2019-2101 | CVE-2019-2101/3.10/0009.patch | drivers/media/usb/uvc/uvc_driver.c | OK | 360609f38c6 | ok |
| CVE-2019-3459 | CVE-2019-3459/3.10/0009.patch | net/bluetooth/l2cap_core.c | SKIP | not compiled |  |
| CVE-2019-3460 | CVE-2019-3460/3.10/0009.patch | net/bluetooth/l2cap_core.c | SKIP | not compiled |  |
| CVE-2019-3701 | CVE-2019-3701/3.18/0003.patch | net/can/gw.c | SKIP | not compiled |  |
| CVE-2019-3819 | CVE-2019-3819/3.18/0003.patch | drivers/hid/hid-debug.c | OK | 158fdffa2f2 | ok |
| CVE-2019-3846 | CVE-2019-3846/3.18/0005.patch | drivers/net/wireless/mwifiex/scan.c | SKIP | not compiled |  |
| CVE-2019-7222 | CVE-2019-7222/3.18/0003.patch | arch/x86/kvm/x86.c | SKIP | not compiled |  |
| CVE-2019-8912 | CVE-2019-8912/3.10/0006.patch | crypto/af_alg.c | SKIP | not compiled |  |
| CVE-2019-9213 | CVE-2019-9213/3.18/0003.patch | mm/mmap.c | OK | abd105b6722 | ok |
| CVE-2019-10142 | CVE-2019-10142/3.18/0003.patch | drivers/virt/fsl_hypervisor.c | SKIP | not compiled |  |
| CVE-2019-10607 | CVE-2019-10607/ANY/0001.patch | security/selinux/ss/services.c | OK | dc8cbec32fa | ok |
| CVE-2019-10638 | CVE-2019-10638/3.18/0005.patch | include/net/net_namespace.h | OK | 6f630f7a5b8 | ok |
| CVE-2019-11477 | CVE-2019-11477/3.10/0003.patch | include/linux/tcp.h | OK | c4127d22444 | ok |
| CVE-2019-11478 | CVE-2019-11478/3.10/0003.patch | include/uapi/linux/snmp.h | OK | af7c652ec10 | ok |
| CVE-2019-11478 | CVE-2019-11478/3.10/0004.patch | net/ipv4/tcp_output.c | OK | 78290253900 | ok |
| CVE-2019-11479 | CVE-2019-11479/3.10/0005.patch | Documentation/networking/ip-sysctl.txt | OK | 558f2defb09 | ok |
| CVE-2019-11479 | CVE-2019-11479/3.10/0006.patch | net/ipv4/tcp_timer.c | OK | e1ba9992961 | ok |
| CVE-2019-11486 | CVE-2019-11486/3.18/0003.patch | drivers/char/Kconfig | SKIP | not compiled |  |
| CVE-2019-11810 | CVE-2019-11810/3.18/0003.patch | drivers/scsi/megaraid/megaraid_sas_base.c | SKIP | not compiled |  |
| CVE-2019-11884 | CVE-2019-11884/3.10/0009.patch | net/bluetooth/hidp/sock.c | SKIP | not compiled |  |
| CVE-2019-12456 | CVE-2019-12456/^5.1.5/0002.patch | drivers/scsi/mpt3sas/mpt3sas_ctl.c | SKIP | not compiled |  |
| CVE-2019-13631 | CVE-2019-13631/3.18/0003.patch | drivers/input/tablet/gtco.c | OK | 447742a9adb | ok |
| CVE-2019-13648 | CVE-2019-13648/3.18/0003.patch | arch/powerpc/kernel/signal_32.c | SKIP | not compiled |  |
| CVE-2019-14053 | CVE-2019-14053/3.4/0003.patch | net/xfrm/xfrm_user.c | OK | 3650c59005e | ok |
| CVE-2019-14284 | CVE-2019-14284/3.18/0005.patch | drivers/block/floppy.c | SKIP | not compiled |  |
| CVE-2019-14814 | CVE-2019-14814/3.18/0003.patch | drivers/net/wireless/mwifiex/ie.c | SKIP | not compiled |  |
| CVE-2019-14821 | CVE-2019-14821/3.18/0004.patch | virt/kvm/coalesced_mmio.c | SKIP | not compiled |  |
| CVE-2019-14835 | CVE-2019-14835/3.18/0003.patch | drivers/vhost/vhost.c | SKIP | not compiled |  |
| CVE-2019-14896 | CVE-2019-14896/3.18/0003.patch | drivers/net/wireless/libertas/cfg.c | SKIP | not compiled |  |
| CVE-2019-15098 | CVE-2019-15098/3.18/0003.patch | drivers/net/wireless/ath/ath6kl/usb.c | SKIP | not compiled |  |
| CVE-2019-15212 | CVE-2019-15212/3.18/0004.patch | drivers/usb/misc/rio500.c | SKIP | not compiled |  |
| CVE-2019-15213 | CVE-2019-15213/3.18/0007.patch | drivers/media/usb/dvb-usb/dvb-usb-init.c | SKIP | not compiled |  |
| CVE-2019-15215 | CVE-2019-15215/3.18/0003.patch | drivers/media/usb/cpia2/cpia2_usb.c | SKIP | not compiled |  |
| CVE-2019-15216 | CVE-2019-15216/3.18/0003.patch | drivers/usb/misc/yurex.c | SKIP | not compiled |  |
| CVE-2019-15217 | CVE-2019-15217/3.18/0003.patch | drivers/media/usb/zr364xx/zr364xx.c | SKIP | not compiled |  |
| CVE-2019-15218 | CVE-2019-15218/3.18/0003.patch | drivers/media/usb/siano/smsusb.c | SKIP | not compiled |  |
| CVE-2019-15219 | CVE-2019-15219/3.18/0003.patch | drivers/usb/misc/sisusbvga/sisusb.c | SKIP | not compiled |  |
| CVE-2019-15239 | CVE-2019-15239/3.4/0002.patch | net/ipv4/tcp_output.c | OK | 90d6a42eeab | reviewed, see below |
| CVE-2019-15291 | CVE-2019-15291/3.18/0003.patch | drivers/media/usb/b2c2/flexcop-usb.c | SKIP | not compiled |  |
| CVE-2019-15292 | CVE-2019-15292/3.18/0003.patch | include/linux/atalk.h | SKIP | not compiled |  |
| CVE-2019-15505 | CVE-2019-15505/3.18/0004.patch | drivers/media/usb/dvb-usb/technisat-usb2.c | SKIP | not compiled |  |
| CVE-2019-15807 | CVE-2019-15807/3.18/0003.patch | drivers/scsi/libsas/sas_expander.c | SKIP | not compiled |  |
| CVE-2019-15926 | CVE-2019-15926/3.18/0004.patch | drivers/net/wireless/ath/ath6kl/wmi.c | SKIP | not compiled |  |
| CVE-2019-16232 | CVE-2019-16232/3.18/0007.patch | drivers/net/wireless/libertas/if_sdio.c | SKIP | not compiled |  |
| CVE-2019-16233 | CVE-2019-16233/3.18/0002.patch | drivers/scsi/qla2xxx/qla_os.c | SKIP | not compiled |  |
| CVE-2019-17052 | CVE-2019-17052/3.18/0008.patch | net/ax25/af_ax25.c | SKIP | not compiled |  |
| CVE-2019-17053 | CVE-2019-17053/3.18/0003.patch | net/ieee802154/af_ieee802154.c | SKIP | not compiled |  |
| CVE-2019-17054 | CVE-2019-17054/3.18/0003.patch | net/appletalk/ddp.c | SKIP | not compiled |  |
| CVE-2019-17055 | CVE-2019-17055/3.18/0003.patch | drivers/isdn/mISDN/socket.c | SKIP | not compiled |  |
| CVE-2019-17056 | CVE-2019-17056/3.18/0003.patch | net/nfc/llcp_sock.c | OK | bd12390018f | ok |
| CVE-2019-17133 | CVE-2019-17133/3.18/0004.patch | net/wireless/wext-sme.c | SKIP | not compiled |  |
| CVE-2019-17666 | CVE-2019-17666/3.18/0003.patch | drivers/net/wireless/rtlwifi/ps.c | SKIP | not compiled |  |
| CVE-2019-18806 | CVE-2019-18806/3.18/0003.patch | drivers/net/ethernet/qlogic/qla3xxx.c | SKIP | not compiled |  |
| CVE-2019-19051 | CVE-2019-19051/3.18/0006.patch | drivers/net/wimax/i2400m/op-rfkill.c | SKIP | not compiled |  |
| CVE-2019-19051 | CVE-2019-19051/4.4/0011.patch | drivers/net/wimax/i2400m/op-rfkill.c | SKIP | not compiled |  |
| CVE-2019-19051 | CVE-2019-19051/4.4/0012.patch | drivers/net/wimax/i2400m/op-rfkill.c | SKIP | not compiled |  |
| CVE-2019-19056 | CVE-2019-19056/3.18/0003.patch | drivers/net/wireless/mwifiex/pcie.c | SKIP | not compiled |  |
| CVE-2019-19060 | CVE-2019-19060/3.18/0006.patch | drivers/iio/imu/adis_buffer.c | SKIP | not compiled |  |
| CVE-2019-19062 | CVE-2019-19062/3.18/0003.patch | crypto/crypto_user.c | SKIP | not compiled |  |
| CVE-2019-19063 | CVE-2019-19063/3.18/0002.patch | drivers/net/wireless/rtlwifi/usb.c | SKIP | not compiled |  |
| CVE-2019-19066 | CVE-2019-19066/3.18/0003.patch | drivers/scsi/bfa/bfad_attr.c | SKIP | not compiled |  |
| CVE-2019-19073 | CVE-2019-19073/3.18/0002.patch | drivers/net/wireless/ath/ath9k/htc_hst.c | SKIP | not compiled |  |
| CVE-2019-19074 | CVE-2019-19074/3.18/0002.patch | drivers/net/wireless/ath/ath9k/wmi.c | SKIP | not compiled |  |
| CVE-2019-19227 | CVE-2019-19227/3.18/0003.patch | include/linux/atalk.h | SKIP | not compiled |  |
| CVE-2019-19448 | CVE-2019-19448/3.18/0002.patch | fs/btrfs/free-space-cache.c | SKIP | not compiled |  |
| CVE-2019-19524 | CVE-2019-19524/3.10/0009.patch | drivers/input/ff-memless.c | OK | 5239724352f | ok |
| CVE-2019-19527 | CVE-2019-19527/3.18/0007.patch | drivers/hid/usbhid/hiddev.c | OK | 66bc5e6572d | ok |
| CVE-2019-19527 | CVE-2019-19527/3.18/0008.patch | drivers/hid/usbhid/hiddev.c | OK | 3cf30f3f23b | ok |
| CVE-2019-19528 | CVE-2019-19528/^5.3/0001.patch | drivers/usb/misc/iowarrior.c | SKIP | not compiled |  |
| CVE-2019-19528 | CVE-2019-19528/^5.4/0002.patch | drivers/usb/misc/iowarrior.c | SKIP | not compiled |  |
| CVE-2019-19530 | CVE-2019-19530/3.18/0003.patch | drivers/usb/class/cdc-acm.c | OK | bd1922233f5 | ok |
| CVE-2019-19531 | CVE-2019-19531/3.18/0003.patch | drivers/usb/misc/yurex.c | SKIP | not compiled |  |
| CVE-2019-19533 | CVE-2019-19533/3.18/0003.patch | drivers/media/usb/ttusb-dec/ttusb_dec.c | SKIP | not compiled |  |
| CVE-2019-19534 | CVE-2019-19534/3.18/0003.patch | drivers/net/can/usb/peak_usb/pcan_usb_core.c | SKIP | not compiled |  |
| CVE-2019-19536 | CVE-2019-19536/3.18/0003.patch | drivers/net/can/usb/peak_usb/pcan_usb_pro.c | SKIP | not compiled |  |
| CVE-2019-19537 | CVE-2019-19537/3.18/0004.patch | drivers/usb/core/file.c | OK | 8857991e0fb | ok |
| CVE-2019-19947 | CVE-2019-19947/3.18/0003.patch | drivers/net/can/usb/kvaser_usb.c | SKIP | not compiled |  |
| CVE-2019-19965 | CVE-2019-19965/3.18/0003.patch | drivers/scsi/libsas/sas_discover.c | SKIP | not compiled |  |
| CVE-2019-19966 | CVE-2019-19966/3.18/0003.patch | drivers/media/usb/cpia2/cpia2_v4l.c | SKIP | not compiled |  |
| CVE-2019-20054 | CVE-2019-20054/3.18/0005.patch | fs/proc/proc_sysctl.c | OK | e95dddb1caf | ok |
| CVE-2019-20054 | CVE-2019-20054/3.18/0006.patch | fs/proc/proc_sysctl.c | OK | 5a07ab7dbbe | ok |
| CVE-2019-20096 | CVE-2019-20096/3.18/0003.patch | net/dccp/feat.c | SKIP | not compiled |  |
| CVE-2019-20636 | CVE-2019-20636/3.18/0004.patch | drivers/input/input.c | OK | 2ba3f8bc718 | ok |
| CVE-2019-25160 | CVE-2019-25160/3.18/0002.patch | net/ipv4/cipso_ipv4.c | SKIP | not compiled |  |
| CVE-2020-0404 | CVE-2020-0404/3.18/0003.patch | drivers/media/usb/uvc/uvc_driver.c | OK | 2c3cd59bfc6 | ok |
| CVE-2020-0429 | CVE-2020-0429/3.18/0001.patch | net/l2tp/l2tp_core.c | SKIP | not compiled |  |
| CVE-2020-0431 | CVE-2020-0431/4.4/0005.patch | drivers/hid/hid-input.c | OK | cec82c058a6 | ok |
| CVE-2020-0465 | CVE-2020-0465/3.18/0003.patch | drivers/hid/hid-input.c | OK | 16008c77f07 | ok |
| CVE-2020-8647 | CVE-2020-8647/3.18/0004.patch | drivers/video/console/vgacon.c | SKIP | not compiled |  |
| CVE-2020-9383 | CVE-2020-9383/3.18/0003.patch | drivers/block/floppy.c | SKIP | not compiled |  |
| CVE-2020-10773 | CVE-2020-10773/4.4/0005.patch | arch/s390/mm/cmm.c | SKIP | not compiled |  |
| CVE-2020-10942 | CVE-2020-10942/3.18/0003.patch | drivers/vhost/net.c | SKIP | not compiled |  |
| CVE-2020-11565 | CVE-2020-11565/3.18/0003.patch | mm/mempolicy.c | SKIP | not compiled |  |
| CVE-2020-11608 | CVE-2020-11608/3.18/0003.patch | drivers/media/usb/gspca/ov519.c | SKIP | not compiled |  |
| CVE-2020-11609 | CVE-2020-11609/3.18/0003.patch | drivers/media/usb/gspca/stv06xx/stv06xx.c | SKIP | not compiled |  |
| CVE-2020-11668 | CVE-2020-11668/3.18/0003.patch | drivers/media/usb/gspca/xirlink_cit.c | SKIP | not compiled |  |
| CVE-2020-12653 | CVE-2020-12653/4.4/0005.patch | drivers/net/wireless/mwifiex/scan.c | SKIP | not compiled |  |
| CVE-2020-12654 | CVE-2020-12654/3.18/0003.patch | drivers/net/wireless/mwifiex/wmm.c | SKIP | not compiled |  |
| CVE-2020-12656 | CVE-2020-12656/4.4/0008.patch | net/sunrpc/auth_gss/svcauth_gss.c | SKIP | not compiled |  |
| CVE-2020-12656 | CVE-2020-12656/4.4/0009.patch | include/linux/sunrpc/gss_api.h | SKIP | not compiled |  |
| CVE-2020-12770 | CVE-2020-12770/3.18/0003.patch | drivers/scsi/sg.c | SKIP | not compiled |  |
| CVE-2020-13974 | CVE-2020-13974/3.18/0002.patch | drivers/tty/vt/keyboard.c | SKIP | not compiled |  |
| CVE-2020-14331 | CVE-2020-14331/3.18/0002.patch | drivers/video/console/vgacon.c | SKIP | not compiled |  |
| CVE-2020-15393 | CVE-2020-15393/3.18/0002.patch | drivers/usb/misc/usbtest.c | SKIP | not compiled |  |
| CVE-2020-15436 | CVE-2020-15436/3.18/0001.patch | fs/block_dev.c | OK | ef2445da7ed | ok |
| CVE-2020-16119 | CVE-2020-16119/4.4/0006.patch | net/dccp/minisocks.c | SKIP | not compiled |  |
| CVE-2020-24588 | CVE-2020-24588/4.4/0019.patch | net/wireless/util.c | OK | f6e12533c98 | ok |
| CVE-2020-24588 | CVE-2020-24588/4.4/0020.patch | net/mac80211/rx.c | OK | a1f7a30566e | ok |
| CVE-2020-25643 | CVE-2020-25643/3.18/0002.patch | drivers/net/wan/hdlc_ppp.c | SKIP | not compiled |  |
| CVE-2020-25668 | CVE-2020-25668/3.18/0007.patch | drivers/tty/vt/vt_ioctl.c | SKIP | not compiled |  |
| CVE-2020-25669 | CVE-2020-25669/3.18/0007.patch | drivers/input/keyboard/sunkbd.c | SKIP | not compiled |  |
| CVE-2020-25673 | CVE-2020-25673/3.18/0001.patch | net/nfc/llcp_sock.c | OK | 1da0a8f420c | ok |
| CVE-2020-27066 | CVE-2020-27066/3.18/0001.patch | net/xfrm/xfrm_policy.c | OK | 6c865a24a92 | ok |
| CVE-2020-27068 | CVE-2020-27068/3.18/0002.patch | net/wireless/nl80211.c | OK | 55fba268826 | ok |
| CVE-2020-27815 | CVE-2020-27815/3.18/0008.patch | fs/jfs/jfs_dmap.h | SKIP | not compiled |  |
| CVE-2020-27825 | CVE-2020-27825/3.18/0007.patch | kernel/trace/ring_buffer.c | OK | fb43ff5ff0f | ok |
| CVE-2020-28974 | CVE-2020-28974/3.18/0007.patch | drivers/tty/vt/vt.c | SKIP | not compiled |  |
| CVE-2020-29371 | CVE-2020-29371/3.18/0001.patch | fs/romfs/storage.c | SKIP | not compiled |  |
| CVE-2020-29568 | CVE-2020-29568/4.4/0020.patch | drivers/xen/xenbus/xenbus_probe_backend.c | SKIP | not compiled |  |
| CVE-2020-29661 | CVE-2020-29661/3.0-^3.10/0008.patch | drivers/tty/tty_io.c | OK | b304c2c7224 | ok |
| CVE-2020-36158 | CVE-2020-36158/3.18/0008.patch | drivers/net/wireless/mwifiex/join.c | SKIP | not compiled |  |
| CVE-2021-0512 | CVE-2021-0512/3.18/0001.patch | drivers/hid/hid-core.c | OK | f0412a76367 | ok |
| CVE-2021-3178 | CVE-2021-3178/3.18/0008.patch | fs/nfsd/nfs3xdr.c | SKIP | not compiled |  |
| CVE-2021-3483 | CVE-2021-3483/3.18/0008.patch | drivers/firewire/nosy.c | SKIP | not compiled |  |
| CVE-2021-3564 | CVE-2021-3564/3.18/0008.patch | net/bluetooth/hci_core.c | SKIP | not compiled |  |
| CVE-2021-3573 | CVE-2021-3573/3.18/0008.patch | net/bluetooth/hci_sock.c | SKIP | not compiled |  |
| CVE-2021-3609 | CVE-2021-3609/4.4/0006.patch | net/can/bcm.c | SKIP | not compiled |  |
| CVE-2021-3612 | CVE-2021-3612/3.18/0008.patch | drivers/input/joydev.c | OK | bda59352b2b | ok |
| CVE-2021-3653 | CVE-2021-3653/4.4/0006.patch | arch/x86/include/asm/svm.h | SKIP | not compiled |  |
| CVE-2021-3655 | CVE-2021-3655/4.4/0012.patch | net/sctp/input.c | SKIP | not compiled |  |
| CVE-2021-3655 | CVE-2021-3655/^5.13/0003.patch | net/sctp/input.c | SKIP | not compiled |  |
| CVE-2021-3753 | CVE-2021-3753/4.4/0004.patch | drivers/tty/vt/vt_ioctl.c | SKIP | not compiled |  |
| CVE-2021-3896 | CVE-2021-3896/4.4/0004.patch | drivers/isdn/capi/kcapi.c | SKIP | not compiled |  |
| CVE-2021-20261 | CVE-2021-20261/^3.15/0001.patch | drivers/block/floppy.c | SKIP | not compiled |  |
| CVE-2021-27363 | CVE-2021-27363/3.18/0008.patch | drivers/scsi/scsi_transport_iscsi.c | SKIP | not compiled |  |
| CVE-2021-27365 | CVE-2021-27365/4.4/0008.patch | drivers/scsi/scsi_transport_iscsi.c | SKIP | not compiled |  |
| CVE-2021-28713 | CVE-2021-28713/4.4/0004.patch | drivers/tty/hvc/hvc_xen.c | SKIP | not compiled |  |
| CVE-2021-28972 | CVE-2021-28972/3.18/0007.patch | drivers/pci/hotplug/rpadlpar_sysfs.c | SKIP | not compiled |  |
| CVE-2021-31916 | CVE-2021-31916/3.18/0008.patch | drivers/md/dm-ioctl.c | OK | 96ba1ef3ce2 | ok |
| CVE-2021-32399 | CVE-2021-32399/3.18/0008.patch | net/bluetooth/hci_core.c | SKIP | not compiled |  |
| CVE-2021-33656 | CVE-2021-33656/4.4/0007.patch | drivers/tty/vt/vt.c | SKIP | not compiled |  |
| CVE-2021-33909 | CVE-2021-33909/3.18/0001.patch | fs/seq_file.c | OK | f0ed4bb472d | ok |
| CVE-2021-34693 | CVE-2021-34693/3.18/0008.patch | net/can/bcm.c | SKIP | not compiled |  |
| CVE-2021-37576 | CVE-2021-37576/4.4/0006.patch | drivers/net/usb/hso.c | SKIP | not compiled |  |
| CVE-2021-39714 | CVE-2021-39714/4.4/0003.patch | drivers/staging/android/ion/ion.c | SKIP | not compiled |  |
| CVE-2021-39715 | CVE-2021-39715/ANY/0001.patch | arch/arm64/kernel/process.c | OK | bea0b856d64 | ok |
| CVE-2021-42008 | CVE-2021-42008/4.4/0004.patch | drivers/net/hamradio/6pack.c | SKIP | not compiled |  |
| CVE-2021-45095 | CVE-2021-45095/4.4/0004.patch | net/phonet/pep.c | SKIP | not compiled |  |
| CVE-2021-45868 | CVE-2021-45868/4.4/0004.patch | fs/quota/quota_tree.c | SKIP | not compiled |  |
| CVE-2021-46905 | CVE-2021-46905/3.18/0001.patch | drivers/net/usb/hso.c | SKIP | not compiled |  |
| CVE-2021-46909 | CVE-2021-46909/^5.12/0001.patch | arch/arm/mach-footbridge/cats-pci.c | SKIP | not compiled |  |
| CVE-2021-46932 | CVE-2021-46932/4.4/0004.patch | drivers/input/mouse/appletouch.c | SKIP | not compiled |  |
| CVE-2021-47086 | CVE-2021-47086/4.4/0004.patch | net/phonet/pep.c | SKIP | not compiled |  |
| CVE-2021-47114 | CVE-2021-47114/4.4/0004.patch | fs/ocfs2/file.c | SKIP | not compiled |  |
| CVE-2021-47118 | CVE-2021-47118/3.18/0001.patch | init/main.c | OK | 348f1ccd5d3 | ok |
| CVE-2021-47121 | CVE-2021-47121/3.18/0001.patch | net/caif/caif_usb.c | SKIP | not compiled |  |
| CVE-2021-47145 | CVE-2021-47145/3.18/0001.patch | fs/btrfs/tree-log.c | SKIP | not compiled |  |
| CVE-2021-47149 | CVE-2021-47149/3.18/0001.patch | drivers/net/ethernet/fujitsu/fmvj18x_cs.c | SKIP | not compiled |  |
| CVE-2021-47153 | CVE-2021-47153/3.18/0001.patch | drivers/i2c/busses/i2c-i801.c | SKIP | not compiled |  |
| CVE-2021-47169 | CVE-2021-47169/3.18/0001.patch | drivers/tty/serial/rp2.c | SKIP | not compiled |  |
| CVE-2021-47171 | CVE-2021-47171/3.18/0001.patch | drivers/net/usb/smsc75xx.c | SKIP | not compiled |  |
| CVE-2021-47173 | CVE-2021-47173/3.18/0001.patch | drivers/usb/misc/uss720.c | SKIP | not compiled |  |
| CVE-2021-47181 | CVE-2021-47181/4.4/0004.patch | drivers/usb/musb/tusb6010.c | SKIP | not compiled |  |
| CVE-2021-47216 | CVE-2021-47216/4.4/0004.patch | drivers/scsi/advansys.c | SKIP | not compiled |  |
| CVE-2021-47236 | CVE-2021-47236/3.18/0001.patch | drivers/net/usb/cdc_eem.c | SKIP | not compiled |  |
| CVE-2021-47249 | CVE-2021-47249/3.18/0001.patch | net/rds/recv.c | SKIP | not compiled |  |
| CVE-2021-47250 | CVE-2021-47250/3.18/0001.patch | net/ipv4/cipso_ipv4.c | SKIP | not compiled |  |
| CVE-2021-47266 | CVE-2021-47266/^5.13/0001.patch | drivers/infiniband/ulp/ipoib/ipoib_netlink.c | SKIP | not compiled |  |
| CVE-2021-47269 | CVE-2021-47269/3.18/0001.patch | drivers/usb/dwc3/ep0.c | SKIP | not compiled |  |
| CVE-2021-47276 | CVE-2021-47276/3.18/0001.patch | kernel/trace/ftrace.c | SKIP | not compiled |  |
| CVE-2021-47284 | CVE-2021-47284/3.18/0001.patch | drivers/isdn/hardware/mISDN/netjet.c | SKIP | not compiled |  |
| CVE-2021-47288 | CVE-2021-47288/4.4/0004.patch | drivers/media/pci/ngene/ngene-core.c | SKIP | not compiled |  |
| CVE-2021-47294 | CVE-2021-47294/4.4/0004.patch | net/netrom/nr_timer.c | SKIP | not compiled |  |
| CVE-2021-47323 | CVE-2021-47323/4.4/0004.patch | drivers/watchdog/sc520_wdt.c | SKIP | not compiled |  |
| CVE-2021-47324 | CVE-2021-47324/4.4/0004.patch | drivers/watchdog/sbc60xxwdt.c | SKIP | not compiled |  |
| CVE-2021-47330 | CVE-2021-47330/4.4/0004.patch | drivers/tty/serial/8250/serial_cs.c | SKIP | not compiled |  |
| CVE-2021-47334 | CVE-2021-47334/4.4/0004.patch | drivers/misc/ibmasm/module.c | SKIP | not compiled |  |
| CVE-2021-47340 | CVE-2021-47340/4.4/0004.patch | fs/jfs/inode.c | SKIP | not compiled |  |
| CVE-2021-47343 | CVE-2021-47343/4.4/0004.patch | drivers/md/persistent-data/dm-btree-remove.c | SKIP | not compiled |  |
| CVE-2021-47344 | CVE-2021-47344/4.4/0004.patch | drivers/media/usb/zr364xx/zr364xx.c | SKIP | not compiled |  |
| CVE-2021-47345 | CVE-2021-47345/4.4/0004.patch | drivers/infiniband/core/cma.c | SKIP | not compiled |  |
| CVE-2021-47347 | CVE-2021-47347/4.4/0004.patch | drivers/net/wireless/ti/wl1251/cmd.c | SKIP | not compiled |  |
| CVE-2021-47353 | CVE-2021-47353/4.4/0004.patch | fs/udf/namei.c | SKIP | not compiled |  |
| CVE-2021-47355 | CVE-2021-47355/4.4/0004.patch | drivers/atm/nicstar.c | SKIP | not compiled |  |
| CVE-2021-47356 | CVE-2021-47356/4.4/0004.patch | drivers/isdn/hardware/mISDN/hfcpci.c | SKIP | not compiled |  |
| CVE-2021-47357 | CVE-2021-47357/4.4/0004.patch | drivers/atm/iphase.c | SKIP | not compiled |  |
| CVE-2021-47416 | CVE-2021-47416/4.4/0004.patch | drivers/net/phy/mdio_bus.c | OK | 15485f30dc2 | reviewed, see below |
| CVE-2021-47418 | CVE-2021-47418/4.4/0004.patch | net/sched/sch_fifo.c | OK | 8642f68ab0c | ok |
| CVE-2021-47456 | CVE-2021-47456/4.4/0004.patch | drivers/net/can/sja1000/peak_pci.c | SKIP | not compiled |  |
| CVE-2021-47468 | CVE-2021-47468/4.4/0004.patch | drivers/isdn/hardware/mISDN/netjet.c | SKIP | not compiled |  |
| CVE-2021-47472 | CVE-2021-47472/4.4/0001.patch | drivers/net/phy/mdio_bus.c | OK | b9820578704 | reviewed, see below |
| CVE-2021-47472 | CVE-2021-47472/4.4/0005.patch | drivers/net/phy/mdio_bus.c | OK | bfa19ee440c | reviewed, see below |
| CVE-2021-47472 | CVE-2021-47472/^5.15/0002.patch | drivers/net/phy/mdio_bus.c | OK | 79588d77f80 | reviewed, see below |
| CVE-2021-47478 | CVE-2021-47478/4.4/0004.patch | fs/isofs/inode.c | SKIP | not compiled |  |
| CVE-2021-47518 | CVE-2021-47518/4.4/0004.patch | net/nfc/netlink.c | OK | 123d2be553d | reviewed, see below |
| CVE-2021-47520 | CVE-2021-47520/4.4/0004.patch | drivers/net/can/pch_can.c | SKIP | not compiled |  |
| CVE-2021-47521 | CVE-2021-47521/4.4/0004.patch | drivers/net/can/sja1000/ems_pcmcia.c | SKIP | not compiled |  |
| CVE-2021-47547 | CVE-2021-47547/4.4/0004.patch | drivers/net/ethernet/dec/tulip/de4x5.c | SKIP | not compiled |  |
| CVE-2021-47565 | CVE-2021-47565/4.4/0004.patch | drivers/scsi/mpt3sas/mpt3sas_scsih.c | SKIP | not compiled |  |
| CVE-2021-47566 | CVE-2021-47566/4.4/0004.patch | fs/proc/vmcore.c | SKIP | not compiled |  |
| CVE-2021-47589 | CVE-2021-47589/4.4/0004.patch | drivers/net/ethernet/intel/igbvf/netdev.c | SKIP | not compiled |  |
| CVE-2021-Misc2 | CVE-2021-Misc2/3.4/0073.patch | fs/pnode.c | OK | 1b5ebd3c4d4 | ok |
| CVE-2019-12819 | CVE-2019-12819/3.18/0003.patch | drivers/net/phy/mdio_bus.c | OK | 85de3ff9795 | ok |
| CVE-2019-14053 | CVE-2019-14053/3.4/0001.patch | net/xfrm/xfrm_user.c | OK | 626af38834d | ok |
| CVE-2019-14053 | CVE-2019-14053/3.4/0002.patch | net/xfrm/xfrm_user.c | OK | bcaa06b1c42 | ok |
| CVE-2019-14283 | CVE-2019-14283/3.18/0004.patch | drivers/block/floppy.c | SKIP | not compiled |  |
| CVE-2020-29660 | CVE-2020-29660/3.18/0007.patch | drivers/tty/tty_io.c | FAIL | patch does not apply |  |
