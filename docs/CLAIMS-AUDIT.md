# What is proven, what is only plausible, what is unknown

Version 20260914.04. Every row names the raw evidence it rests on, what that
evidence actually supports, the alternative explanation that has not been
excluded, and the one experiment that would decide it.

A claim is **PROVEN** only if a measurement exists that would have come out
differently had the claim been false. Everything else is PLAUSIBLE or UNKNOWN,
however well it fits the story.

## RESOLVED 2026-09-14: converter 0x0a's channel count

    converter 0x0a   cvt_chan_count   0x03  ->  0x00

Measured either side of one deep suspend, **speakers confirmed audible before
and silent after**, across 722 capability-validated fields. It is the only
functional field in the entire codec that moves, at rest and with a
four-channel stream actually running.

One limit of that comparison, found 2026-10-15: the capture tool read every
amplifier gain/mute field as the input amplifier, right channel, index 0,
because it put the direction and channel selector into the 8-bit parameter
the hwdep ioctl passes, where the codec never sees it. Amplifier output state
either side of the suspend was therefore not compared, and "the only field
that moves" holds for the other fields only. macbook91-codec-state now
addresses the amplifiers correctly. The fix itself is measured on its own:
with the channel count programmed on resume the speakers play after deep
suspend (gate fix.cvt_chan_count_programmed in docs/test-status.json).

The register holds **channels - 1** (`sound/hda/core/hdmi_chmap.c:199-210`).
Firmware programs four channels at power-on; a suspend leaves one. The stream
format word is untouched — `0x4013`, four channels, 44.1 kHz, 16 bit — so
everything that looks at the format sees a correct four-channel stream while
the converter emits a single channel into a TDM frame the four TAS5758L
amplifiers read as four slots.

**Why nothing in Linux put it back.** `sound/hda/core/regmap.c:132` keeps
`AC_VERB_GET_CVT_CHAN_COUNT` out of the HDA regmap's writeable set, under the
heading *"basically writable, but disabled for reducing unnecessary writes at
sync"* and commented *"managed in HDMI CA code"*. So `snd_hda_regmap_sync()`
never replays it — and this codec has no HDMI CA code to manage it. The
vendored sequence never writes it either (it does not name the register at
all). How upstream produced the sequence is not documented
(`src/cs420x-a1534/vendored/PROVENANCE.md`), so this document does not say
which machine state it was made from.

**Why headphones always worked.** Converter `0x02` reports no
`AC_WCAP_CHAN_CNT_EXT` at all. It has no such register to lose.

**Why s2idle failed identically.** The codec is reset either way; the platform
rails were never the question.

Everything the amplifier story was built to explain is explained by this
instead, and without needing the amplifiers to be reachable, unprogrammed, or
unpowered. Claims D2, D3 and D6 below remain unknown and are now also
unnecessary.

## The headline

> **The amplifier read procedure this project has used since the amplifier bring-up was added has never
> been validated, and the one control that was run argues that it is invalid.**
> It returned `0x0000` from all four amplifier addresses *and* from address
> `0x20`, where nothing lives, in the same sweep, on a machine whose speakers
> were working. A procedure that answers identically for a present device and
> an absent one has measured neither. Every statement about the amplifiers
> being unreachable, unprogrammed or lost across suspend rests on that
> procedure and is therefore withdrawn — not reversed, withdrawn.

## Audit table

### A. "Headphones are audible after resume through hw:0,0, 4-channel S16_LE"

| | |
| --- | --- |
| Raw evidence | `~/a1534-triage-20260914T114103Z.txt` (the raw triage log, not part of this repository), section I; user confirmation "HEADPHONES: AUDIBLE" |
| Supports | The controller, DMA, stream tag, the codec's command path, converter `0x02`, pin `0x10` and the driver's jack/route logic all work after a resume. |
| Does **not** support | Any statement about converter `0x0a`, pin `0x1d`, TDM clocking or framing, the speaker mute path, or the amplifiers. `a1534_format_for()` rewrites the channel nibble to 2 for converter `0x02` (`a1534_pcm.h:109`), so the two paths do **not** receive identical converter programming even from one PCM. |
| Alternative | The headphone test ran in section I, **after** the DFET GPIO sweep, a module reload and an optional PCI remove/rescan. Any of those could have re-initialised part of the hardware. Plugging the jack itself runs `a1534_hp_jack_callback()`, which replays the bring-up. |
| Decisive next | Capture converter `0x0a`'s stream format, `0x1d`'s pin-ctl and the amp-path state immediately after resume, **before** any intervention, from a fresh baseline arm. `macbook91-runner cycle` does exactly this and does nothing else first. |
| Status | **PLAUSIBLE as stated, over-read as used.** |

