# Audio bring-up for flounder

> **Hardware status (2026-10-19):** first test boots done. Modules load, but no
> card has registered yet. See “First hardware test” at the end of this note.

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

## How downstream modelled the speaker link, and why this differs

Worth recording, because the card here does it differently and the difference
should be deliberate rather than accidental.

Downstream's `tegra_rt5677.c` declares its speaker link with a **dummy** codec:

```c
.codec_name     = "spdif-dit.0",
.platform_name  = "tegra30-i2s.2",
.cpu_dai_name   = "tegra30-i2s.2",
```

`spdif-dit.0` is a stub SPDIF transmitter — it is not the amplifier. The
tfa9895s appear in that driver only as function calls, `set_tfa9895_spkamp(1, 0)`
and `set_tfa9895l_spkamp(1, 0)`, made from the PCM `startup` and `shutdown`
callbacks on playback.

So downstream's model is: a link whose codec is there to satisfy ASoC, with the
real amplifiers enabled over I2C from stream callbacks.

The card here instead puts the two `nxp,tfa9895` amps on the link as codecs,
which relies on their own DAPM `POWER` widget powering up when the PCM starts.
That should come to the same thing, and is the more conventional modelling —
the amps really are I2S-attached devices with DAIs, which is why the generic
binding describes them with `#sound-dai-cells`.

**What is not established** is whether it does come to the same thing on this
hardware. If the speaker path stays silent despite binding, the first thing to
try is reproducing downstream's shape: a dummy codec on the link plus an
explicit enable from the stream callbacks, which is a small change to the
machine driver already added.

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

## First hardware test (2026-10-19)

Image `n9audio-bind-stripped.img`: current `init-auto.c` with `/etc/audio`,
`/etc/no-wifi`, kernel `#116` (`6.19.0-htc-flounder-g65429d8f78f5`).

- **Boot 1 stalled.** Mode B (gadget enumerated, serial silent, no watchdog
  reset). The rolling record was untouched from the previous soak, so init
  never reached its first write — the stall landed before ~6 s. Power cycle
  needed. Boot 2 was healthy, so this was the known intermittent stall, not
  the image (see `stability-debug.md`).
- **The auto module load was broken — init passed `.ko` names.** Busybox
  `modprobe snd-soc-tegra30-ahub.ko` loads the file verbatim and skips
  `modules.dep`, so `snd`, `snd-pcm` and friends never loaded; `snd-soc-core`
  then failed with `Unknown symbol snd_pcm_lib_ioctl` (and ~30 more).
  Symptom: only `snd_soc_tegra30_ahub` in `/proc/modules`, no
  `/proc/asound/cards` at all.
- **Plain names work.** Manually, all returned rc=0:
  `snd`, `snd-pcm`, `snd-soc-core`, `snd-soc-tegra30-i2s`,
  `snd-soc-rt5677`. So dependencies are fine when modprobe sees names.
- **`modprobe snd-soc-tfa989x` hung the console.** The shell blocked in the
  modprobe and never returned; typed input was still echoed by the tty, and
  the userspace watchdog pinger kept running (no reset in 2.5 min), so this
  is a task-local hang, not a machine stall. Recovery needs a power cycle.
  Nothing has yet checked whether the codec probe or the shared `spk_ldo`
  regulator is the blocker.

Fixed in `init-auto.c`: audio modules now load by plain name, core first, and
`tfa989x` is left out of the automatic sequence until its probe behaviour is
understood. Next: rebuild, verify `/proc/asound/cards` and the `rt5677 1-002d`
bind in dmesg, then exercise the tfa989x probe by hand with a timeout.

## Root cause found: the codec supply gates (2026-10-19 23:00)

`rt5677 1-002d: Device with ID register 0x0 is not rt5677` was **not** an I2C
problem. The downstream machine driver's power sequence
(`tegra_rt5677.c`, board file `board-flounder.c`) enables, in order:

1. `gpio_ldo1_en` **PK0** — V_IO_1V8
2. palmas **LDO2** — V_AUD_1V2 (`vdd_audio`, already modelled)
3. `gpio_int_mic_en` **PV3** — V_AUD_1V8
4. `gpio_reset` **PX4** — released last

Our DT carried only LDO2 and reset, so the codec's I/O rail never came up and
the ID register read 0. Modelling PK0 and PV3 as `regulator-fixed` rails with
`regulator-always-on` (in `tegra132-flounder.dts`) fixed it: the driver now
binds with no ID error, and with `snd-soc-tegra30-i2s` loaded the card
appears:

```
 0 [G9             ]: tegra - Google Nexus 9
  2: [ 0- 0]: digital audio playback
  3: [ 0- 0]: digital audio capture
  4: [ 0]   : control
```

Two build/init traps found on the way:

