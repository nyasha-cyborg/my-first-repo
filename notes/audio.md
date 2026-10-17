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

## Finding 5 — the rt5506 is the headphone output stage, and has no driver

This settles the open question from Finding 1, and the answer is bad for the
headphone path. The shipped kernel carries a complete driver for it:

```
rt5506_probe        set_rt5506_hp_en        rt5506_volume_ramp
rt5506_headset_detect   set_rt5506_amp      rt5506_set_gain
```

plus two GPIOs (`rt5506-enable`, `rt5506-power-en`) and an LDO
(`rt5506_reg ldoen is enabled`). Its compat string is `richtek,rt5506-amp`, and
its mixer control is literally "Headset rt5506 Volume", with headset impedance
detection alongside it.

So the amp is not an optional accessory to the jack — it *is* the headphone
output stage, and it also does jack detection. **Mainline has no rt5506 driver**
(`grep -rl rt5506 sound/` is empty), so the rt5677 node committed above gives a
card whose headphone output has nothing to drive it.

## Finding 6 — the speaker path needs a machine driver, and the bindings are why

This finding was wrong twice before it was right, so the route matters as much
as the conclusion.

**First attempt:** "the speaker path needs a machine driver, because
`tegra30_i2s.c` has no `of_graph` support." The reasoning was bad —
`audio-graph-card` parses the graph out of the device tree itself and resolves
components by `of_node`, so the CPU driver needs no graph code.

**Second attempt:** "so it is device tree work, using a graph card." Also wrong,
and the schema check below is what settled it. Both bindings involved are
`additionalProperties: false` and admit no graph nodes at all:

- `nvidia,tegra30-i2s.yaml` allows only `^pinctrl-[0-9]+$` beyond its named
  properties — no `port`, no `ports`;
- `nxp,tfa989x.yaml` likewise allows only `^pinctrl-[0-9]+$`.

So graph nodes on a Tegra I2S are not merely undocumented, they are excluded by
design. What is genuinely true and constrains the choice:

- `simple-audio-card` is hard-limited to **one codec per link** — the parser is
  `of_get_child_by_name(node, "codec")`, which returns a single node;
- `audio-graph-card` hardcodes `li->num[li->link].codecs = 1`; only
  `audio-graph-card2` handles `num_codecs > 1`, and it needs the ports that
  Tegra30 forbids;
- the qcom cards that carry two amps use a `sound-dai` phandle *list*, which is
  that card driver's own extension.

That leaves a **machine driver**, declaring the link in C where the codec array
size is not the bindings' business — which is also the conclusion the first
attempt reached for the wrong reason, and what downstream shipped.

## Checking the device tree against the bindings

`make CHECK_DTBS=1` needs `dtschema`, which is not installed system-wide here.
It does not need to be: `dt-validate` will validate a built DTB against a
bindings directory directly, so a throwaway venv is enough. The recipe, and the
tree-wide results, are in [`schema-check.md`](schema-check.md).

Run before trusting any binding claim. It found five real errors in the audio
nodes, all in nodes that had built perfectly cleanly, because `dtc` checks
syntax and this checks meaning:

| Node | Error |
|---|---|
| `rt5677@2d` | `gpio-controller` and `#gpio-cells` are required by `realtek,rt5677.yaml` |
| `rt5677@2d` | needs `interrupts` or `interrupts-extended` |
| `audio-codec@34/35` | `port` rejected — the graph node above |
| `i2s@70301200` | `ports` rejected — the graph node above |
| `sound` | `nvidia,tegra-audio-rt5677` alone is too short; the binding wants a board-suffixed compatible first |

The irq is `PS4`, which is `gpio_irq1` in the downstream board file — so the
requirement is satisfiable from evidence rather than guesswork.

## The rest of the tree

Running the same check without the `-l '/sound/'` filter takes about twenty
minutes and reports roughly 150 lines of diagnostics. Audio is clean in it; the
rest is the port's own device tree, and **this port's DT is not schema-clean as
a whole.** The full breakdown, including what was fixed in the SoC dtsi and what
is still open, is in [`schema-check.md`](schema-check.md).

## Templates that already exist in this tree

- **`tegra124-xiaomi-mocha.dts`** — the Shield Tablet, same Tegra124 family,
  declares two `nxp,tfa9890` amps at 0x36/0x37 with `sound-name-prefix`
  "Speaker Right" / "Speaker Left" and a `vddd-supply`. Closest hardware match
  to flounder's speaker path. Note it declares the amps but has **no card node**,
  so the amps are described and unwired — mainline has not finished the Shield
  Tablet's audio either.