### B. "All 1209 registers are restored"

| | |
| --- | --- |
| Raw evidence | `tools/macbook91-codec-dump` output pair in `/tmp/a1534-triage-20260914T114103Z-codec-{before,after}.txt` (raw dumps, not part of this repository) |
| Supports | That 1209 **printed fields** compared equal. |
| Does **not** support | Completeness. 1209 is a count of emitted lines, not of independent valid hardware reads. The dump has a fixed NID/verb list, duplicates `pin_sense`, has no dynamically validated register map, reads no amplifier register, and does not check per widget whether a verb is supported. `OSError` is skipped in places, and in the coefficient path a `None` can reach a mask. It also calls itself "no writes of any kind" while issuing `SET_COEF_INDEX` (0x500) 128 times — an index write is a write. |
| Alternative | Two snapshots can match while reset state, clock state or sequencing differ, none of which any of these verbs expose. |
| Decisive next | Replace the fixed list with a map derived from each widget's own `AC_PAR_*` capabilities; mark unreadable/errored fields distinctly from zero; and run the comparison with and without the dump in between to show the dump itself changes nothing. |
| Status | **MISSTATED.** The comparison is real; "all" and "1209 registers" are not. |

### C. "Address 0x20 answers identically to 0x6c-0x6f, therefore the amps cannot be reached"

| | |
| --- | --- |
| Raw evidence | `macbook91-dfet-probe` output; `macbook91-i2c-probe` output; `macbook91-i2c-clock-probe` before/after |
| Supports | That this read procedure returns the same value for every address tried. |
| Does **not** support | Physical unreachability. It is the definition of an uncalibrated instrument: the same reading appeared while the speakers were working, which is the one state in which the amplifiers are known to be alive. |
| Alternative | The read path is wrong or incomplete. Three concrete candidates, all now documented: the kernel path omitted the closing STOP (`docs/APPLE-I2C-AUDIT.md` §7 D1, fixed); the data register `0x15` does not read back what is written to it while `0x14` does; and the control register `0x16` retains `0x02` long after the transaction, so nothing is consuming commands. |
| Decisive next | `sudo macbook91-runner probe` — `transport.discriminates`. It is written so that a FAIL means "this instrument reads nothing", not "the amplifiers are absent". |
| Status | **WITHDRAWN.** Not reversed: nothing is claimed about the amplifiers in either direction. |

### D. "The four TAS5758L lose configuration in S3 and firmware programs them only at power-on"

Four separate claims that were being carried as one.

| # | Claim | Status | Evidence / what is missing |
| --- | --- | --- | --- |
| D1 | Four TAS5758L amplifiers exist at I2C `0x6c`–`0x6f`, TDM slots 0/1/0/1 | **PROVEN from Apple's data** | `layout121.xml`: four `TDMDevices`, `Device` = 22360 = `0x5758`, `I2Caddress` 108–111, `Bus` 1/1/2/2, `TDMSlot` 0/1/0/1. Corroborated by `TAS5758L::enable` reading `I2Caddress` at `this+0x5a`. This says what Apple's layout declares for this codec; it is not an electrical measurement of this unit. |
| D2 | Their supply drops in S3 | **ARGUED AGAINST** | **s2idle leaves the speakers silent too** (maintainer-reported, 2026-09-14, cycle at 13:45:21). s2idle does not enter S3 and keeps platform rails up, so a fault that survives it is not a platform-supply fault. Not proof: the codec can still reach D3 under s2idle, and the DFET GPIOs are codec-driven, so a codec that loses power could drop the amplifier supply with it. But it points the same way as D6. |
| D2b | (superseded) Their supply drops in S3 | **UNKNOWN** | No measurement exists. `CHDFETControl` = GPIO 4 and `USDFETControl` = GPIO 5 are declared in the layout, and both currently read **enabled, output, data 0** while the speakers work — so "data high = supply on" is not established, and the earlier DFET sweep drove them high on that assumption. |
| D3 | They lose their register configuration | **UNKNOWN** | Depends on D2 and on a read path that works (C). |
| D4 | Mac firmware programs them at power-on and never again | **CONTRADICTED for the programming step** | `AppleHDATDMAmpTAS5758L::init` ends with `this->enable(true)` (0xa2e126, vptr+0x1a8 → 0xa2e1b4). **AppleHDA programs the amplifiers itself**, once, when `setupTDMDevices` builds the device list — not firmware, and not per stream (`AppleHDAPath::enable` never calls that slot). What firmware does before AppleHDA loads is still unknown. |
| D6 | The amplifiers must be reprogrammed after a sleep | **DOUBTED** | `TAS5758L` has no `performPowerRailSave`/`Restore` at all, while `TAS5764L` has both and so do several widget classes. If these amplifiers lost their configuration in S3, macOS would need a restore path and Apple would have written one. There is none. Either the configuration survives — making D2/D3 false and the resume fault codec- or TDM-side — or something outside AppleHDA re-establishes it. Not settled; macOS's behaviour on this unit after sleep has not been observed. |
| D5 | Nothing in Linux has ever reprogrammed them | **PROVEN** | Trivially: no Linux driver contains the sequence. |

