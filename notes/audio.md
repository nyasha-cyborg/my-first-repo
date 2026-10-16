# Audio bring-up for flounder

Surveyed 2026-10-17. What the hardware is wired like, what mainline already has,
and the two findings that change the shape of the job.

Nothing here has run on hardware. Everything below is read out of either the
**shipped 7.1.1 artifact** (the stock kernel and DTB, via REA and `dtc`) or the
mainline 6.19 tree this port builds.

## The topology: two DAI links, not one

The port's device tree marks every audio part `/* TODO */`. Reading the shipped
artifact shows why a naive single-codec node would be wrong — flounder splits
playback across **two separate I2S controllers**:

| Path | Codec | Pins | Port DT pinmux function | Mainline node |
|---|---|---|---|---|
| Headphones, mics | `rt5677` | `dap2_*` PA2-PA5 | `i2s1` | `tegra_i2s1` @70301100 |
| Speakers | `tfa9895` ×2 | `dap3_*` PP0-PP3 | `i2s2` | `tegra_i2s2` @70301200 |

Two independent sources agree on that mapping:

- the shipped DTB gives `i2s@70301100` an `nvidia,ahub-i2s-id = <0x01>`;
- downstream `board-flounder.c` puts `HIFI_CODEC` on `audio_port_id = 1` with the
  `dap2` pins, and `SPEAKER` on `2` with `dap3`.

The classic `nvidia,tegra-audio-rt5677` machine driver (`tegra_asoc_machine.c:996`)
models **one** codec, so it cannot express both links — which is exactly why
downstream shipped a custom `tegra_rt5677.c` instead of the generic one.

## What mainline already has

| Part | State |
|---|---|
| `rt5677` codec | driver in tree, `CONFIG_SND_SOC_RT5677=m` **already enabled** |
| `rt5677` machine driver | `nvidia,tegra-audio-rt5677` in `tegra_asoc_machine.c` |
| `tfa9895` speaker amps | driver in tree (`sound/soc/codecs/tfa989x.c:408`), `CONFIG_SND_SOC_TFA989X` **not enabled** |
| graph-card machine driver | `SND_SOC_TEGRA_AUDIO_GRAPH_CARD=m` **already enabled** |
| I2S controllers | present and `okay` in the DT |

`tfa989x` carries one caveat, stated in its own Kconfig: it **bypasses the amp's
CoolFlux DSP and supports no hardware volume control** — software volume only.
Irrelevant for music.

The DT also has no `sound` node of any kind, so even with every driver loaded
there is currently no card.

## Finding 1 — the headphone amp is driven by the *machine* driver

REA on the shipped kernel finds the flounder machine driver poking the RT5506
directly:

```
tegra_rt5677_rt5506_gain_set
tegra_rt5677_rt5506_dump_set
```

That RT5506 sits on the headphone path (`rt5506@52`, a bare TODO in the port's
DT), and **mainline has no rt5506 driver at all**. If headphone output depends on
that amp being configured, headphones are blocked on more than a DT node.

Note the inversion this creates: nothing sits on the speaker path, so the
**speakers may be the easier target than headphones**.

## Finding 2 — downstream loaded rt5677 DSP firmware

Also from REA:

```
rt5677_load_dsp_from_file      rt5677_elf_%s
rt5677_parse_and_load_dsp      snd_soc_rt5677.dsp_vad_suffix
```

The downstream codec loaded VAD/DSP firmware at probe. Mainline's rt5677 does not.
Almost certainly only needed for the voice-activity / always-on-mic path rather
than plain playback — but it is the kind of gap that produces "playback partly
works", so it is worth knowing before chasing a symptom.

## Supporting detail

- Codec attaches as `rt5677.1-002d` — **I2C bus 1, address 0x2d**, matching the
  port's `rt5677@2d` node.
- Card device name downstream: `tegra-snd-rt5677`; compatible
  `nvidia,tegra-audio-rt5677`.
- Supply is palmas **LDO2** (`v_ldo2`, "tegra_rt5677_reg v_ldo2 is enabled") at
  1.2 V — the port already carries this as `vdd_audio: ldo2`.
- GPIOs the downstream driver requests, all still unwired in the port's DT:
  `tfa9895-power-enable`, `rt5677-ldo-enable`, `rt5677-reset`.
- The codec also has an SPI interface (`rt5677@0` on `spi@7000dc00`,
  `flounder_rt5677_spi_suspend`). Downstream used it for DSP code transfer, not
  for ordinary control — so it is not needed for a basic playback path.

## Building evidence

The downstream source came from
`CaptainThrowback/kernel_android-tegra-flounder-3.10`, branch `BeyondStock-M-MR1`
(`arch/arm/mach-tegra/board-flounder.c`, `sound/soc/tegra/tegra_rt5677.c`). Note
that fork is a 2016-era Android 6 tree; the **shipped artifact is the 7.1.1
kernel**, which is what REA was pointed at, and the two agree.

