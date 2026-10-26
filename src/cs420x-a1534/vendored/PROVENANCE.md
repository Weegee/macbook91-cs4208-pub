# Vendored A1534 bring-up sequence

Files: `ORIGINAL-a1534_sequence.h`, copied verbatim from the upstream file
`patch_cirrus/patch_cirrus_a1534_setup.h` of
<https://github.com/leifliddy/macbook12-audio-driver>, and `a1534_sequence.h`,
derived from it as described below.

## Upstream revision

Recorded on 2026-10-20 (read-only, through the GitHub API). **VERIFIED**

- Repository: <https://github.com/leifliddy/macbook12-audio-driver>
- File: `patch_cirrus/patch_cirrus_a1534_setup.h`
- Commit: `4cdfcdbac2db3f300cc45d9679cfd21df6590a8a` (master, 2026-09-03)
- Git blob: `cddc79ca89abc67ab16ab16ef2835dd8fae6a472`
- Size: 1678 lines, 153495 bytes
- sha256: `cc77fb60e44cef0bbe689deb52dbd18fb571c02a8e70599612f388907e359544`

`ORIGINAL-a1534_sequence.h` has exactly this blob hash, so it is byte-identical
to the upstream file at that commit.

## Authors and credits

The file carries no copyright or license notice. Its first line reads "credits
to davidjo for making speakers work on mbp14,3", its second "below is the
setup for mb9,1". In the upstream repository the file's history lists:

- Leif Liddy (2019-2020, two commits)
- "root" (2019-08-28, one commit)
- breitburg (2026-06-05, "Add working headphone jack switching")

