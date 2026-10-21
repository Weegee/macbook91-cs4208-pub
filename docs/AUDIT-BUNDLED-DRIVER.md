# Adversarial audit: bundled out-of-tree driver snapshot

Version 20260914.01. Subject:
`patch_cirrus/` of the `leifliddy/macbook12-audio-driver` snapshot supplied as
evidence.

Method: `diff -u` of the snapshot's `cs420x.c` against the **authoritative**
in-tree `sound/hda/codecs/cirrus/cs420x.c` at tag `v7.2.4` (the running
kernel), plus direct reading of `patch_cirrus_a1534_setup.h` (1678 lines) and
`patch_cirrus_a1534_pcm.h` (444 lines).

The delta on `cs420x.c` is small — 65 added, 24 removed lines — so it can be
audited line by line. **Per the audio task statement of this investigation, this snapshot is
evidence, not a basis to copy.** The findings below are why. (The audio task statement, cited by
"Phase N" in this and other documents, was the archived brief of the investigation; it is not
published, see `docs/EVIDENCE-MAP.md`.)

## Findings

### F1 — The A1534 path is completely ungated (critical)

`cs4208_probe()` in the snapshot:

```c
	//mb9-specific
	err = setup_a1534(codec);
	err = play_a1534(codec);
	hda_codec_to_driver(codec)->ops = &cs_4208_codec_ops;
	spec->gen.pcm_playback_hook = cs_4208_playback_pcm_hook;
	//end
```

There is **no codec-SSID check and no DMI check anywhere in the snapshot.**
Grepping the whole driver for `dmi_match`, `dmi_check_system`, `DMI_`,
`MacBook9` or `0x6500` yields only two hits, and both are *inside* trace
verification reads, not conditionals.

Consequently the entire MacBook9,1 verb replay runs on **every** CS4208:
MacBookPro 11,2 / 12,1, MacBookAir 6,1 / 6,2, MacMini 7,1, MacPro 6,1 and
iMac 16,1. This directly contradicts the target-device gating that
Phase 3 of the audio task statement requires.

**It is also not self-limiting.** The trace's own consistency check is:

```c
	if (retval != check_val)
		codec_dbg(codec, "command nid BAD read check return value ...");
	return retval;
```

It **only logs** and continues. So on a non-MacBook9,1 CS4208 the sequence
proceeds to completion regardless, merely emitting debug noise.

### F2 — Driver-wide `ops` are mutated from a per-codec probe (critical)

```c
	hda_codec_to_driver(codec)->ops = &cs_4208_codec_ops;
```

`hda_codec_to_driver()` is, in `include/sound/hda_codec.h` @ v7.2.4:

```c
#define hda_codec_to_driver(codec) \
	container_of((codec)->core.dev.driver, struct hda_codec_driver, core.driver)
```

That resolves to the single module-global `cs420x_driver`. Assigning `->ops`
there replaces the operations for **every codec bound to the module**, not
just the codec being probed — including CS4206 and CS4207 instances. The write
is unsynchronised and persists for the module's lifetime.

The snapshot's own comment shows the authors hit a consequence of this
(re-probe failing with `-EINVAL` unless `.probe`/`.remove` are duplicated into
the replacement table), and worked around the symptom rather than the cause.

### F3 — Mainline quirk matching is broken for four other Macs (high)

The snapshot rewrites `cs420x_fixup_tbl`:

```c
-	SND_PCI_QUIRK(0x10de, 0x0ac0, "MacBookPro 5,3", CS420X_MBP53),
+	HDA_CODEC_QUIRK(0x10de, 0x0ac0, "MacBookPro 5,3", CS420X_MBP53),
```

…and likewise for `0x10de,0x0d94`, `0x10de,0xcb79`, `0x10de,0xcb89`.

`0x10de` is **NVIDIA**: these are *PCI* subsystem ids of the nvidia HDA
controllers in those Macs. Their *codec* SSIDs are `106b:*`.
`HDA_CODEC_QUIRK` sets `match_codec_ssid = true`, which makes
`snd_hda_pick_fixup()` take the codec-SSID branch, where `10de:*` can never
match; the trailing `hda_quirk_lookup_id()` fallback is also codec-SSID based
and cannot match either.