- **`msm8916-alcatel-idol347.dts`** — a working two-amp card, with
  `pin-switches` so the speakers can be disabled individually.
- **`nxp,tfa989x.yaml`** documents exactly this topology: two amp nodes, each
  with `sound-name-prefix`, `#sound-dai-cells = <0>`, optional `vddd-supply`.
  It sets `additionalProperties: false`, so whether it tolerates the `port`
  subnode a graph card needs is unverified here — the same schema check that
  could not be run.

## The two paths, honestly

| Path | What it is blocked on |
|---|---|
| Headphones | an **rt5506 driver** — mainline has none, and the register map would have to come out of the shipped binary |
| Speakers | device tree only — amp nodes plus a graph card |

The node committed here registers a card and proves the rt5677 wiring, but its
headphone output has no driver behind it. The speaker path is the one that can
be finished in the device tree.

## What was implemented

`patches/flounder-audio.patch`, applied after the cumulative patch. It carries
two cards: the rt5677 headphone/mic card, and a speaker card built on
`audio-graph-card2`.

The speaker card is the interesting one, because no generic driver can express
the topology. It is declared in `sound/soc/tegra/tegra_asoc_machine.c`, next to
the other Tegra machines, so the link reuses that driver's clocks, hw_params and
ops instead of duplicating them:

- a `SND_SOC_DAILINK_DEFS(flounder_spk, …)` with **two** codec entries, which is
  what makes `num_codecs = 2` and gives one stereo PCM rather than two mono
  ones;
- a `tegra_flounder_spk_data` entry matched by
  `nvidia,tegra-audio-tfa989x-flounder`;
- the probe now reads as many `nvidia,audio-codec` phandles as the link
  declares, via a new indexed variant of `tegra_machine_parse_phandle`. The
  original is kept as a one-line wrapper, so no existing card changes
  behaviour.

On the device tree side:

- two `nxp,tfa9895` nodes at 0x34 and 0x35, each with `#sound-dai-cells = <0>`,
  a `sound-name-prefix` and a shared `vddd-supply`;
- `spk_ldo`, a `regulator-fixed` gated by the `tfa9895-power-enable` pin (PX5
  downstream). It declares **no voltage**, because none is known: downstream
  only ever toggled the enable, and the amplifier driver only gets and enables
  the regulator without ever setting a voltage. An earlier draft carried an
  invented 5 V, which nothing would have caught and which would have been a
  guess sitting in the tree looking like a measurement. Dropping it was
  revalidated against `fixed-regulator.yaml`;
- a `sound-speakers` node with the I2S, both codecs, and the routing
  `"Speakers", "Speaker <side> OUT"`. Both amplifiers expose the same DAPM pin
  `OUT`; the `sound-name-prefix` is what disambiguates them, since ASoC prefixes
  widget names as `"<prefix> <widget>"`.
- **no `fully_routed`** on this card. It takes the shared widget set, which
  carries headphone and microphone widgets flounder does not wire through here,
  so asserting completeness would fail on its own. That is a real gap in the
  routing check for this card, not an oversight.

The rt5677 card:

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

## Auditing the driver before any hardware

The panel driver yielded seven bugs to a pre-hardware audit, so the same was
done here. This one came back clean, which is worth stating as plainly as a
finding would be, along with what was actually checked:

- **`num_codecs` is genuinely 2 at compile time.** `SND_SOC_DAILINK_REG1`
  expands to `ARRAY_SIZE()` of the codec array, and `DAILINK_COMP_ARRAY` is a
  variadic passthrough, so two `COMP_CODEC` entries really do yield 2. Had it
  been 0 the probe loop would silently skip and the card would register with no
  codecs at all — the kind of failure that reads as "no sound" rather than an
  error.
- **The other cards are untouched.** Every existing card has `num_codecs == 1`,
  so the loop runs once at index 0, which is what the old code did
  unconditionally. The AC97 path never assigned codecs and still does not.
- **The shared `init` is safe with two codecs.** `tegra_asoc_machine_init`
  touches the codec only from jack paths, every one of which is behind an
  `asoc->add_*_jack` flag that this card leaves false, so it returns without
  looking at a codec at all.
- **`card->components` is only a label.** `snd_component_add()` puts the string
  into the ALSA card's component list; it is not instantiation, so
  `codec:tfa989x` cannot attempt to create a device.
- **The amplifiers never constrain the supply voltage** — `devm_regulator_get`
  and enable/disable only — which is why declaring none is safe.

Verified, in the order the checks were run:

1. **`dtbs` builds clean.**
2. **`Image` and `modules` build clean**, which is what actually compile-tests the
   `CONFIG_SND_SOC_TFA989X=m` change — `dtbs` alone would not have.
