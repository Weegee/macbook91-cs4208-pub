# Root cause: silent internal speakers on MacBook9,1 (A1534)

Version 20260914.01. Baseline capture 20260914T050602Z (a local capture, not part of this repository).
Kernel `7.2.4-3-cachyos`. Every claim below is traced to either the live
machine or to kernel source at tag `v7.2.4`.

## 1. Summary

The internal speakers of the MacBook9,1 are wired to a **digital, 8-channel**
pin (`0x1d`) whose only source is a **digital-only converter** (`0x0a`).
The HD-audio generic parser cannot bind an analog PCM stream to a digital
converter, so **no ALSA PCM device is ever attached to converter `0x0a`**.
The only analog playback device the driver creates (`hw:0,0`, "CS4208 Analog")
is bound to converter `0x02`, which reaches the **headphone jack** pin `0x10`.

Consequently the speakers receive no audio stream at all. This is a *missing
data path*, not a muted or mis-initialised amplifier, and **no HDA fixup or
mixer setting can repair it** — a fixup can patch pin configuration, GPIO and
verbs, but it cannot invent a PCM on a converter the parser rejected.

## 2. The two output paths, confirmed from the live codec

From `34-codec-dump-0.txt` of that baseline:

```
Node 0x0a [Audio Output] wcaps 0x46631: 8-Channels Digital Stripe
  Digital:
  PCM: rates [0x60]: 44100 48000   bits [0xe]: 16 20 24   formats [0x1]: PCM
                                       (no "Device:" line -> bound to no PCM)

Node 0x1d [Pin Complex] wcaps 0x406301: 8-Channels Digital
  Pincap 0x00000010: OUT
  Pin Default 0x901600f0: [Fixed] Speaker at Int N/A
  Pin-ctls: 0x40: OUT
  Connection: 1
     0x0a
```

```
Node 0x02 [Audio Output] wcaps 0xd043d: Stereo Amp-Out Stripe
  Control: name="Line Out Playback Volume"
  Device: name="CS4208 Analog", type="Audio", device=0     <- the only PCM
Node 0x10 [Pin Complex] ... Pin Default 0x032b401f: [Jack] HP Out at Ext Left
  Pin-ctls: 0xc0: OUT HP
  Connection: 1
     0x02
```

**Confirmed:** speaker = Pin `0x1d` ← Converter `0x0a` (digital, 8 ch);
headphone = Pin `0x10` ← Converter `0x02` (analog, stereo, amp).
This independently reproduces the historical claim about these node numbers.

The analog pins `0x11`–`0x14` also carry `[Fixed] Speaker at Int` defaults and
feed converters `0x02`–`0x05`, but all four have `Pin-ctls: 0x00` — the driver
never enables them. They are the classic CS4208 analog speaker layout used by
other Macs; on this machine they are not the path in use.

## 3. Which fixup actually runs, and why

Kernel log, current boot:

```
snd_hda_codec_cs420x hdaudioC0D0: CS4208: picked fixup  for codec SSID 106b:0000
snd_hda_codec_cs420x hdaudioC0D0: autoconfig for CS4208: line_outs=1 (0x1d/...) type:speaker
snd_hda_codec_cs420x hdaudioC0D0:    speaker_outs=0 (0x0/...)
snd_hda_codec_cs420x hdaudioC0D0:    hp_outs=1 (0x10/...)
```

This line is fully explained by primary source, with no residual unknown:

1. `snd_hda_pick_fixup()` (`sound/hda/common/auto_parser.c`, v7.2.4) prints
   `q->subvendor, q->subdevice` — **the matched table entry's** ids, *not* the
   codec's own SSID, despite the wording "for codec SSID". So `106b:0000`
   identifies the entry, and the machine's real codec SSID stays `106b:6500`.
2. The empty fixup name is expected: `struct hda_quirk` only carries `.name`
   under `CONFIG_SND_DEBUG_VERBOSE`, and this kernel has that **unset**.
3. The matched entry is
   `SND_PCI_QUIRK_VENDOR(0x106b, "Apple", CS4208_MAC_AUTO)` from
   `cs4208_fixup_tbl` — subvendor `0x106b`, subdevice `0x0000`.

It matched through the *fallback* branch. In `snd_hda_pick_fixup()` the
primary loop is:

```c
for (q = quirk; q->subvendor || q->subdevice; q++) {
        if (!pci_vendor || !pci_device || q->match_codec_ssid) {
                if (hda_quirk_match(codec_vendor, codec_device, q)) { type = "codec SSID"; goto found_device; }
        } else {
                if (hda_quirk_match(pci_vendor, pci_device, q))     { type = "PCI SSID";   goto found_device; }
        }
}
/* match with the codec SSID */
q = hda_quirk_lookup_id(codec_vendor, codec_device, quirk);
```

On this machine `pci_vendor:pci_device` = `8086:7270` and
`codec_vendor:codec_device` = `106b:6500`. `SND_PCI_QUIRK_VENDOR` sets
`match_codec_ssid = false`, so the primary loop takes the PCI branch and
`8086:7270` does not match `0x106b`. The trailing `hda_quirk_lookup_id()` then
matches on the codec SSID, because `SND_PCI_QUIRK_VENDOR` leaves
`subdevice_mask = 0` and therefore matches any device of vendor `0x106b`.

Result: `CS4208_MAC_AUTO` → `cs4208_fixup_mac()`, which re-picks from
`cs4208_mac_fixup_tbl`:

```c
/* codec SSID matching */
static const struct hda_quirk cs4208_mac_fixup_tbl[] = {
        SND_PCI_QUIRK(0x106b, 0x5e00, "MacBookPro 11,2", CS4208_MBP11),
        SND_PCI_QUIRK(0x106b, 0x6c00, "MacMini 7,1",     CS4208_MACMINI),
        SND_PCI_QUIRK(0x106b, 0x7100, "MacBookAir 6,1",  CS4208_MBA6),
        SND_PCI_QUIRK(0x106b, 0x7200, "MacBookAir 6,2",  CS4208_MBA6),
        SND_PCI_QUIRK(0x106b, 0x7800, "MacPro 6,1",      CS4208_MACMINI),
        SND_PCI_QUIRK(0x106b, 0x7b00, "MacBookPro 12,1", CS4208_MBP11),
        SND_PCI_QUIRK(0x106b, 0x7f00, "iMac 16,1",       CS4208_MBP11),
        {}
};
```

**There is no `0x6500` entry** — mainline has no MacBook9,1 entry at all — so
`cs4208_fixup_mac()` falls back to `CS4208_GPIO0`.

That fallback is confirmed by the live GPIO state, which matches
`cs4208_fixup_gpio0()` (`gpio_eapd_speaker = 1`, `mask = dir = 1`) exactly:

```
GPIO: io=6, o=2, i=0, unsolicited=1, wake=1
  IO[0]: enable=1, dir=1, wake=0, sticky=0, data=1, unsol=0
```

### Verdict on the historical P0 hypothesis

**Refuted as stated; replaced by the mechanism above.**

- No quirk is selected "from PCI subsystem `8086:7270`". Nothing in any CS4208
  table matches `8086:7270`. (The only `8086,7270` text in the file is a
  *commented-out* `HDA_CODEC_QUIRK(0x8086, 0x7270, "IMac 27 Inch", …)` in the
  unrelated **CS420x** table.)
- No generic **MacBookAir** path is selected. `CS4208_MBA6` is never reached;
  the applied fixup is `CS4208_GPIO0`.
- The `HDA_CODEC_QUIRK` → `SND_PCI_QUIRK` conversion cannot be attributed:
  the artifact said to contain it is absent, and in the two artifacts that do
  exist the polarity is the opposite of the claim (mainline uses
  `SND_PCI_QUIRK`; the bundled out-of-tree snapshot uses `HDA_CODEC_QUIRK`).

Note a genuine but *latent* mainline inconsistency found while checking this:
`cs4208_mac_fixup_tbl` is commented "codec SSID matching" yet is built from
`SND_PCI_QUIRK`, so its entries only ever match via the trailing fallback.
It is not the cause of this bug and must not be "fixed" opportunistically.

## 4. Why a correct fixup is necessary but not sufficient

The autoconfig line proves the parser *did* select pin `0x1d` as the sole
output (`line_outs=1 (0x1d) type:speaker`). It nevertheless produced a PCM on
converter `0x02`, and the resulting control set contains **no
`Speaker Playback Volume`/`Switch` at all**:

```
numid=1  'Line Out Playback Volume'      (node 0x02)
numid=2  'Line Out Playback Switch'      (pin 0x10)
numid=8  'Master Playback Volume'
numid=13 'Speaker Phantom Jack'          (read-only, from the fixed 0x1d pin)
```