Net effect: **MacBookPro 5,3 / 5,5 / 7,1 and MacBookAir 3,1(2) silently lose
their fixups.** The `0x106b` conversions in the same table are harmless (that
block is genuinely codec-SSID), but the `0x10de` ones are a real regression.

Note this is the *opposite direction* from the historical P0 hypothesis:
the snapshot **introduces** a quirk-semantics regression rather than fixing
one. See `docs/ROOT-CAUSE.md` §3.

### F4 — Two mainline quirk entries are silently dropped (medium)

`cs4208_mac_fixup_tbl` in the snapshot omits two entries present in v7.2.4:

```c
	SND_PCI_QUIRK(0x106b, 0x7800, "MacPro 6,1",  CS4208_MACMINI),
	SND_PCI_QUIRK(0x106b, 0x7f00, "iMac 16,1",   CS4208_MBP11),
```

MacPro 6,1 and iMac 16,1 would fall back to bare `CS4208_GPIO0`.

### F5 — GPIO writes bypass the PM-aware helper (medium; suspend-relevant)

```c
-	if (spec->gpio_mask)
-		snd_hda_codec_set_gpio(codec, spec->gpio_mask, spec->gpio_dir,
-				       spec->gpio_data, 0);
+	if (spec->gpio_mask) {
+		snd_hda_codec_write(codec, 0x01, 0, AC_VERB_SET_GPIO_MASK, ...);
+		... SET_GPIO_DIRECTION ... SET_GPIO_DATA ...
+	}
```

`snd_hda_codec_set_gpio()` records GPIO state in the codec's verb cache so it
is replayed on resume. Raw `snd_hda_codec_write()` does not. Given that the
speaker amplifier DFET supply is GPIO-controlled
(`docs/HARDWARE-PATH.md` §3), losing GPIO state across suspend is a plausible
mechanism for "audio gone after resume". Applied unconditionally to all
CS420x, this is a regression against mainline.

### F6 — Return values discarded (low, but masks real failures)

```c
	err = setup_a1534(codec);
	err = play_a1534(codec);
```

`err` is overwritten and never tested, so a failing initialisation is
indistinguishable from success.

### F7 — Snapshot predates the target kernel (provenance)

```c
-	spec = kzalloc_obj(*spec);
+	spec = kzalloc(sizeof(*spec), GFP_KERNEL);
```

`kzalloc_obj()` is the newer in-tree spelling, so this edit is a *backport*.
Together with F4 (missing entries that v7.2.4 has) this shows the snapshot is
based on a pre-v7.2.4 mainline. Its `linux-driver-metadata/*` files are all
0 bytes, so the exact base is unrecorded. It still compiles, because
`kzalloc()` remains available.

### F8 — `play_a1534()` drives streaming state at probe time (medium)

`play_a1534()` sets `AC_VERB_SET_STREAM_FORMAT` (`0x4013`),
`AC_VERB_SET_CHANNEL_STREAMID` (`0x10`) and a D0/D3 sequence on converter
`0x0a` during probe. No host DMA is armed from the codec side, so it should
not itself emit sound, but it does leave the codec in a streaming
configuration established outside any PCM lifecycle.

### F9 — The power-state churn behind the known concurrency risk (open)

`patch_cirrus_a1534_setup.h` contains **223** `AC_VERB_SET_POWER_STATE` and
**134** `AC_VERB_GET_POWER_STATE` operations, many on the AFG.
Phase 4 of the audio task statement flags exactly this as a possible breaker of
concurrent capture/playback. The concern is therefore concrete, not
hypothetical. **Unassessed — remains a release blocker.**

### F10 — The sequence is a replay, not an implementation (design)

Measured verb histogram of `patch_cirrus_a1534_setup.h`: 373
`AC_VERB_PARAMETERS` reads, 223 `SET_POWER_STATE`, 54 `SET_AMP_GAIN_MUTE`,
47 touches of vendor widget `0x24` — but only 7 `SET_COEF_INDEX` and **2**
`SET_PROC_COEF`. Combined with the per-call `check_val` arguments and the
trailing `// 0x00a70503`-style raw-command comments, the file reads as a verb
sequence derived from observed behaviour and the upstream header, including
its *read* operations (see `src/cs420x-a1534/vendored/PROVENANCE.md`).