3. **`tegra_asoc_machine.c` recompiles with no warnings**, forced with a `touch`
   rather than trusted to an incremental build that had nothing to do.
4. **`dt-validate` reports zero errors for every sound binding**, including the
   new one. Before the fixes it reported five.
5. **In the built DTB**, every reference resolves to what it should:

   | Reference | Resolves to |
   |---|---|
   | speaker card `nvidia,i2s-controller` | `i2s@70301200` (`tegra_i2s2`) |
   | speaker card `nvidia,audio-codec` | `audio-codec@34`, `audio-codec@35` |
   | rt5677 card `nvidia,i2s-controller` | `i2s@70301100` (`tegra_i2s1`) |
   | rt5677 card `nvidia,audio-codec` | `rt5677@2d` |

   The two amplifier phandles are in the same order as the routing entries, so
   `Speaker Right` and `Speaker Left` are not swapped.
6. **The patch applies cleanly to a pre-audio tree**, checked by rewinding the
   DTS, the driver and the binding and running `git apply --check`.

Phandles are auto-assigned and shifted twice while this work landed, so the
numbers in the table were resolved and read back rather than assumed.

## How to point a binary analyser at a kernel Image

Worth writing down, because the first attempt was subtly useless.

`objcopy -B aarch64` on a raw kernel `Image` lands the bytes in **`.data`**,
which is not executable, so Ghidra treats the whole 16 MB as data: string
searches work and nothing else does. Every xref comes back empty, and asking for
a function by name fails with "unknown procedure", which reads like the symbol
is missing rather than like no code was ever analysed.

Wrapping so the bytes land in an executable section fixes it:

```sh
llvm-objcopy -I binary -O elf64-littleaarch64 -B aarch64 \
    --rename-section .data=.text,alloc,load,readonly,code \
    ~/Downloads/nexus9/kernel-lte.raw kernel-lte-text.elf
```

With this, Ghidra's procedure inventory for the image exceeds the MCP response
budget — code analysis is genuinely running.

Two limits remain, and between them they cap what this can answer:

- **The name lookup still fails.** The `rt5677_*` / `rt5506_*` / `tfa9895_*`
  names the string search finds are `kallsyms` data, compressed for crash
  reporting. No analyser applies them, so there is still no way to ask for a
  function by name; a code address has to be reached some other way.
- **String xrefs still resolve to nothing**, including for
  `"rt5506 hs imp value ..."`. Making the section executable did not change it,
  which points at the image's load base rather than at the section flags.

Neither blocker is fatal on its own, but the second one means the driver's own
register writes are not reachable by following its strings.

## Not done, and what it needs

- **Nothing has run on hardware. No driver has bound; no card has been seen.**
- **The schema check now runs** (recipe above), and it found real errors that a
  clean `dtbs` build had hidden — which is the argument for running it before
  trusting any binding claim.
- **Nothing has bound, on either card.** Builds and DT resolution are not
  binding. The speaker card is the one that could plausibly come up, but
  `audio-graph-card2` has never been pointed at a Tegra I2S before, so whether
  it resolves a Tegra DAI to a PCM is the first thing to find out.
- **There is no binding for `nvidia,tegra-audio-tfa989x-flounder`.** The new
  speaker card needs one to be schema-clean; as it stands only the rt5677 card
  was validated against real schemas.
- **The speaker amps have no acoustic tuning here** (see below).
- **It will run without the shipped acoustic tuning.** The amps' protection and
  EQ configuration was applied from the Android HAL over ioctl
  (`TFA9895_WRITE_CONFIG`), so mainline gets the hardware defaults. That is a
  behaviour difference to expect, not a bug to chase.
- **Mainline's amp DAI is narrower than the path**: `tfa989x-hifi` is
  playback-only, `S16_LE`, 8-48 kHz.
- **The `rt5506` is the blocker, and it turned out to be smaller than this note
  first estimated.** It is the headphone output stage with no mainline driver,
  and its tuning was expected to be locked in a compiled HAL. It is not — it is
  `/etc/RT5506` in the ROM, a plain-text register table of 21 modes. See
  [`rt5506.md`](rt5506.md), including the question that has to be answered
  first: whether it is an analog amplifier or a codec, which decides both the
  driver's shape and whether the headphone routing on the card above is right.
- `dtbs` builds clean, but three pre-existing warnings appear from the port's own
  DT, not from this change: `usb@7d000000` / `usb@7d004000` / `usb@7d008000`
  each share a unit address with their `usb-phy@` sibling.
