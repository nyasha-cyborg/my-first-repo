# Sources and licensing

Everything in this repository is either written here or derived from something
below. Nothing bulky is vendored, and nothing proprietary is redistributed.

## Where each input comes from

| Input | Upstream | Pinned to | Licence | How it is obtained |
|---|---|---|---|---|
| Kernel source | `https://cyberchaos.dev/yuka/linux.git`, branch `flounder` | commit `38ff6862` | GPL-2.0 | `./setup.sh` clones it; **not** stored here |
| Kernel config | postmarketOS `pmaports`, `device/testing/linux-htc-flounder` | snapshot | GPL-2.0 | `configs/flounder_defconfig` |
| Stock boot images | Android 7.1.1 factory images — Wi-Fi `volantis` N4F27B, LTE `volantisg` N4F27P | N/A | Proprietary | Downloaded by hand; **never committed** |
| `hboot.img` | Same factory images | N/A | Proprietary | Read-only analysis; **never committed** |

The non-free rows are inputs to the analysis, not part of the deliverable. They
are excluded by `.gitignore` and must stay that way.

## Why the kernel is not in this repository

The kernel is a **build input**, in the same sense that a compiler is. This
repository holds the small, irreplaceable part: the findings, the patches, the
tools, and the recipe that reproduces the rest.

Committing the kernel would mean:

- carrying a ~282 MB third-party clone (and worse, `--unshallow`ing it first,
  because git refuses to push from a shallow clone) into a repository that is
  otherwise measured in kilobytes;
- embedding someone else's history in this one permanently — git history is
  append-only, so it could never be taken back out;
- duplicating a dependency that is already reproducible from the recipe below.

The same reasoning applies, more strongly, to the ROMs and extracted images in
`~/Downloads/nexus9`: roughly 1.8 GB of purely derivable data.

## Licensing

**This repository is licensed GPL-2.0.** See [`LICENSE`](LICENSE).

That is not a free choice. The patches in `patches/` modify the Linux kernel
and are therefore derivative works of it, so they must carry the kernel's
licence. Applying GPL-2.0 to the repository as a whole keeps the position
simple and unambiguous rather than splitting hairs over which file is which.

GPL-2.0 permits redistribution and modification; it requires that the licence
and copyright notices travel with the work. It does **not** require you to
publish anything you build from it, and it does not reach across into unrelated
software you write.

## Refreshing

- **Kernel moved upstream?** Update `KERNEL_COMMIT` in `setup.sh`, re-clone, and
  re-apply `patches/flounder-lte-and-display.patch` to confirm it still applies.
- **Changed the kernel tree by hand?** Regenerate the cumulative patch from the
  working tree so the change is captured here:

  ```sh
  git -C linux-flounder add -A
  git -C linux-flounder diff --cached HEAD -- . \
      ':(exclude)arch/arm64/configs/flounder_defconfig' \
      > patches/flounder-lte-and-display.patch
  ```

  The exclusion keeps the kernel config out of the source patch, where it would
  be 230 KB of noise; it lives in `configs/` instead.
- **Changed the config?** Replace `configs/flounder_defconfig`.