That is consistent with `docs/HARDWARE-PATH.md` §5: the real amplifier
programming (four TAS5758L over I2C) is not visible in it, and is not in the
supplied evidence either.

## Conclusion

The snapshot is usable as **behavioural evidence** — it records a sequence
that reportedly makes these speakers work — but it is **not a safe basis to
package as-is**: F1 and F2 alone would ship a driver that runs a
machine-specific trace on unrelated hardware and mutates module-global state,
while F3–F5 regress mainline behaviour for at least six other Mac models.

**Design consequence.** Build on the authoritative in-tree `cs420x.c` @
`v7.2.4` and port only the A1534 additions onto it, with:

1. a hard gate on codec SSID `106b:6500` **and** DMI `Apple Inc./MacBook9,1`,
   so every non-target CS4208 keeps byte-identical mainline behaviour;
2. no mutation of `hda_codec_to_driver(codec)->ops` — per-codec dispatch only;
3. mainline quirk tables left untouched (F3, F4 not carried over);
4. `snd_hda_codec_set_gpio()` retained (F5 not carried over);
5. checked return values (F6);
6. the A1534 verb sequence treated as **empirical**, carried with explicit
   provenance, and validated only on hardware.

---

# Round 2: `patch_cirrus_a1534_pcm.h` (444 lines)

The first round audited the `cs420x.c` delta. This round audits the custom PCM
layer, which is where the speaker/headphone routing actually lives.

### F11 — Per-codec stream state kept in module-global variables (critical)

```c
static unsigned int cs4208_cur_stream_tag;	/* running PCM stream tag */
static unsigned int cs4208_cur_format;		/* running PCM HDA format word */
static int cs4208_cur_hp = -1;			/* last HP jack state */
```

These are file-scope statics: **one set for the whole module**, not one per
codec. They are written from the PCM `prepare`/`cleanup` path and read and
written from the unsolicited jack-event path, with **no locking of any kind**.

Phase 4 of the audio task statement lists "serializing jack changes against
prepare/cleanup" as a hypothesis needing review. It is not merely unproven
here — it is absent. A jack event arriving during `prepare` can re-point a
stream using a half-updated tag/format pair.

### F12 — `hinfo->nid` is mutated inside `.open` (high)

```c
	if (hp_pin_sense) {
		hinfo->nid = 0x02;		/* headphone converter */
		err = headphones_a1534(codec);
	} else {
		hinfo->nid = 0x04;		/* "speaker converter" */
		err = play_a1534(codec);
	}
```

`hinfo` is the codec's persistent `hda_pcm_stream`, not per-open state, so the
converter choice is latched at open time from the jack state and then diverges
from whatever the jack callback later decides. Phase 4 of the audio task statement names
"avoiding hardware switching in open" as a required hypothesis to test; this
code does the opposite, and additionally runs the full `play_a1534()` /
`headphones_a1534()` verb replay from inside `.open`.

### F13 — A private kernel struct is copied into the module (critical, latent)

```c
// this is very hacky ... re-define these from hda_codec.c here
// NOTA BENE - need to check this is consistent with any hda_codec.c updates!!
struct hda_cvt_setup {
	hda_nid_t nid; u8 stream_tag; u8 channel_id; u16 format_id;
	unsigned char active; unsigned char dirty;
};
```

Verified against `sound/hda/common/codec.c` @ v7.2.4: the layout **currently
matches**, so there is no corruption today. But that definition lives in a
`.c` file, not in any exported header. It is private, carries no ABI promise,
and the module gets **no compile-time error** if it ever changes — the code
would simply read and write the wrong offsets of a live kernel object.

This is the worst possible interaction with DKMS: a kernel update triggers an
automatic rebuild, the rebuild succeeds, and the resulting module silently
corrupts converter state. Phase 8 of the audio task statement requires robust DKMS
rebuild behaviour across kernel updates; this construct is incompatible with
that requirement as written.

### F14 — `remove` leaks the generic spec (high)

```c
static void cs_4208_free_explicit(struct hda_codec *codec)
{
	kfree(codec->spec);
}
```

`cs420x.c`'s replacement ops table wires this to `.remove`, bypassing
`snd_hda_gen_free()`. Everything `hda_gen` allocated (the kctls `snd_array`,
input paths, and so on) leaks, and generic teardown never runs. The same
header even defines `#define cs_4208_free snd_hda_gen_free` — and then does
not use it.

