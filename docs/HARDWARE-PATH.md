# A1534 hardware path — what the evidence does and does not establish

Version 20260914.01. Phase 4 of the audio task statement.
Every item is classified **confirmed** / **strongly indicated** / **speculative**.
No register value, GPIO state, coefficient or channel map is invented here; where
the evidence stops, this document says so.

## 1. Output topology — confirmed

From the live codec dump (baseline capture 20260914T050602Z, `34-codec-dump-0.txt`; a local capture, not part of this repository):

| Path | Pin | Converter | Nature |
| --- | --- | --- | --- |
| Internal speakers | `0x1d` `[Fixed] Speaker at Int`, cfg `0x901600f0` | `0x0a` | **digital, 8-channel**, 44.1/48 kHz, 16/20/24 bit |
| Headphone jack | `0x10` `[Jack] HP Out at Ext Left`, cfg `0x032b401f` | `0x02` | analog stereo, amp, HP-detect, unsol tag 01 |
| Analog speaker pins (unused) | `0x11`–`0x14` | `0x02`–`0x05` | all `Pin-ctls: 0x00`, never enabled |

**Confirmed:** the historical "Speaker = Converter 0x0a / Pin 0x1d, Headphone =
Converter 0x02 / Pin 0x10" claim is correct on this machine.

## 2. Capture path — confirmed

`Mic = 0x18` (external, jack, unsol tag 02), `Internal Mic = 0x19` (digital,
`Internal Mic Boost Volume` present). ADC `0x07` carries `Capture Volume` /
`Capture Switch` and is the ADC bound to PCM `hw:0,0` capture. Capture is
already exposed by the stock driver and is independent of the speaker defect.

## 3. Speaker amplifier topology — strongly indicated

`AppleHDAHardwareConfigDriver` `Info.plist` (macOS 12.5.1, build 21G83) carries
three CS4208 layouts (**121, 127, 129**) that are **byte-identical in every
hardware-relevant field**. Summarised from those layouts:

| Amplifier | Type | I2C address | TDM bus | TDM slot |
|---|---|---|---|---|
| 1 | TI TAS5758L, mono (device type 22360) | 0x6c | 1 | 0 |
| 2 | same | 0x6d | 1 | 1 |
| 3 | same | 0x6e | 2 | 0 |
| 4 | same | 0x6f | 2 | 1 |

The codec settings of the same layouts name GPIO 5 and GPIO 4 as the controls
of two supply FETs (DFET), GPIO 1 as the amplifier fault input (fault reads 0),
select analogue supply setting 5 and polling of the S/PDIF input, and enable
both TDM interfaces with a sample-rate multiple of 64.

So the internal speakers are **four mono TI TAS5758L smart amplifiers** fed by
TDM over the digital pin `0x1d`, two amps per TDM bus, plus DFET (supply FET)
control on **GPIO 4 and GPIO 5** and an amp-fault input on **GPIO 1**.

This is corroborated by the live codec: `GPIO: io=6` (GPIO 0–5 exist), which
accommodates GPIO 1, 4 and 5. It also explains why converter `0x0a` is an
8-channel digital converter: TDM slots, not discrete analog outputs.

Classified *strongly indicated* rather than confirmed only because the archive
contains no model→layout-ID mapping (the `layout-id` property comes from EFI,
not from the kext), so we cannot prove *which* of 121/127/129 this machine
uses. Since all three are identical in these fields, the distinction does not
affect any decision.

**Live corroboration of the defect:** the stock driver enables only GPIO 0:

```
IO[0]: enable=1, dir=1, data=1      <- cs4208_fixup_gpio0(), EAPD
IO[1]: enable=0 ... IO[5]: enable=0 <- DFET (4,5) and amp-fault (1) untouched
```

The DFET GPIOs that gate the speaker amplifier supply are never driven.

## 4. Channel count — strongly indicated, NOT yet actionable

Four mono amplifiers on four TDM slots indicate a **four-slot** speaker stream,
consistent with converter `0x0a` advertising 8 channels.

**The physical meaning of each slot is NOT established.** The evidence gives
bus/slot/I2C addresses but no mapping from slot to a physical driver
(left/right, woofer/tweeter). Per Phase 6 of the audio task statement, no four-channel
probe and no four-channel WirePlumber policy may be enabled until that mapping
is proven on hardware at low volume. Treat any slot→speaker assignment as
**speculative** until measured.

