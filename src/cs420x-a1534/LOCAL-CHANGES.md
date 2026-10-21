# Local changes to the vendored `cs420x.c`

Base: `upstream/cs420x.c`, verbatim from `sound/hda/codecs/cirrus/cs420x.c` at
the tag of each series recorded in `packaging/upstream.lock` (the same patch applies to each series' `upstream/<series>/cs420x.c`, yielding `<series>/cs420x.c`) - a resolved tag, not a fixed
one, and a file that is fetched at build time rather than stored here. See
`UPSTREAM.txt`. The complete delta is `local-changes.patch` (270 added, 3
removed lines) and every hunk is bracketed by
`/* --- MacBook9,1 (A1534) additions: begin/end --- */`. Those counts are
recomputed from the patch by `tests/run-tests.sh`, because they were
hand-maintained until they read 51 and 2.

| # | Change | Why |
| --- | --- | --- |
| 1 | `#include "../generic.h"` → `#include "generic.h"` | The private HDA headers are vendored flat into `kheaders/<series>/`, which is on the include path. One of three upstream lines this patch replaces rather than adds to; the other two are the `hda_codec_ops` entries `.build_pcms` and `.init`, replaced by #8. |
| 2 | added `<linux/delay.h>`, `<linux/dmi.h>`, `<linux/mutex.h>`, `<linux/string.h>`, `"a1534_match.h"` | used by the gate and by the A1534 code below |
| 3 | `unsigned int is_a1534:1;`, `struct a1534_state a1534;` and `struct a1534_snapshot a1534_snap;` in `struct cs_spec` | per-codec flag and state, so A1534 behaviour can never leak to another codec |
| 4 | `a1534_streq()` + `cs4208_is_a1534()` | the gate; the decision itself lives in `a1534_match.h` so the host tests exercise the same code |
| 5 | set `spec->is_a1534` early in `cs4208_probe()` and log on match | one machine-checkable marker, per the project's audio plan |
| 6 | gated call of `setup_a1534()` + `play_a1534()`, **return values checked** | amplifier bring-up; on failure `is_a1534` is cleared so the codec falls back to plain mainline behaviour instead of pretending to have succeeded (audit F6) Both vendored functions currently return 0 on every path, so this fallback is defensive and has never triggered. |
| 7 | `#include "vendored/a1534_sequence.h"`, `"a1534_i2c.h"`, `"a1534_snapshot.h"` and `"a1534_pcm.h"` | the bring-up trace (vendored evidence), the amplifier I2C transport, the firmware-state snapshot and the new PCM layer |
| 8 | `cs_build_pcms()`, `cs_init_dispatch()`, `cs_resume()` dispatchers, `cs_suspend()`; `cs_codec_ops` points at them | **the F2 fix**: A1534 behaviour is selected per codec inside one `const` ops table, instead of assigning `hda_codec_to_driver(codec)->ops`, which is module-global. `cs_resume()` reproduces the core's own default (`snd_hda_codec_init()` + `snd_hda_regmap_sync()`) for non-A1534 codecs. `cs_suspend()` clears `bringup_valid`, so a resume replays the bring-up because a suspend happened, not because of a power-state event. |
| 9 | `struct a1534_state` and `struct a1534_snapshot`, with `A1534_NCOEF` and `A1534_PIN_FIRST`/`A1534_PIN_LAST`/`A1534_NPIN`, defined before `struct cs_spec` | `cs_spec` embeds both; the state is per codec and guarded by its own mutex |
| 10 | `cs4208_probe()` logs `CS4208: not the A1534 path (codec SSID ..., DMI ...)` when the gate does not match | a negative marker, so a log without the A1534 line still says why |
| 11 | on a match, `cs4208_probe()` initialises the mutex, sets `hp = -1` (jack state unknown), takes and logs the firmware-state snapshot only while pin `0x1d` still holds its firmware configuration, and sets `bringup_valid` after a successful bring-up | a snapshot taken from an already-reset codec would let the resume path restore nothing |
| 12 | after `snd_hda_pick_fixup()`/`snd_hda_apply_fixup()`, `gpio_mask`, `gpio_dir` and `gpio_data` are set to the A1534 values | the mainline GPIO fixup would narrow the mask and switch the amplifier supply GPIOs off; going through the spec fields lets `snd_hda_codec_set_gpio()` replay them on resume |
| 13 | `MODULE_VERSION(A1534_SRCID)` | the loaded module's identity, read by the verifier from `/sys/module/snd_hda_codec_cs420x/version`. `A1534_SRCID` is the package version plus a hash of `cs420x.c`, `a1534_pcm.h`, `a1534_match.h`, `a1534_snapshot.h`, `a1534_i2c.h` and `vendored/a1534_sequence.h` (`Makefile`). The patch's own comment names only three of them; it is left as is, because changing the patch changes the derived `cs420x.c` hash in `packaging/upstream.lock`. |

## What was deliberately NOT carried over from the bundled snapshot

Each of these is an audit finding from `docs/AUDIT-BUNDLED-DRIVER.md`:

- **F1** — nothing machine-specific runs unconditionally. Every A1534 branch is
  behind `spec->is_a1534`.
- **F2** — `hda_codec_to_driver(codec)->ops` is *not* assigned. That pointer
  resolves to the module-global `cs420x_driver`, so writing it would change ops
  for every codec bound to the module. A1534 behaviour will instead be reached
  by branching inside the single static ops table on `spec->is_a1534`.
- **F3** — the `0x10de` entries in `cs420x_fixup_tbl` keep `SND_PCI_QUIRK`.
  They are NVIDIA *PCI* subsystem ids; converting them to `HDA_CODEC_QUIRK`
  breaks MacBookPro 5,3 / 5,5 / 7,1 and MacBookAir 3,1(2).
- **F4** — the `MacPro 6,1` and `iMac 16,1` entries stay.
- **F5** — `snd_hda_codec_set_gpio()` stays; it caches GPIO state for replay on
  resume, which matters because the speaker amp DFET supply is GPIO-controlled.
- **F7** — `kzalloc_obj()` stays; it is the current in-tree spelling.

Result: on any CS4208 that is not a MacBook9,1, and on every CS4206/CS4207,
this module behaves identically to the mainline driver it is built from.

## The new PCM layer (`a1534_pcm.h`)

Written for this project; it is **not** the bundled snapshot's PCM layer. What
it does differently, keyed to the audit findings:

| Finding | Bundled snapshot | Here |
| --- | --- | --- |
| F11 | stream tag/format/jack state in module-global statics, no locking | per-codec `struct a1534_state` inside `cs_spec`, every access under `a1534_state.lock` |
| F12 | `.open` rewrites the shared `hinfo->nid` and replays the whole trace | `.open` only samples jack state; the converter is chosen in `.prepare` |
| F13 | copies `struct hda_cvt_setup` out of `sound/hda/common/codec.c` | not copied at all; the converter being left is released with the public `snd_hda_codec_cleanup_stream()` |
| F14 | `.remove` = `kfree(codec->spec)`, leaking the generic spec | `.remove` stays `snd_hda_gen_remove` |
| F15 | hardcodes 44.1 kHz / S16 / 4 ch onto converter `0x04` | capabilities come from converter `0x0a`; only `channels_max = 4` is asserted, because that is what the bring-up programs and what the four TDM amps expect |
| F16 | PCM bound to converter `0x04`, which the trace powers down; works only via a stream-tag collision on `0x0a` | PCM bound to converter `0x0a`, the converter physically wired to speaker pin `0x1d`; the HDA core assigns and programs the tag normally |

`channels_max` is deliberately **not** raised to the 8 that converter `0x0a`
advertises: the physical meaning of the extra TDM slots is unproven
(`docs/HARDWARE-PATH.md` §4), and the project's audio plan forbids activating a
channel map that has not been demonstrated.