### E. Claims found wrong in this session's own earlier reasoning

| Claim | Status | Why |
| --- | --- | --- |
| "The HDA regmap cache answers `GET_PROC_COEF` from a shadow copy / drops a repeated `SET_COEF_INDEX`" | **REFUTED** | `snd_hda_codec_read/write` → `snd_hdac_codec_read/write` → `codec_read/codec_write` → `snd_hdac_exec_verb`, straight to the controller (`device.c:1066-1091` of the Linux 7.2.4 tree, which is not part of this repository). regmap is not in this path. `snd_hda_codec_write_cache()` would be, and is not used. |
| "Apple pulses the I2C enable bit" | **REFUTED** | `enableI2C` toggles then sets; with bit 3 initially clear (as it is here) that is SET, SET. |
| "`a1534_amp` has no `bus` field, so bus dispatch may be missing" | **RESOLVED, nothing missing** | `TAS5758L::enable` calls `i2cWrite(addr, reg, val)` with no bus argument. "Bus 1/2" in the layout are TDM audio buses. |
| "The amplifier bring-up verified 0 of 4, so the transport does not reach the bus" | **VOID** | The verification used the same unvalidated read path (C), and the kernel path was additionally missing the STOP. |

### F. Facts established in this session that change the ground

| Fact | Evidence |
| --- | --- |
| `/sys/power/mem_sleep` is currently **`[s2idle] deep`** — this machine is **not** in deep suspend mode right now | read live, 2026-09-14 |
| An **s2idle** suspend was already performed in this boot, at 13:45:21, and left no `A1534` resume log at all | `journalctl -k -b 0`: `PM: suspend entry (s2idle)` / `PM: suspend exit`, no codec activity between |
| A **deep** suspend in this same boot at 13:40:44 *did* restore correctly: `restored 128 coefficients, 19 pin configs, digi 0x111`, `pin 0x1d after restore: 90100110 (want 90100110)` | same journal |
| Pin `0x1d` is right now `0x90100110` with `Pin-ctls 0x40 OUT`, and the speaker PCM offers 4 channels — the codec-side configuration is intact after both of those suspends | `macbook91-runner preflight`, run `20260914T120925Z` |
| The SSID gate works: the 13:41:13 re-probe reported `SSID 1013:4208` and still took the A1534 path | same journal |
| The I2C address register `0x14` latches; the data register `0x15` does not read back what was written; the control register `0x16` retained `0x02` across minutes | journal dump at 13:41:13, `coef 10: … 0041 0000 0002 0000` |

**What this does not settle:** whether the internal speakers actually produce
sound right now. Nothing in software can answer that, and it is not claimed
either way.

## What the last two suspends showed

Boot of 2026-09-14 14:25:20, the build before the channel-count fix, `mem_sleep` = `s2idle [deep]`
(deep selected). Deep suspend 14:26:28 → 14:26:33:

    A1534: restored 128 coefficients, 19 pin configs, digi 0x111
    A1534: pin 0x1d after restore: 90100110 (want 90100110)

After the resume, `subsystem id 0x106b6500`, speaker PCM 4 channels, pin
`0x1d` `0x90100110` with `Pin-ctls 0x40 OUT`, loaded module matching disk.
Everything this driver knows how to check is correct, and the speakers are
silent anyway.