The upstream README says "Based on davidjo's snd_hda_macbookpro" and credits
davidjo's reverse engineering. Credit for the file belongs to these authors and
to davidjo (<https://github.com/davidjo/snd_hda_macbookpro>).

`PROVENANCE.sha256` holds the hashes of both. `packaging/fetch-upstream.sh`
writes it when it assembles the tree, so it exists in the package and in an
assembled tree, not in a plain checkout.

## How it reaches the tree

`ORIGINAL-a1534_sequence.h` is tracked, permanently, and Git is its integrity
record. It is byte-identical to the upstream file named above - sha256
`cc77fb60e44cef0bbe689deb52dbd18fb571c02a8e70599612f388907e359544`, first
re-checked on 2026-09-21 and compared with the upstream blob on 2026-10-20.

`a1534_sequence.h` is no longer tracked. It is derived at package build time
by `packaging/fetch-upstream.sh`, offline, as `ORIGINAL-a1534_sequence.h` +
`a1534_sequence.patch` applied with `patch --forward --fuzz=0`. Its hash is
recorded in `packaging/upstream.lock` under the pseudo-tag `derived`, and
`tests/run-tests.sh` rebuilds it and compares against that record.

This sequence is **never downloaded**. Not from leifliddy's repository, not
from anywhere, not at build time and not at any other time: it is part of this
repository and part of the package. The build's downloads cover `cs420x.c`
and the five private HDA headers of each kernel series, and nothing else.

## Status: EMPIRICAL, NOT DERIVED

This is the single part of the project that could **not** be re-derived from
primary evidence. `docs/HARDWARE-PATH.md` section 5 records why:

- AppleHDA's CS4208 `ConfigData` is 16 bytes and only rewrites the pin config
  of NID `0x22`. It contains no amplifier init, no coefficients, no GPIO work.
- The real amplifier programming targets four TAS5758L smart amps over I2C,
  and neither those register sequences nor any `TAS5758` string exist anywhere
  in the material this project examined.
- The Boot Camp driver covers `DEV_4206`/`DEV_4207` only — it has no CS4208
  entry at all — so it says nothing about this machine.

## Known character of this file

Measured, not assumed: 373 `AC_VERB_PARAMETERS` reads, 223
`AC_VERB_SET_POWER_STATE`, 54 `AC_VERB_SET_AMP_GAIN_MUTE`, 47 references to
vendor widget `0x24`, but only 7 `SET_COEF_INDEX` and **2** `SET_PROC_COEF`.
Together with the per-call `check_val` arguments and the trailing raw-command
comments, the file reads as a verb sequence **derived from observed behaviour
and the upstream header**, including its read operations. How upstream
produced it is not documented there, and this project does not claim to know.
The upstream README (checked at the commit above on 2026-10-21, **VERIFIED**)
says only that the module "replays the initialization the codec needs
(reverse-engineered from macOS)" and "replays the macOS init for both paths";
it does not use the words "verb trace" or "capture". Where other files of this
project say "macOS verb trace", "macOS bring-up", "macOS capture", "captured" or
"replayed", those are this project's own shorthand for the sequence, or a
description of how this driver uses it, not upstream's name for it and not a
statement about how the sequence was obtained.

## Therefore

1. It is carried as **data with provenance**, not as authored code, and is not
   reformatted or "cleaned up" — an untestable trace is safest byte-for-byte.
2. It runs **only** behind the `a1534_match()` gate (DMI `MacBook9,1` **and**
   codec SSID `106b:6500`, or `1013:4208` once firmware state is lost). See
   `../a1534_match.h`.
3. Any claim that it works may only be made after it is demonstrated on the
   machine. It must never be reported as confirmed on the strength of the
   upstream file alone.

## Risk carried with it

It performs 223 power-state writes, many on the AFG. The project's audio plan
flagged exactly this as a possible breaker of a concurrent capture or playback
stream. **It does break a running capture** (measured 2026-10-19,
`docs/INCIDENT-20261019.md`): after a headphone plug replays
`headphones_a1534()`, capture converter `0x06` reads stream tag 0, although
the sequence never writes `0x06`, and the capture stops; the sequence
restores the stream tag of the headphone converter `0x02` only. A playback
survives (`regress.jack_hotplug_stream`). The records of 2026-09-15 and
2026-10-06 that called this closed never had a real plug: the headphones were
already in when the runner asked for it. The driver now re-programs the
capture converter after every replay (`a1534_capture_resync()` in
`../a1534_pcm.h`), and **a running capture survives the plug and the
unplug** (measured 2026-10-20 under 20261020.01, `macbook91-runner
jackstream` run `20261020T063948Z-5274`, `regress.concurrent_capture` PASS).
Not run: a real call with a headset plugged in. A re-vendored trace with
different power-state counts needs this re-assessed; `tests/run-tests.sh`
section 7e counts them.

## Local changes to this file

The as-copied original is kept verbatim as `ORIGINAL-a1534_sequence.h`, and the
complete delta is `a1534_sequence.patch`, tracked in Git. `PROVENANCE.sha256`
holds the hashes of the original and of the derived file, not of the patch.
Exactly two changes, neither touching a single verb:

1. Removed the trailing `#include "patch_cirrus_a1534_pcm.h"`. The snapshot
   chained its own PCM layer from the end of this file; this project supplies
   `../a1534_pcm.h` instead, for the reasons in
   `docs/AUDIT-BUNDLED-DRIVER.md` round 2.
2. Made `snd_hda_coef_item()` `static`. It had external linkage under a
   `snd_hda_`-prefixed name, which both warns under `-Wmissing-prototypes` and
   squats on the kernel's namespace from an out-of-tree module.

No verb, coefficient, GPIO value, power transition or check value was altered.

## License: GPL-2.0-only, assumed, not stated

Neither this file nor the repository it comes from states a license. Labels:
**VERIFIED** = read on 2026-10-20 through the GitHub API, or in this file;
the conclusion at the end is the maintainer's decision, not a finding.

- `leifliddy/macbook12-audio-driver` has no license file. Its README says
  "Based on davidjo's snd_hda_macbookpro" and credits davidjo's reverse
  engineering. **VERIFIED**
- `ORIGINAL-a1534_sequence.h` is identical to that repository's current
  `patch_cirrus/patch_cirrus_a1534_setup.h` (1678 lines). Its first line
  reads "credits to davidjo for making speakers work on mbp14,3", its second
  "below is the setup for mb9,1". **VERIFIED**
- Its helpers `snd_hda_codec_read_check()` and `snd_hda_coef_item()` are
  davidjo's: davidjo's `patch_cirrus/*.h` use them 855 and 374 times.
  **VERIFIED**
- `davidjo/snd_hda_macbookpro` is licensed GPL-2.0. **VERIFIED**

What that does not show:

- The A1534 verb data itself is not in davidjo's repository, whose
  `patch_cirrus` holds MacBookPro14,3 and CS8409 files only. **VERIFIED**
- In leifliddy's repository the file has three authors: Leif Liddy
  (2019-2020), "root" (2019) and breitburg (2026-06-05, "Add working
  headphone jack switching…"). **VERIFIED**

**The maintainer's decision (2026-10-20):** this file is treated as GPL-2.0, read
conservatively as GPL-2.0-only, since whether davidjo's code allows a later
GPL version is not checked. The same holds for what is derived from it,
`a1534_sequence.patch` and `a1534_sequence.h`. That is an assumption, not a
stated license: it rests on the file's derivation from davidjo's GPL-2.0 code
and on its distribution as part of a GPL kernel driver. Should
`leifliddy/macbook12-audio-driver` ever state a license, that statement
replaces this assumption. The machine-readable marker is
`ORIGINAL-a1534_sequence.h.license` next to the file. If a rights holder of
this file objects to its inclusion, the maintainer will remove it on request,
through an issue in <https://github.com/Weegee/macbook91-cs4208-pub>. How the
rest of the project is licensed is in the README's "Provenance and licensing".