- `run()` forks without waiting, so the init's modprobe loop raced the
  dependency chain (`rt5677-spi` before `snd-soc-core`, `tegra30-i2s` skipped
  entirely). Now a single sequential `busybox sh -c` loop.
- A `make` without `ARCH=arm64` ran oldconfig and clobbered the build
  `.config` (Tegra unset). Recovered exactly with
  `scripts/extract-ikconfig arch/arm64/boot/Image`.

Not yet done: audible playback (no `aplay` in the ramdisk), and the tfa989x
speaker amps still unloaded pending the probe-hang investigation.

The automatic path is verified on `n9audio4-stripped.img`: after the sequential
load fix, the `G9` card registers with no manual commands.

## Priority (2026-10-20)

Speaker output is the requirement; headphones do not matter for the
daily-usable target. That removes the blocked rt5506 path from the critical
list and puts the tfa989x amplifier probe hang first in line: the codec and
card already work, so the remaining speaker blocker is the amplifier driver.

## 2026-10-22 00:20 — speaker PCM stream runs end to end (audibility to be confirmed)

Root causes found on the way (all on the consistent kernel `...g6988accc2d82`):
1. The `tfa989x` "probe hang" was the Palmas PMIC interrupt storm starving the
   PMIC I2C bus (see `stability-debug.md`); fixed by dropping
   `nvidia,invert-interrupt` from the PMC node. After that
   `modprobe snd-soc-tfa989x` returns and **both cards register**:
   `0 [speakers]`, `1 [G9]`; `/dev/snd/pcmC0D0p` is the speaker playback.
2. `tegra_machine_hw_params()` failed the stream with `codec_dai clock not
   set: -524` because the TFA9895 amps have no `set_sysclk`. Fixed in
   `sound/soc/tegra/tegra_asoc_machine.c` (tolerate `-ENOTSUPP`), kernel
   commit `6988accc2`, patch exported to `patches/`.
3. `tools/miniroot/tone-min.c` (freestanding, no alsa-lib): 48 kHz S16 stereo
   sine via raw PCM ioctls. `tone-min 0 0 2 440 10` -> hw_refine/hw_params/
   sw_params/prepare all 0, 96000 frames written, drain 0, no kernel errors.
   Amplitude is a % of full scale (10 % by default; the amps run untuned and
   have software volume only).
Open: whether anything is audible (needs a human ear), amp gain/protection
tuning, the headphone path (rt5506), mixer controls.

## 2026-10-22 00:45 — PARKED: speakers play "successfully" but are silent

State when parked (user heard nothing on 440 Hz / 880 Hz tones at 10 %, 3 s):
- PCM stream is clean: hw_params/sw_params/prepare ok, all frames written,
  drain 0, no xruns, no kernel errors. Kernel `...g6988accc2d82`
  (`tegra_asoc_machine` ENOTSUPP fix); images `n9dbgK` / `n9dbgL`.
- DAPM during playback is fully **On**: `Speakers`, both amps' `POWER`
  (R9 bit 0) and `AMPE` (R9 bit 3), amp input mux "Left".
- Rails enabled: `spk-ldo` (PX5), `vdd-aud-1v8`, `vdd-io-1v8`; `vdd-audio`
  reads 3.1 V (suspicious: the codec notes say 1.2 V, but it feeds the
  rt5677, not the amps).
- Pinmux: DAP3 pins PP0-PP3 = function `i2s2` (correct). Clocks running:
  pll_a 368.64 MHz -> pll_a_out0 12.288 MHz (extern1) -> i2s2 BCLK
  3.072 MHz (enable counts 1).
- NOT yet checked (next steps, in order):
  1. Read the amps' registers during playback with
     `tools/miniroot/i2cget-min` (now in `n9dbgL`): bus 1, slaves 0x34 and
     0x35, regs 00..0f. Status R0 (CLKS/PLLS/AMPS/SWS bits), REV R3 (0x18 for
     TFA9895), I2S control R4, SYS_CTRL R9. If CLKS/PLLS are 0 the amps are
     not seeing a valid BCLK.
  2. Pad properties of the DAP3 pins: tristate/enable-input in
     `pinconf-groups` (a muxed pad can still be tri-stated).
  3. I2S2 data path: AHUB routing and the tegra30 I2S2 TX enable (regmap
     `70301200.i2s`), DAI format/master mode set by the machine driver.
  4. Android's side: REA of `/vendor/lib64/hw/audio.primary*` and the
     downstream tfa9895 driver (it applies a config/patch over ioctl; the
     mainline driver is bypass-only and may need unmute/volume registers).
  5. Amp mixer controls (no `amixer` in the ramdisk; add a tiny control tool).