Combined with s2idle failing the same way and with AppleHDA having no resume
path for these amplifiers (§D6), the centre of gravity has moved: **the thing
that silences the speakers after a resume is not yet captured by any state
this project inspects.** That is what `macbook91-codec-state` exists to
change — a capability-validated capture of every readable field, taken in the
working state and in the fault state, and diffed.

## The measurement, 2026-09-14 12:55 UTC

Cold boot, the same build, `mem_sleep` deep, **speakers confirmed audible by the
maintainer**. One capture. Then one deep suspend, resume, second capture. Both
35 nodes, 582 fields, **0 read errors**.

**One functional field differs:**

    subsystem_id_verb    106b6500  ->  10134208

The 128 vendor coefficients, all 19 pin configuration defaults, every pin
control, every amplifier gain/mute pair, every power state, every stream
format, and GPIO data/mask/direction `07`/`37`/`31` are **byte-identical**.

Two things follow, and only two.

1. The subsystem id is firmware-programmed state that a deep suspend
   destroys — the same degradation a PCI re-probe causes. It is the only
   readable firmware-owned register the driver does not restore. It is the
   fingerprint of a codec reset. It is **not** expected to affect audio and
   must not be "fixed" as though it would.
2. Everything else the driver restores, it restores correctly. Whatever
   silences the speakers is **not** in the codec's readable register state.

**The caveat that matters:** both captures were taken at rest, with every
widget reporting power `0x33` — setting D3, actual D3 — and converter `0x0a`
showing a stale latched format. State that only exists while a stream is
running was not compared. That is `hw.state_capture_streaming`, and the
capture also now includes `STRIPE_CONTROL`, which the first pass missed.

### And the transport is not an instrument

Same run, in the working state:

| test | result |
| --- | --- |
| `transport.coef_writes_stick` | PASS — `0x14` read back `0055`, `00aa`, `0000` as written |
| `transport.bridge_latches` | PASS — coefficient `0x00` `00c4` → `00cc`, bit 3 set |
| `transport.engine_responds` | BLOCKED — `0x16` holds `0004` with the bridge open **and** closed; a latch and a level control line are indistinguishable here |
| `transport.discriminates` | **FAIL** — `0x6c`, `0x6d`, `0x6e`, `0x6f`, `0x20`, `0x50`, `0x7e` all returned the same all-zero map |
| `transport.timing_sensitive` | PASS — a 1 ms settle after every step changed nothing |
| `probe.restored_entry_state` | PASS — coefficient `0x00` back to `00c4` |

The read path returns no information. Claim C stays withdrawn, now on a
measurement with three negative controls rather than one. One asymmetry is
worth recording: coefficient `0x14` latches what is written and coefficient
`0x15` never does — a written register number reads back as zero every time.
That is equally consistent with a write-only transmit register whose read
returns the (empty) receive path, and with writes being dropped.

## What is still open after this

> **Superseded, 2026-10-15.** This section and the next are kept as written
> on 2026-09-14. Since then the fix was verified on hardware
> (`fix.cvt_chan_count_programmed`, 2026-09-14) across five deep suspends of up
> to 1 h 44 min (`hw.long_suspend_coverage`, 2026-09-15); a playback survives a
> headphone plug and unplug (`regress.jack_hotplug_stream`), but a running
> capture does not survive the plug (`regress.concurrent_capture`, FAIL on
> 2026-10-19, `docs/INCIDENT-20261019.md`; the PASS of 2026-10-06 never had a
> real plug); HDMI is outside the
> validated scope by the maintainer's decision (`hw.hdmi_preserved`, SKIPPED); and the
> probe ran (`transport.discriminates` FAIL, 2026-09-14), so the transport point
> stands. No gate covers the microphone after a deep suspend on its own.
> `docs/test-status.json` is the current record.

- The fix is **built and not yet verified on hardware**. Three consecutive
  deep cycles with sound confirmed by ear is the minimum acceptance, per
  the audio task statement of this investigation.
- The amplifier transport remains not an instrument (`transport.discriminates`
  FAIL). Nothing is concluded from it in either direction, and the amplifier
  bring-up stays off by default.
- Whether the microphone, headphone hotplug and HDMI survive the same cycle
  is a regression question the acceptance run has to answer.

## The one thing to do next

`sudo macbook91-runner probe`. It is read-only with respect to every amplifier
register, restores the I2C bridge byte-exact, plays no audio, and its central
test is written so that failure means "this instrument measures nothing",
which is a result, rather than a statement about the hardware, which it would
not have earned.