```sh
# decompile the shipped device tree that carries the ahub-i2s-id values
dtc -I dtb -O dts -o lte.dts ~/Downloads/nexus9/extract-lte/fdt/fdt-0x66d8d2.dtb

# wrap the shipped kernel so a binary analyser will read it
llvm-objcopy -I binary -O elf64-littleaarch64 -B aarch64 \
    ~/Downloads/nexus9/kernel-lte.raw kernel-lte.elf
```

## Finding 3 — the Tegra audio graph card cannot be used here

`tegra_audio_graph_card.c` matches only three compatibles:

```c
{ .compatible = "nvidia,tegra210-audio-graph-card", ... }
{ .compatible = "nvidia,tegra186-audio-graph-card", ... }
{ .compatible = "nvidia,tegra264-audio-graph-card", ... }
```

No Tegra124/132. So the modern Tegra card driver — the one that would express
several DAI links cleanly — is unavailable, and the single-codec
`nvidia,tegra-audio-rt5677` machine driver is the only supported route. Its
shape, from source:

```c
components = "codec:rt5677"
dai     = "RT5677", codec DAI name "rt5677-aif1"
dai_fmt = SND_SOC_DAIFMT_I2S | _NB_NF | _CBC_CFC    /* Tegra is master */
```

## Finding 4 — the downstream amps were separate drivers, driven by ioctl

REA on the shipped kernel finds two distinct codec drivers, not one:

```
sound/soc/codecs/tfa9895.c      tfa9895_probe, set_tfa9895_spkamp, tfa9895_disable
sound/soc/codecs/tfa9895l.c     tfa9895l_probe, set_tfa9895l_spkamp, tfa9895l_disable
```

and the strings `TFA9895_WRITE_CONFIG`, `TFA9895_READ_CONFIG`,
`TFA9895_ENABLE_DSP` show they were configured from userspace over ioctl, with
the machine driver registering them. So the acoustic tuning (protection
filters, EQ) the tablet shipped with lives in an Android HAL, **not in the
device tree** — mainline will run these amps at defaults.

Mainline's `tfa989x` DAI is also narrower than the path needs:

```c
.name = "tfa989x-hifi"          playback only
.formats = SNDRV_PCM_FMTBIT_S16_LE     16-bit only
.rates   = 8000..48000
```

The `tfa9895-power-enable` GPIO is a single pin shared by both amps.

## What was implemented

`patches/flounder-audio.patch`, applied after the cumulative patch. It is
deliberately the **rt5677 path only** — the one mainline actually has a machine
driver and binding for.

- `rt5677@2d` gains its label, is enabled, and gets the two optional GPIOs the
  codec driver asks for: `realtek,pow-ldo2-gpio` (PQ3, active high) and
  `realtek,reset-gpio` (PX4, active low). Both are downstream board-file
  numbers.
- `vdd_audio` (palmas LDO2, 1.2 V) becomes `regulator-always-on`. Downstream
  consumed this rail as `v_ldo2` from the machine driver; mainline's machine
  driver has no supply consumer, so nothing else would ever enable it.
- A `sound` node: `nvidia,tegra-audio-rt5677` on `tegra_i2s1` with the rt5677,
  headphone and headset-mic routing, and the PLL_A -> EXTERN1 -> PMC clock-out
  mclk chain copied from the Nexus 7, which uses the same machine driver.

Verified: `dtbs` builds clean, and the built DTB resolves `nvidia,i2s-controller`
to `tegra_i2s1`, `nvidia,audio-codec` to the rt5677, the three clocks to
PLL_A (216) / PLL_A_OUT0 (217) / PMC CLK_OUT_1, and the GPIOs to 131 and 188.

## Not done, and what it needs

- **Nothing has run on hardware. No driver has bound; no card has been seen.**
- **The schema check was not run** — `make CHECK_DTBS=1` needs the `dtschema`
  python package, which is not installed here. The node was checked by hand
  against `nvidia,tegra-audio-rt5677.yaml` and `realtek,rt5677.yaml` instead,
  which is exactly the gap the panel driver's binding still has.
- **The speaker path is untouched.** It needs two amp nodes on `tegra_i2s2`, a
  multi-codec card (generic `audio-graph-card`, not the Tegra one), and it will
  run without the shipped acoustic tuning. Given the amps also want a power
  enable GPIO and bring 16-bit-only playback with them, this is the larger job.
- **The `rt5506` question is unresolved.** It sits on the headphone path with no
  mainline driver, and the shipped kernel configures it. Whether playback needs
  it or the codec drives the jack directly is the thing most likely to decide
  whether this node produces sound.
- `dtbs` builds clean, but three pre-existing warnings appear from the port's own
  DT, not from this change: `usb@7d000000` / `usb@7d004000` / `usb@7d008000`
  each share a unit address with their `usb-phy@` sibling.
