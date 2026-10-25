# Kernel security, Wave D (Wi-Fi driver, NVIDIA drivers, heap hardening)

**Summary (plain):** Branch `n9-3.10.108-secD` in `~/n9kernel/kernel`, on top of the flashed
`n9-3.10.108-sec-nvavp` (`b9078499b80`). 9 commits:
- 2 fixes in the Broadcom Wi-Fi driver (bcmdhd). Almost every published bcmdhd fix was
  already in our tree (Google shipped them to the Nexus 9 until its last update, Oct 2017).
- 0 NVIDIA fixes: every NVIDIA fix Google published for the Nexus 9 is already in the tree.
  Fixes from after the Nexus 9 lost support were never published for this kernel code.
- 6 Divest/CopperheadOS heap-hardening patches, plus 1 fix of mine to them. They make
  memory-corruption bugs much harder to exploit: freed memory is wiped, slab merging is off,
  free-list pointers are scrambled, and objects carry canaries. Cost: some CPU (every freed
  page is zeroed) and a little more RAM (+8 bytes per slab object).
- A heap-corruption bug in any driver now **crashes the kernel (BUG) instead of passing
  silently**. That is the point, but it is also the main boot risk.

Builds with GCC 4.9: 271 warnings, the same set as secC-nvavp. **Not boot-tested.**

| Image | Tree | Size | sha256 (16) | Notes |
|---|---|---|---|---|
| `~/n9kernel/out/boot-secD.img` | `c12ca048de8` | 9,031,680 | `392ec77baf4ccf0a` | everything |
| `~/n9kernel/out/boot-secD-wifionly.img` | `cba6325d181` | 9,031,680 | `30ebfe8ceeb003eb` | only the 2 bcmdhd fixes (fallback if secD fails) |

Both: repacked onto `~/n9kernel/rom/boot.img`, page 2048, ROM cmdline kept, ramdisk `961b8af0`
unchanged (checked with `bootimg-split.py`). Logs `~/n9kernel/out/build-108-secD{,-wifionly}.log`.
Scripts: `/tmp/divkp/wd/b.sh`. Note: `build-108` was last built at the wifionly commit.

Test plan: `fastboot boot boot-secD.img` first. Check boot to `sys.boot_completed`, Wi-Fi
connect + scan, LTE, HW video decode, camera, then a few hours of normal use;
`dmesg | grep -E "BUG|kernel BUG|Oops"` must be empty. If it crashes, try `secD-wifionly`.

## What was applied

| Commit | ID | What | How |
|---|---|---|---|
| `016ba8916da` | CVE-2017-0567 (ASB 2017-04, Broadcom) | `wl_cfg80211_add_iw_ie`: `data_len` (up to 255) was copied into the 9-byte `cfg->iw_ie` | Divest 3.4 patch hand-placed (context differs) |
| `cba6325d181` | CVE-2017-13303 (ASB, Broadcom) | `wl_cfgvendor_priv_string_handler`: user vendor data compared without length check; unbounded `strlen` of firmware reply | Hand-port by meaning. AOSP deleted the command; I kept it (unknown whether the Wi-Fi HAL uses it; no blobs pulled, tablet off-limits) and added a length check + `strnlen` |
| `c31667e14fb` | 0006/3.10/0007 | page sanitization: zero pages on free, verify zero on alloc (BUG if not) | unchanged |
| `f2a4c109854` | 0006/3.10/0008 | slub sanitization: zero objects on free (re-run ctor) | unchanged |
| `0a6d0230cb6` | 0006/3.10/0009 | slub write-after-free check on alloc (BUG) | unchanged |
| `d5d56275113` | 0006/3.10/0010 | slab merging off by default (`slub_nomerge = 1`) | unchanged |
| `5ac40dc434f` | 0006/3.10/0011 | slub free-list pointer XOR with per-cache secret and address | unchanged |
| `26d4e74800f` | 0006/3.10/0012 | slub per-object random canary, checked on alloc/free (BUG) | unchanged |
| `c12ca048de8` | follow-up | secrets set at the top of `kmem_cache_open()` instead of end of `__kmem_cache_create()` | mine, see below |