- Harness: console must be a piped non-interactive shell
  (`/etc/n9-plainsh`); `tools/n9boot.sh <img> load-audio` boots and waits;
  `tools/n9sh.sh '<cmd>' <secs>` runs a command (output of a long command can
  arrive one call late; send `echo x` to flush).

## 2026-10-22 02:15 — REA of Android's TFA9895 driver: what mainline is missing

Artifact: running Android kernel (sha256 `b26351cb…`, LNX partition), symbols
recovered from its own address table (see `stability-debug.md`), window
`ffffffc0008293c0-ffffffc00082b000`. Functions: `tfa9895_probe` 0x8294dc,
`set_tfa9895_spkamp` 0x829df4 (+ `tfa9895l_*` for the left amp), `tfa9895_ioctl`
0x8297dc. Registers are 16-bit big-endian.

Vendor bypass/"mode 0" recipe (probe and power-on), bytes read from the Image:
```
R4  = 0x8853     I2S register: I2SSR=8 (48 kHz), CHSA/format bits
R9  = 0x0619     SYS_CTRL: PWDN=1, AMPE=1, DCA=1 (boost), + bits 9,10
R9  = 0x0618     PWDN=0 (powered), AMPE=1, DCA=1
R8 |= 0x0400     speaker block (high byte bit 2)
power-off: R9 = 0x0619
other mode (flag != 0): R9&=~1, R6&=~0x20, then R9|=8   /   off: R6|=0x20, R9&=~8, R9|=1
```
Mainline `sound/soc/codecs/tfa989x.c` differs: it **clears DCA/CFE/AMPC**
(boost off), never writes R6 or R8, and only sets R4 sample-rate/channel
fields. Hypotheses for the silence, cheapest first (test with
`tools/amp-probe.sh`, image `n9ampA`, which prints R0 status incl.
CLKS/PLLS/AMPS after each step; no listener needed):
1. boost (DCA) off  2. R6 bit 5 (vendor clears it when enabling)  3. R8
bit 10  4. R4 I2S format/sample rate wrong for our 64fs BCLK.
Android also loads per-device tuning over `TFA9895_WRITE_CONFIG` ioctl from
the HAL; mainline runs the hardware defaults.

## 2026-10-22 07:45 — amp probe on hardware (image n9ampA/B, kernel ...g6988accc2d82)

Read-only first (both amps 0x34/0x35 on i2c bus 1, tone playing):
`R0=001d R1=02fe/02ff R2=0100 R3=0012 R4=880b R5=13ab R6=001f R7=0fe6 R8=3c4e R9=0208 R10=06c3`.
Idle (stream stopped): R0 still 001d, R9=0201 (PWDN). R3=0x12 = TFA9895.
- R0 never changes between idle and playing -> PLL/clock-stable bits never
  asserted; R1/R2 (battery voltage / temperature) read plausibly, so the
  analog side is alive and our register writes land.
- Ruled out as the cause (each tried with a single write, tone playing):
  R6 bit 5 (already 0), R8 bit 10 (already 1), R4=0x8853 vendor value
  (took, R0 unchanged), R9 DCA boost on (0x0218, R0 unchanged).
- Pad tri-state: the DT had the DAP3 pads (dout/fs/sclk) with
  `nvidia,tristate = <ENABLE>` (tri-stated). Changed to DISABLE/enable-input
  ENABLE in the working tree (uncommitted, image n9ampB): **R0 unchanged**,
  so not sufficient on its own (may still be required).
- I2S2 (70301200) registers during playback: CTRL=0x80000403 (TX enabled,
  MASTER_ENABLE, 16-bit), TIMING=0x1f (32-bit slots -> BCLK 3.072 MHz = 64fs).
  Machine driver dai_fmt for the speaker link = I2S|NB_NF|CBC_CFC (Tegra is
  clock provider). Clock tree: pll_a 368.64 MHz -> pll_a_out0 12.288 MHz ->
  extern1 / i2s2 (3.072 MHz) all enabled.
- Other facts: `dap_mclk1_pw4` = extperiph1, driven; amps need no MCLK per DT.
- Still open: do pins PP0-PP3 (DAP3) physically reach the amps? (downstream
  `board-flounder.c` + the two-source agreement in this note say yes); is
  R0 a latched/other-meaning register on this part; did the user hear anything
  during the boost toggle (07:41:12-07:41:31)? Next: per-pad register check,
  scope-free test by routing a GPIO-bit-banged BCLK/LRCK on PP3/PP0 and
  watching R0, and REA of the downstream pinmux table (nameless data array
  in the Android kernel; callers `tegra_pinmux_set_*`).
- Wi-Fi: Android's calibration files found: `/system/etc/wifi/bcmdhd.cal`
  and `bcmdhd_lte.cal` (BCM94354 WLBGA, xtalfreq=37400); copied to
  `~/Downloads/nexus9/firmware-extracted/wifi/` (not in the repo).