### F15 — Declared PCM capabilities contradict the hardware (high)

```c
static const struct hda_pcm_stream cs4208_pcm_analog_playback = {
	.channels_min = 2,
	.channels_max = 4,
	.rates   = SNDRV_PCM_RATE_44100,
	.formats = SNDRV_PCM_FMTBIT_S16_LE,
	.maxbps  = 16,
};
...
	info->stream[SNDRV_PCM_STREAM_PLAYBACK].nid = 0x04;
	info->stream[SNDRV_PCM_STREAM_PLAYBACK].channels_max = 4;
```

The converter it assigns, `0x04`, is reported by this machine's own codec as
**stereo** (`wcaps 0xd043d`), supporting 32k–192k and 16/20/24/32-bit:

```
Node 0x04 [Audio Output] wcaps 0xd043d: Stereo Amp-Out Stripe
  PCM: rates [0x7f0]: 32000 ... 192000   bits [0x1e]: 16 20 24 32
```

So `channels_max = 4` is asserted on a converter the hardware calls stereo,
while the rate/format set is narrowed far below what that converter supports.
Conversely converter `0x0a` — the one physically wired to the speaker pin —
reports exactly 44.1/48 kHz and 16/20/24 bit, which is what the hardcoded
values look like they were copied from.

This is precisely the pair of failures Phase 9 of the audio task statement asks the
regression tests to catch: *"generic stereo PCM incorrectly treated as the
A1534 four-channel path"* and *"channel probe starting without compatible PCM
capabilities"*. Pinning the rate to 44.1 kHz only also forces PipeWire to
resample all 48 kHz content, which works against the Phase 6 sound-quality
goal.

## Round 2 conclusion

The PCM layer is **not** salvageable by small corrections. F11 (unlocked
module-global stream state), F12 (mutating shared `hinfo` in `.open`), F13
(copied private kernel struct) and F14 (leaking teardown) are structural, and
F15 shows the declared capabilities were not derived from this codec's own
capability report.

It remains valuable as **behavioural evidence** — in particular it records
that the working configuration drives converter `0x04` for speakers and `0x02`
for headphones, which is *not* what a reading of the pin connection lists
alone would predict (see the correction in `docs/ROOT-CAUSE.md` §4). That
discrepancy is the single most important thing to resolve on hardware.

### F16 — The PCM is bound to a converter the driver powers off (critical)

Resolved while settling the open question in `docs/ROOT-CAUSE.md` §4.

`cs_4208_build_pcms_explicit()` sets `info->stream[PLAYBACK].nid = 0x04` and
`cs_4208_playback_pcm_open()` sets `hinfo->nid = 0x04` for speakers. But in
`patch_cirrus_a1534_setup.h`, converter `0x04` appears 15 times and **every one
is an `AC_VERB_PARAMETERS` read**, followed by `SET_POWER_STATE D0` and then
`SET_POWER_STATE D3`. It is never given a stream format or a stream id, and the
trace leaves it powered down.

The converter that actually carries speaker audio is `0x0a` (148 occurrences):
`SET_STREAM_FORMAT 0x4013` (44.1 kHz, 16-bit, 4 ch) and
`SET_CHANNEL_STREAMID 0x10` (stream tag 1), with pin `0x1d`
`SET_CONNECT_SEL 0` and `SET_PIN_WIDGET_CONTROL 0x40`.

So the host DMA stream is programmed onto a dead converter, and sound reaches
the speakers only because `play_a1534()` hardcodes **stream tag 1** on `0x0a`
while the host independently assigns the PCM a stream tag that happens to be 1.
This is a tag collision, not a routing design: it breaks as soon as the host
allocates a different tag (another active stream, a different open order), and
it is why the verb replay has to be re-run from inside `.open` (F12).

It also confirms F15's origin: the hardcoded 44.1 kHz / S16 / 4-channel
capabilities were copied from `0x0a`'s configuration and then attached to a PCM
pointed at `0x04`.

**Design consequence.** Bind the speaker PCM to converter `0x0a` and declare
capabilities from that converter's own report, letting the HDA core assign and
program the stream tag normally. That removes the need to replay the trace on
every open, and removes the tag collision entirely.