`aplay -l` lists exactly one analog device, `hw:0,0 CS4208 Analog`, and the
codec dump shows that device bound to converter `0x02`. Converter `0x0a`
carries no `Device:` binding.

Therefore the work required is a **driver that creates and drives a playback
stream reaching the speakers**, plus the A1534 amplifier initialisation —
which is why the out-of-tree `macbook12-audio-driver` carries a bespoke PCM
(`patch_cirrus_a1534_pcm.h`) and a 1678-line setup sequence
(`patch_cirrus_a1534_setup.h`). A pin/verb/GPIO fixup added to mainline
`cs420x.c` alone cannot fix this machine.

### Correction — resolved: the speaker stream is converter `0x0a`

An earlier revision of this document asserted the remedy is to bind a PCM to
converter `0x0a`, which at the time was an inference from the pin connection
list. It then looked contradicted by the bundled driver, which sets
`info->stream[PLAYBACK].nid = 0x04` for speakers.

Reading the A1534 verb trace settles it **in favour of `0x0a`**, from evidence
alone:

| Converter | Occurrences in the trace | What the trace does with it |
| --- | --- | --- |
| `0x0a` | 148 | `SET_STREAM_FORMAT 0x4013`, `SET_CHANNEL_STREAMID 0x10`, pin `0x1d` `SET_CONNECT_SEL 0`, pin `0x1d` `SET_PIN_WIDGET_CONTROL 0x40` |
| `0x02` | 74 | `SET_STREAM_FORMAT 0x4011`, `SET_CHANNEL_STREAMID 0x10` (headphones) |
| `0x04` | 15 | **`AC_VERB_PARAMETERS` reads only**, then `SET_POWER_STATE D0` and `SET_POWER_STATE D3` |

Converter `0x04` is never given a stream format or a stream id, and the trace
leaves it **powered down in D3**. It is not a data path.

The trace also confirms the wiring it is driving: at line 1049 it reads
`0x1d`'s connection list and expects `0x0000000a`, then selects index 0.

Decoding the two format words gives the exact stream contract:

```
0x4013 -> 44100 Hz, 16-bit, 4 channels   (converter 0x0a, speakers)
0x4011 -> 44100 Hz, 16-bit, 2 channels   (converter 0x02, headphones)
0x4031 -> 44100 Hz, 24-bit, 2 channels   (the macOS headphone format the
                                          bundled driver downgraded to 0x4011)
```

**Confirmed:** the speaker path is converter `0x0a` → pin `0x1d`, carrying
**four channels at 44.1 kHz, 16-bit** — which is consistent with `0x0a`'s own
capability report (44.1/48 kHz, 16/20/24-bit, 8-channel capable) and with the
four TAS5758L TDM amplifiers in `docs/HARDWARE-PATH.md` §3.

This also explains audit finding F15: the bundled driver's hardcoded
`SNDRV_PCM_RATE_44100` / `S16_LE` / `channels_max = 4` were taken from `0x0a`'s
configuration, but then applied to a PCM pointed at `0x04`. Audio reaches the
speakers only because `play_a1534()` hardcodes stream tag 1 on `0x0a` and the
host happens to assign the same tag to the PCM — a collision, not a design.

## 5. Consequences for the design

1. A codec-SSID-gated (`106b:6500`) **and** DMI-gated (`MacBook9,1`) selection
   is required, and must not depend on the `8086:7270` PCI subsystem.
   Required regression case: PCI `8086:7270` + codec `106b:6500` + DMI
   `Apple Inc./MacBook9,1` → A1534. *(Implemented and tested:
   `src/cs420x-a1534/a1534_match.h`, `tests/test_a1534_match.c`.)*
2. The deliverable must be an out-of-tree DKMS module, because the fix needs a
   custom PCM, not just a fixup entry.
3. It must be built with **clang/LLD** (`LLVM=1`), because the target kernel
   sets `CONFIG_CC_IS_CLANG=y` / `CONFIG_LD_IS_LLD=y` with ThinLTO. Building
   with the host GCC 16.2.1 reproduces the historical flag rejections
   (`-mstack-alignment=8`, `-mretpoline-external-thunk`,
   `-fexperimental-late-parse-attributes`); those flags are correct for this
   kernel and must not be stripped.
4. Every A1534 register/coefficient value must be re-derived from the AppleHDA
   and Boot Camp references before it is trusted, since the bundled driver
   snapshot has no recorded provenance.