## 2026-10-22 09:10 — ROOT CAUSE FOUND: bootloader leaves DAP pads in GPIO mode

**Fix works on hardware**: with the stock mainline `tfa989x` driver and no
manual register writes, both amps report `R0 = 0xd05f / 0xd85f` (PLLS, CLKS,
AMPS... = the Android playing value) during a 1 % tone. Kernel
`6.19.0-htc-flounder-g96949bf28c4c`, image `n9ampL`. Not yet heard by ear (user
away); tone kept at 1 %.

Cause: Tegra `GPIO_CNF` for PP0-PP3 (DAP3 = I2S2 to the amps) was `0xf` =
**GPIO mode**, with PP0/PP2/PP3 as outputs driving low (`OE=0xd`). GPIO mode
overrides the pinmux's I2S2 function, so the amps never saw BCLK/LRCK. The
pinmux registers, I2S2 registers, clocks and amp registers all matched Android
exactly, which is why nothing in the earlier register-level work found it.
Port A (PA2-PA5 = DAP2 = I2S1 for rt5677/headphones) had the same leftover
(`CNF=0xbd`).

How it was found (evidence, trimmed):
- Android playing vs mainline playing: I2S2 CTRL/TIMING/OFFSET/CIF identical,
  pad regs `0x70003030-3c` = 0 (I2S2 mux, not tristated) identical, `drive_dap3`
  `0x00605008` identical, amp regs R4/R9/RA identical after writing Android's
  values, `i2s2` clock identical, PMC IO-DPD audio pad powered. Only the amps'
  R0 (and the MTP/trim regs 0x70/0x71/0x80-0x8d that appear after lock) differed.
- Bit-banging PP0/PP3 as plain GPIOs (`tools/miniroot/regdump/bitbang.c`,
  ~150 kHz BCLK, nowhere near 8 kHz fs) changed R0 to `0x801d` (AMPS) while
  real I2S2 never changed R0: the amps do listen to those pads, I2S2's output
  just wasn't reaching them.
- `GPIO_CNF` read (`regdump.ko`) showed `0x0f`; clearing it (`sfio.ko`) gave
  `R0=0xd05f` immediately.
- Fix = release the pads: `gpiod_get(ASIS)` + `gpiod_put()` runs
  `tegra_gpio_free()` which clears CNF. Implemented as optional DT property
  `nvidia,i2s-pad-gpios` read by `tegra_asoc_machine_probe()`.

Dead ends now explained / dropped:
- The `nvidia,i2s-bclk-1x` patch is NOT needed: default 64fs (3.072 MHz)
  locks too. Reverted (`d202c7477`), not in the patch series.
- Boost (DCA), R6/R8 bits, R4 vendor value: not needed for lock. R9 stays
  `0x0208` with the stock driver and the amps still lock.
- Kept: DAP3 pads un-tristated in DT (vendor un-tristates around playback),
  `drive_dap3` = Android's value (never tested whether it matters).

Tools added: `tools/miniroot/regdump/` (out-of-tree modules: `regdump.ko`
reads physical registers even where STRICT_DEVMEM blocks `/dev/mem`,
`padsample.ko`, `bitbang.ko`, `sfio.ko`; build recipe in the Makefile),
`tools/miniroot/tone-min` now takes a 6th arg = sample rate. Note: GPIO_IN does
NOT show SFIO pad levels (I2C pads read 0), so it cannot sample I2S pads.

Android reference (playing, both amps): R0 `d05f`, R4 `8853` (0x34) / `880b`
(0x35), R9 `0618`, RA `38d2`, 0x41 `0308`, 0x47 `5be1`, 0x48 `0180`, 0x49
`0e82`, 0x4b `181e`, 0x70 `0002`, 0x71 `0001`, 0x73 `00ff`, 0x80 `0003`.
Android during playback: `i2s2` on at 1.536 MHz, `i2s1` off, `extern1` off.

Next steps:
1. Let the user listen (tone-min, keep amplitude <= 10 %; both channels).
2. If quiet/distorted: R9 DCA boost, RA/R8 tuning, per-device config blob.
3. Headphones: rt5506 driver (not started); the DAP2 pad release is in but
   unverified by ear.
4. Check other pads the bootloader may have left as GPIO (BT UART, etc.).

## 2026-10-22 17:20 — speakers confirmed audible

User heard the 440 Hz tone at 10 % (`tone-min 0 0 6 440 10`) on image `n9ampL`
(kernel `g96949bf28c4c`); both amps R0 `0xd05f` during playback. Mainline
speaker output works with the stock `tfa989x` driver plus the pad-release fix.
Not yet checked: left/right channel assignment, volume/boost tuning, headphones
(rt5506, DAP2 pad release untested by ear).