Hunk placement checked by hand: `free_pages_prepare`/`prep_new_page` (page_alloc.c),
`slab_alloc_node`, `slab_free`, `setup_object`, `early_kmem_cache_node_alloc`, `calculate_sizes`,
`get_track`, `print_trailer`, `check_pad_bytes`, `slab_ksize`, freepointer helpers (slub.c).
`CONFIG_SLUB=y`, `SLUB_DEBUG_ON` off, `DEBUG_PAGEALLOC` off, no highmem.

Why the follow-up: in our 3.10 `__kmem_cache_create()` returns early while `slab_state <= UP`,
so the Divest placement left every boot cache (`kmalloc-*`, `kmem_cache`, `kmem_cache_node`)
with all-zero secrets (the most-attacked caches). Not a crash bug (values stayed consistent), a
strength bug. Mainline `SLAB_FREELIST_HARDENED` sets the secret at the top of `kmem_cache_open()`,
before `early_kmem_cache_node_alloc()` builds the first slab; `bootstrap()` memcpy carries it.
Early-boot `get_random_long()` entropy is weak (jiffies/cycles, no arm64 HW RNG), same as mainline.

## Skipped and why

### bcmdhd (all Divest bcmdhd patches, 60 files, tested against our tree)
- Already present (fix visible in the code, often a different patch revision): CVE-2016-0801,
  -0802, -2475 (`apply --check` passed but the `capable(CAP_NET_ADMIN)` check already exists a few
  lines away; applying would duplicate it), -8454, -8456, -8457, -8464, -8465, -8466, CVE-2017-0430,
  -0509, -0568, -0569, -0570, -0571, -0572, -0573, -0574, -0633, -0705, -0706, -0740, -0786..-0792,
  -0824, -0825, -13292.
- Not applicable: CVE-2016-8455 (APF filter code does not exist in our bcmdhd);
  CVE-2016-8453, CVE-2017-0449 (`dhd_pcie.c`; flounder's BCM4354 is on SDIO, file not compiled).
- Upstream brcmfmac CVEs (e.g. CVE-2019-9500/9503) are for a different driver, not built.

### NVIDIA (nvmap, nvhost, nvgpu, nvavp, camera, cryptodev, quadd)
The tree already carries Google's Nexus 9 fixes through its final update, e.g. nvmap TOCTOU
`8a475ed425f`, OOB `ca04323faa0`, create-handle `e85b751dee0`, info leaks `00343697d9d`/`b860552cb94`;
nvhost submit/overflow `8aa87ee451a`, `687e106e7ff`, `aa70a157fd0`; nvgpu `2c4667047ca`,
`420e75934c5`, `90d0178529f`, `36e52833669`; nvavp UAF `2190da53209`; tegra-cryptodev
`95e9b66a92b`/`8517de73b11`; quadd leaks. DivestOS has no NVIDIA patches. NVIDIA items in
bulletins after Oct 2017 target Pixel C / SHIELD (3.18/4.x, T210 nvgpu); no public fix that maps
onto this code was found, so none was ported (would be guesswork).

### Divest 3.10 FAIL lists
Wave A had none, Wave B's 3 are resolved (waveC note), Wave C's one (CVE-2022-Misc2) is moot.
Nothing left.

### Hardening not taken
0004 (DEVICE_SIDECHANNEL: changes stat timestamps on device nodes, behaviour change), 0005/0018
(early entropy tweaks), 0006 (arm64 canary byte), 0013-0017 (extra slab checks / panics), and
DENYUSB (0005-*, as requested). Candidates for a later wave if secD proves stable.

## Remaining known gaps
- Post-EOL (2018+) Broadcom/NVIDIA vendor-driver bugs: no fixes exist for this code.
- Spectre/Meltdown-class arm64 mitigations: not feasible on this tree.
- Everything Divest skipped as "not compiled" stays unfixed but unreachable.
- secD is not boot-tested; the hardening can expose latent use-after-free bugs in vendor
  drivers as BUG() crashes. If a BUG names a specific cache/driver, that is a real bug to fix,
  not a reason to drop the hardening right away.
- 11:56-12:11 boot-secD.img x2: USB OK (20 s), no oops, cameraserver running, Wi-Fi on, nvavp IOVA OK. LTE not registered both runs because the SIM was removed by the owner (qcril card_error 3 'No ATR', card_state 2). LTE needs a recheck with the SIM back in before/after flashing.
