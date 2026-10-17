# Checking the device tree against the bindings

Setup and results as of 2026-10-17. This is the check that catches what a clean
`dtbs` build cannot: **`dtc` validates syntax, and this validates meaning.** The
first run found five real errors in nodes that compiled without a murmur.

## Running it

`make CHECK_DTBS=1` wants `dtschema`, which is not installed system-wide here.
It does not need to be — `dt-validate` validates a built DTB against a bindings
directory directly, so a throwaway virtualenv is enough and nothing outside it
is touched:

```sh
python3 -m venv ~/.local/share/nexus9-dtschema-venv
~/.local/share/nexus9-dtschema-venv/bin/pip install dtschema

cd linux-flounder
make O=$PWD/../linux-flounder-out ARCH=arm64 LLVM=1 dtbs    # build the DTB first

# one subtree, which is quick
~/.local/share/nexus9-dtschema-venv/bin/dt-validate \
    -s Documentation/devicetree/bindings -l '/sound/' -m \
    ../linux-flounder-out/arch/arm64/boot/dts/nvidia/tegra132-flounder.dtb

# the whole tree, which takes about twenty minutes
~/.local/share/nexus9-dtschema-venv/bin/dt-validate \
    -s Documentation/devicetree/bindings -m \
    ../linux-flounder-out/arch/arm64/boot/dts/nvidia/tegra132-flounder.dtb
```

`-l` limits to schemas whose `$id` contains the substring, and accepts several
separated by `:`. `-m` also lists compatible strings that match no schema at
all, which is how the vestigial nodes elsewhere in the port's tree show up.
Exit code is 120 when errors were found, 0 when clean.

## Fixed

### Audio — `patches/flounder-audio.patch`

| Node | Error |
|---|---|
| `rt5677@2d` | `gpio-controller` and `#gpio-cells` are required by `realtek,rt5677.yaml` |
| `rt5677@2d` | needs `interrupts` or `interrupts-extended` |
| `audio-codec@34/35` | `port` rejected by `nxp,tfa989x.yaml` |
| `i2s@70301200` | `ports` rejected by `nvidia,tegra30-i2s.yaml` |
| `sound` | `nvidia,tegra-audio-rt5677` alone is too short; the binding wants a board-suffixed compatible first |

The irq is `PS4`, which is `gpio_irq1` in the downstream board file.

Those two `port`/`ports` rows are why the speaker card is a machine driver and
not an `audio-graph-card2` graph: both bindings are `additionalProperties:
false` and admit no graph nodes, so the graph approach is excluded by design
rather than merely undocumented. See `notes/audio.md` Finding 6.

### SoC dtsi — `patches/tegra132-compatible-fallbacks.patch`

Three nodes in mainline's `arch/arm64/boot/dts/nvidia/tegra132.dtsi` declare a
compatible the bindings document as a **two-element** list:

| Node | Binding expects |
|---|---|
| `dsi@54300000` | `nvidia,tegra132-dsi`, `nvidia,tegra124-dsi` |
| `dsi@54400000` | `nvidia,tegra132-dsi`, `nvidia,tegra124-dsi` |
| `fuse@7000f800` | `nvidia,tegra132-efuse`, `nvidia,tegra124-efuse` |

All three supply only the first element, so each reports as "too short". This is
a bug in the upstream file, not in anything this port added, and the fallback is
safe in both cases because the drivers already match the second compatible —
`drivers/gpu/drm/tegra/dsi.c` lists both, and
`drivers/soc/tegra/fuse/fuse-tegra.c` lists `nvidia,tegra124-efuse`. The only
other consumer of this file is `tegra132-norrin.dts`, which benefits too.

## Still open, and not obviously ours to fix

| Node | Diagnosis |
|---|---|
| `/` | `google,flounder64_lte` is not in the Tegra board list — structural, in that mainline has never had a flounder tree at all |
| `ccplex-clock@70040000` | `nvidia,tegra132-ccplex-clk` matches no schema |
| `touchscreen@0` | `rmi-f01@1` / `rmi-f12@12` subnodes not admitted by `syna,rmi4.yaml` |
| `extcon-usb-gpio` | two errors against `linux,extcon-usb-gpio.yaml` |
| `clock@70040084`, several regulators | values reported as `b'\x00\x00\x00\x01'` — as bytes rather than integers |

That last row should be **treated with suspicion rather than believed**. A cell
value rendering as a bytes literal points at how the validator represented an
untyped property, not at the device tree being wrong. It is recorded as
unresolved rather than as a defect, and is the one row here that might be noise.