## 4a. Measured slot mapping and rate (test machine, 2026-09-14)

Established by playing one TDM slot at a time at 12% of full scale:

| Slot | Heard | Confidence |
| --- | --- | --- |
| 0 | left | clear |
| 1 | right | clear |
| 2 | centrally, could not localise | **uncertain** |
| 3 | right | uncertain |

Read together with AppleHDA's two TDM buses of two slots each
(§3), the consistent interpretation is **two drivers per side**, i.e. two
duplicate stereo pairs rather than a surround layout — so slot 2 is most
likely the second left-side driver. Classified **strongly indicated**, not
confirmed: the listener was explicitly unsure about slots 2 and 3, and no
measurement distinguishes "second left driver" from "a right driver heard
centrally".

Consequence: PipeWire must present the device as `FL/FR/RL/RR` (there is no
way to express duplicate positions), so stereo content would otherwise reach
only slots 0 and 1. The shipped WirePlumber rule therefore enables
`channelmix.upmix` with `upmix-method = simple`, a verbatim front→rear copy,
rather than the default `psd` method which synthesises a pseudo-surround rear
channel and would be wrong for duplicate pairs.

**Sample rate — confirmed.** The same tone is clean at 44.1 kHz and audibly
distorted at 48 kHz. The codec advertises both for converter `0x0a`, but the
amplifiers are clocked from the codec (`SRMultiple = 64`) and only track the
rate the bring-up programs: format `0x4013` = 44.1 kHz. The driver now
restricts the speaker PCM to 44.1 kHz; userspace resamples.

## 5. What the evidence does NOT contain — a hard limit

Two of the four named evidence sources yield nothing usable for this machine:

### 5.1 Boot Camp material is for the wrong codec — confirmed

`bootcamp/extracted/cs420x_46.inf` (Cirrus, 2009–2014) declares **only**
`DEV_4206` (94 ids) and `DEV_4207` (24 ids). It contains **no `DEV_4208`
entry at all**, and no `SUBSYS_106B6500` (its highest Apple subsystem is
`106B7A00`). `CS420X64.sys` strings contain no occurrence of "4208".

Despite the installer being named `CirrusAudioCS4208x64.exe`, the Boot Camp
reference **cannot** describe the MacBook9,1 CS4208 path. It is excluded as
evidence for this project.

### 5.2 AppleHDA contains topology but no amplifier programming — confirmed

The CS4208 `ConfigData` for layouts 121/127/129 is 16 bytes, identical in all
three, and decodes to four verbs on **NID 0x22 only**: the four
`SET_CONFIG_DEFAULT` byte verbs, one per byte of the pin configuration default.
Together they rewrite the pin config default of `0x22` (SPDIF In) to
`0xd0c60040`, matching the `PostConstructionInitialization` entry for the same
layouts. **There is no speaker-amplifier init, no vendor coefficient sequence
and no GPIO programming in AppleHDA's CS4208 data.** That work is done by
`AppleHDAController`'s TDM/I2C machinery, of which the archive holds only
extracted strings — and those contain **no `TAS5758` and no register
sequences** (the `I2C*` hits are generic IOKit symbol names).

### 5.3 Consequence

**The A1534 speaker initialization cannot be independently re-derived from the
supplied evidence.** The archive establishes the *topology* (§3) but not the
*programming*.

The only concrete initialization available is the sequence in the
bundled out-of-tree snapshot, `patch_cirrus_a1534_setup.h` — and per
`docs/EVIDENCE-MAP.md` §B that snapshot has **empty provenance metadata**
(all four `linux-driver-metadata/*` files are 0 bytes).

Its character, measured: 373 `AC_VERB_PARAMETERS` reads, 223
`AC_VERB_SET_POWER_STATE` writes, 47 touches of vendor widget `0x24`, but only
7 `SET_COEF_INDEX` and **2** `SET_PROC_COEF`. That reads like a **replayed verb
trace** (this project's shorthand; the upstream README says only that the
module replays the macOS init, and how the sequence was obtained is not known,
see `src/cs420x-a1534/vendored/PROVENANCE.md`), not a derived
initialization.

Therefore any A1534 init in this project must be labelled **empirical, not
derived**, and can at best be classified *strongly indicated* after it is
demonstrated to work on this machine. It must never be reported as confirmed
on the strength of the archive.

## 6. Open risk carried forward

Phase 4 of the audio task statement flags that the headphone sequence may drive the whole
AFG through D3/D0. The bundled snapshot contains **223 `AC_VERB_SET_POWER_STATE`
and 134 `AC_VERB_GET_POWER_STATE`** operations, so the concern is well founded
and concrete. It does break a concurrent capture, and a concurrent playback
survives (measured 2026-10-19, section 6.4).

### 6.1 The mechanism, measured

Counted directly over the derived `vendored/a1534_sequence.h`, which the build
makes from the tracked `ORIGINAL-a1534_sequence.h` and `a1534_sequence.patch`
(see `vendored/PROVENANCE.md`); the count is `tests/run-tests.sh` "7e.
Concurrent-capture / jack-power census":

| function | AFG → D3 | AFG → D0 | runs when |
| --- | --- | --- | --- |
| `headphones_a1534()` | 8 | 9 | headphones plugged, from `a1534_hp_jack_callback()` |
| `play_a1534()` | 0 | 1 | headphones unplugged, same callback |

Putting the audio function group in D3 powers down every widget beneath it,
including the ADCs of a running capture. So a headphone plug during a
recording has a concrete mechanism for corrupting or killing it; section 6.4
records that a plug does stop it.

### 6.2 The measurement procedure

`sudo ./tools/macbook91-runner jackstream` starts a real capture and a
safe 4-channel playback (the same 12%-of-full-scale tone the verifier uses,
never `speaker-test`) on the internal device, prompts the user to plug the
headphones once and unplug them once, and after each transition checks
whether the capture survived (process alive, the file kept growing, no
overrun/broken-pipe/EPIPE in `arecord`'s own error output), whether playback
survived, whether a capture started after the transition records, and the
codec power state of the AFG and the ADC via `macbook91-codec-state`; the
capture result names the stream tags of the ADCs `0x06` and `0x07`. Before
each prompt it waits for the jack to read the opposite state, so a plug that
happened before the prompt is BLOCKED instead of counted. It writes no
amplifier register, loads no module, and changes no persistent configuration.
The packaged `macbook91-audio-verify` keeps a capture running across its
headphone plug and unplug as well.

### 6.3 The options that become choosable once the result exists

This section does not pick one - that is a design decision for whoever reviews
the `jackstream` result, not something to decide in advance of the evidence:

1. **Leave as is.** Justified only if the measurement shows the capture and
   playback both survive the power cycling unharmed.
2. **Skip the replay while any stream is running, and re-point the stream
   only.** If a stream is active, defer the amplifier bring-up/teardown
   until it ends, and just re-route the existing stream to the new DAC in
   the meantime.
3. **Narrow the replay to the widgets that actually need it.** Most of the
   223 `AC_VERB_SET_POWER_STATE` operations are almost certainly touching
   widgets that do not need a full AFG-level D3/D0 cycle at all; a replay
   scoped to the amplifier path specifically would leave the ADC alone.
4. **Re-program what the replay resets.** Keep the replay as traced and
   write the running capture's converter setup back after it.

### 6.4 The result (2026-10-19)

The measurement rules out option 1. With a capture running on `hw:0,0` and a
silent playback keeping the codec awake, a headphone plug stopped the capture
(`arecord`: Input/output error); capture converter `0x06` read stream tag 0
afterwards, and every capture opened later stayed silent until the codec
runtime-suspended. The playback survived (`docs/INCIDENT-20261019.md`). The
earlier PASS records never had a real plug: the headphones were already in
when the runner asked for it.

The driver now takes option 4, because it changes nothing in the traced
sequence: `a1534_capture_resync()` in `a1534_pcm.h` drops the HDA core's
cached converter setup and writes the stream tag and format back, after every
headphone replay and on every capture prepare. Options 2 and 3 stay open if
the replay turns out to disturb anything else. The fix was measured on
hardware on 2026-10-20 with 20261020.01 installed, by the procedure of
section 6.2: `macbook91-runner jackstream` run `20261020T063948Z-5274`,
`regress.concurrent_capture` PASS.
