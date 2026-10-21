# Project state

Version 20261021.01 - updated 2026-10-21, adding the first public release (next paragraph) to the 2026-10-20 state below.

**History note.** 20261021.01 is the first public release. Everything below that names an earlier version (tags, GitHub releases,
release assets, installs, package checksums, `release/` directories) describes the earlier, private development line of this
project. Those tags, release pages and packages are not part of this repository and cannot be followed from here; the text is kept
as the record of how the current state was reached.

**20261021.01 is promoted and released (tag `v20261021.01` on the promote commit, published 2026-10-21 as a GitHub release): comments, attribution, licence headers and non-code files only.** Edits in
`src/cs420x-a1534/`, `tools/`, the packaged README, `vendored/PROVENANCE.md`, the `contrib/` files and the `Makefile`; the two derived
`cs420x.c` files change by comments only, through `local-changes.patch`, so `packaging/upstream.lock` is re-pinned. No executable line was added,
removed or changed. VERIFIED by comparing the old and the new tarball: every changed C file is identical once comments are stripped (same line
counts), and the modules built from both at one fixed build path with 6.18.55-2-cachyos-lts (gcc) and 7.2.11-1-cachyos (clang) differ only in
the embedded source-identity string, the build id and, for the clang build, the source-file checksums in the line table. The source identity
changes without a change in module code: 7.2 `3459bbf7be37223c` (was `79b16c8b296a3821`), 6.18 `2fc8b8ad2d1b2deb` (was `7fc96add428d9fce`).
The hardware run is **NOT RUN** for 20261021.01 and is carried over from 20261020.03 (6.18) and 20261020.01 (7.2) on that evidence; the package
is not installed anywhere (`pkg.install_20261021_01`).
Test totals: 253 passed, 0 failed, 9 blocked on a host with the replacement module loaded; 252 passed, 0 failed, 10 blocked on a host that runs
the stock codec (derived, NOT RUN on such a host). The suite no longer fails when it is started with SIGINT ignored.

**20261020.03 is promoted and released** (tag `v20261020.03` on the promote commit; published 2026-10-20 evening as a GitHub release
with the package as asset, sha256 `96a58562...`). VERIFIED. It ships the CachyOS LTS
series 6.18 next to 7.2 and changes no driver code: source identity 7.2 `79b16c8b296a3821` (as before), 6.18
`7fc96add428d9fce`. The maintainer installed it on the test machine (`pacman -U` exit 0 at 18:20, DKMS installed it for 6.18.55-2-cachyos-lts and
7.2.11-1-cachyos) and booted 6.18.55-2-cachyos-lts: `macbook91-audio-verify` **PASS on hardware** (31 passed, 0 failed, 2 skipped;
module `20261020.03+7fc96add428d9fce`; speaker tone, microphone, headphone jack detect, capture across plug and unplug and the
headphone tone maintainer-confirmed). **Not verified on 6.18, accepted by the maintainer on 2026-10-20 without a test run (not tested):
suspend/resume** (no suspend happened in that boot; gate `hw.suspend_resume_6_18_lts` stays NOT_RUN, the acceptance is its
`accepted` field), Bluetooth function (gate in the wireless package), a real call with a headset (`hw.headset_call`, same
acceptance). HDMI stays SKIPPED by the maintainer's decision. The 7.2 runtime result is carried over from
20261020.01 (module code identical, `hw.runtime_7_2_20261020_03_carried_over`). That run used the package built before the
documentation-only re-pin (sha256 `3fc2fe99...`); the promoted and published package (sha256 `96a58562...`) differs from it in the
two shipped README files and package metadata only. **The published package is installed since 2026-10-20 19:01-19:04**
(VERIFIED, `docs/test-status.json` `pkg.install_published_20261020_03`; run by the maintainer on 6.18.55-2-cachyos-lts):
`sudo pacman -U`, exit 0, reinstalled over the pre-re-pin build (`3fc2fe99...`); the installed package is now byte-identical to the
GitHub release asset. DKMS installed the module (`20261020.03`) for 6.18.55-2-cachyos-lts and 7.2.11-1-cachyos, the initramfs was rebuilt for
both, `pacman -Qkk` reports 0 altered files, and the loaded `snd_hda_codec_cs420x` (`20261020.03+7fc96add428d9fce`) equals the
on-disk module (same source identity as before the reinstall). No new runtime check ran on the reinstall. The text below describes
20261020.02 and earlier.

**20261020.02 is promoted and released** (tag `v20261020.02`; published 2026-10-20 as a GitHub release with the
package as asset). No driver change: the module's source identity stays
`+79b16c8b296a3821`. It carries the license change of 2026-10-20 (own files GPL-3.0-or-later; the module, what
builds it and what it derives from stay GPL-2.0; `README.md` "Provenance and licensing"), the corrections of
`vendored/PROVENANCE.md` and the translation of the remaining German text to English. Installed on the test machine on
2026-10-20 (pacman -U exit 0, DKMS built it for 7.2.11-1-cachyos, on-disk module
`20261020.02+79b16c8b296a3821`) but not loaded: no reboot since. No runtime check of the new modules was
run; the runtime evidence is carried over from 20261020.01, whose module source is identical
(`macbook91-audio-verify` 31 passed / 0 failed / 2 skipped on it, `docs/test-status.json`
`hw.runtime_20261020_02_carried_over`). Promoting it pruned `release/20261015.01`.

**20261020.01 is released.** It fixes the defect found on 2026-10-19 (a headphone plug stopped a running
capture). The maintainer installed it on the test machine on 2026-10-20 and rebooted; the loaded module reads
`20261020.01+79b16c8b296a3821`. `macbook91-runner jackstream` run `20261020T063948Z-5274`: PASS
(`regress.concurrent_capture`, `regress.jack_hotplug_stream`, all identity and jackstream checks).
`macbook91-audio-verify` was run by the maintainer; its counts were not recorded and no failure archive was written.
Not run: a real call with a headset plugged in (accepted by the maintainer on 2026-10-20 without a test run, `hw.headset_call`).

Step 0 cleanup, 2026-10-20 (no driver, package or release change): the current-state lines here, in
`README.md`, the 20261020.01 entry of `docs/CHANGELOG.md`, `docs/HARDWARE-PATH.md` and
`docs/test-status.json` now match the measured release; dead paths in the documentation are corrected.

**20261015.01 was released.** The maintainer installed it on the test machine with `pacman -U` on 2026-10-15 14:03
(20261006.01-1 -> 20261015.01-1), DKMS built it for 7.2.9-2-cachyos, the machine was rebooted at
14:05, and the loaded and on-disk module both read `20261015.01+137052a20d23eae4`.
`macbook91-audio-verify` passed, as reported by the maintainer; its counts were not recorded (the verifier
archives only on failure, and no archive was written). Promoting it pruned the oldest release directory.

What changed since 20261014.01: **unreleased changes from an audit of the tree; nothing on the test machine was
installed or changed.** The verifier now ends on Ctrl-C, does not count journalctl's "-- No entries --"
as a kernel log, checks this card's own sink and the DKMS entry of the running kernel, and plays a quiet
tone into the headphones and waits for the unplug instead of asking about audio that was not playing.
`tools/macbook91-codec-state` now addresses amplifier gain/mute by direction and channel: the 722-field
comparison of 2026-09-14 read every amplifier field as input, right channel, index 0, so amplifier output
state was not compared (the caveat is added where that claim is made). The runner, an evidence-archiving helper
(which had packed a microphone recording) and smaller tools were fixed, the driver headers' comments
changed (comments only, but the module's source identity changes at the next build), and drifted docs
were corrected; `docs/RELEASING.md` collects the release procedure.
The RTKit boot check is PASS: the boot that started 2026-10-14 12:29:53 holds no RTKit line at `-p4`
(`env.rtkit_boot_messages`). Everything recorded under 20261014.01 below still holds.

What changed since 20261006.02: **no driver or package change.** Two host questions from the
macbook91-hw-fixes journal review are decided and written down in `docs/HOST-POLICY.md`: the package
ships no `snd_hda_intel` power_save policy, because the udev "exit code 1" lines are a cachyos-settings
1:1.4.1-1 defect already fixed upstream (`env.power_save_policy`, SKIPPED by decision; on AC too the
value in effect is 1, measured; that TLP is the writer there is an inference); and rtkit stays installed, and the user session's PipeWire keeps its rlimit realtime priorities after a restart (`env.rtkit_user_session_priority`); whether the greeter's and the portal's RTKit lines are gone needs the maintainer's next reboot (`env.rtkit_boot_messages`, NOT_RUN).
The Artifacts section below is corrected to what is on disk, and a live-state re-read is added.
Everything recorded under 20261006.02 still holds.

**20261006.01: the package version is date-based** (the earlier numbering is
summarised at the end of `docs/CHANGELOG.md`). The build before it was
re-released unchanged under the new version; the two packages differ in one
line, `PACKAGE_VERSION` in `dkms.conf`, and the module's source identity stays
`679b7fd96a54c7de` (it reports `20261006.01+679b7fd96a54c7de`). That build was
installed on the test machine on 2026-10-06, built by DKMS for
7.2.9-1-cachyos and verified on hardware the same day: `macbook91-audio-verify`
27 passed, 0 failed, 2 skipped, and `macbook91-runner jackstream` run
`20261006T081744Z-3324` 13 of 13 (its plug half measured nothing, the
headphones were already in; see "Found 2026-10-19"). That release also made the
source tarball reproducible, with its SHA256 pinned in
`packaging/arch/PKGBUILD`.

## Found 2026-10-19: a headphone plug stops a running capture

**Defect in 20261015.01 and every earlier release.** Plugging the headphones
in while a capture runs stops that capture, and every capture opened after it
stays silent, unplugging included, until the codec runtime-suspends. In a
call, the microphone records nothing once the headset goes in, and KDE's
microphone test shows no level. Measured on the test machine on 2026-10-19 under
20261015.01, unprivileged and with plain ALSA (`docs/INCIDENT-20261019.md`):
`regress.concurrent_capture` is **FAIL**. After the headphone replay, capture
converter `0x06` reads stream tag 0, and the HDA core's converter cache keeps
later captures from writing it back. The four-pole plug is not detected as a
headset, so the capture source stays the internal microphone; that is a
separate limitation and unchanged.

The PASS records of 2026-09-15 and 2026-10-06 were wrong for the plug: the
headphones were already in when the runner asked for the plug, and the runner
accepted that. It now waits for the opposite jack state before each prompt,
restarts the capture after each transition and compares the loaded module's
full source identity; the verifier's headphone step keeps a capture running
across the plug and the unplug.

The driver fix is in 20261020.01, installed and measured on hardware on 2026-10-20
(`fix.capture_resync_after_jack_replay`, PASS; `macbook91-runner jackstream` run
`20261020T063948Z-5274`): `a1534_capture_resync()` in
`src/cs420x-a1534/a1534_pcm.h` re-programs the capture converter after every
headphone replay and on every capture prepare. Workaround on 20261015.01 and
earlier: end the call, or stop every playback and capture; once the codec
has suspended, a few seconds later, the next capture works again.

## Current objective

**The capture fix is released and measured** (see "Found 2026-10-19").
`20261021.01` is the newest promoted release (the first public one; comments, attribution, licence headers and non-code files only, hardware NOT RUN, carried over);
`20261020.03` is the newest one that was run on hardware (the 6.18 LTS series added; see the top of this file and "Exact next action"). `macbook91-runner jackstream` passed on 20261020.01 on 2026-10-20. Still
not run, and accepted by the maintainer on 2026-10-20 without a test run (not tested, nothing pending): suspend/resume under 6.18
(`hw.suspend_resume_6_18_lts`) and a real call with a headset plugged in (`hw.headset_call`).

What is left open is open by decision or by measurement, not by omission:
`hw.hdmi_preserved` and `hw.hdmi_under_fixed_profile` are SKIPPED because this
machine is practically never connected to an external display, and the
optional amplifier bring-up (`a1534_amp=1`) stays off by default behind
`transport.discriminates`, which is FAIL. See "Open, and honestly open".

## Live state, re-read on 2026-10-15

| | | read with |
| --- | --- | --- |
| Kernel | `7.2.9-2-cachyos` | `uname -r` |
| Package | `macbook91-cs4208-dkms 20261015.01-1` installed | `pacman -Q` |
| DKMS | `macbook91-cs4208/20261015.01, 7.2.9-2-cachyos, x86_64: installed (Original modules exist)` | `dkms status` |
| Loaded module | `20261015.01+137052a20d23eae4`, same as `modinfo` | `/sys/module/snd_hda_codec_cs420x/version` |
| Boot | 2026-10-15 14:05:08 | `uptime -s` |

Read only; no verifier run, no sound.

## Deliverable

**Current promoted package:** `macbook91-cs4208-dkms 20261021.01-1` (`release/20261021.01/`)
- **RELEASED** (tag `v20261021.01`, published 2026-10-21): the first public release, comments, attribution, licence headers and non-code files only, no driver change;
hardware NOT RUN, carried over from 20261020.03 and 20261020.01. See `release/20261021.01/STATUS.txt`.

Previous: `20261020.03`, tag `v20261020.03`, published 2026-10-20 (GitHub release): the
6.18 LTS series next to 7.2, no driver change; 6.18 audio PASS on hardware, suspend/resume on 6.18 NOT VERIFIED (accepted by the maintainer).
Before that `20261020.02`, tag `v20261020.02`: no driver change, the license change and the English translation. Before that `20261020.01`, tag `v20261020.01`: the capture fix after a headphone plug,
measured on hardware on 2026-10-20 (its release directory is pruned). Before that `20261006.01`, tag `v20261006.01`: the first date-based version,
identical to the build before it apart from `PACKAGE_VERSION`; that build was
installed on the test machine on 2026-10-06, built by DKMS for kernel
7.2.9-1-cachyos and verified on hardware the same day (module source identity
`679b7fd96a54c7de`). Its driver differs from the one before only by the
jack-callback fix of 2026-09-21.

Working and user-confirmed: four-channel speakers from cold boot, software
volume, headphones with hotplug both ways *and* with the jack already in,
internal microphone, deep suspend up to 1 h 44 min with sound surviving the
resume, no codec wedge, clean rollback to the stock codec. A headphone plug
during a live capture stopped the capture under 20261015.01
(`regress.concurrent_capture`, FAIL on 2026-10-19, `docs/INCIDENT-20261019.md`);
under 20261020.01 the capture survives it (PASS on 2026-10-20).

For 20261015.01 no mandatory gate was unrun. `hw.dkms_kernel_update`, the
last one, closed on 2026-09-21: the rebuild happened twice over and the
verifier ran on the result, 27 passed / 0 failed / 2 skipped.
`regress.concurrent_capture` was FAIL from 2026-10-19; since 2026-10-20 it and
the gate of its fix, `fix.capture_resync_after_jack_replay`, are PASS under
20261020.01.

The amplifier bring-up (`a1534_amp=1`) remains opt-in and unproven; the
transport has never been shown to distinguish a present device from an absent
one. It is unrelated to everything above.

## Long suspend: measured, not inferred

Five deep suspends on 2026-09-15, read out of the journal rather than produced
by a probe:

| entry | exit | duration |
| --- | --- | --- |
| 06:19:42 | 08:03:39 | 1 h 44 min |
| 10:03:41 | 10:51:53 | 48 min |
| 13:25:40 | 13:48:55 | 23 min |
| 18:25:15 | 18:53:57 | 29 min |
| 19:26:33 | 20:50:57 | 1 h 24 min |

Each is `PM: suspend entry (deep)`, and every resume carries
`A1534: restored 128 coefficients, 19 pin configs, digi 0x111, converter 0x0a
channel count 4`. The maintainer confirms sound after them. This supersedes the
earlier concern that only seconds-long S3 had ever been seen.

Two limits, both real. These ran under the speaker fix of 2026-09-14, before
the headphone-profile fix of 2026-09-15, which changed **no driver source at
all**, so the `cvt_chan_count` restore under test is byte-identical. And the
20:50:57 resume *did* leave the machine silent: for the unrelated userspace
reason the headphone-profile fix addresses, not because the codec restore
failed. Its restore
line is present like all the others.

## Exact next action

**20261021.01 is promoted, tagged and published** (`docs/RELEASING.md` sections 5 and 6). Hardware: NOT RUN for 20261021.01. If the maintainer installs it, the check is
one `macbook91-audio-verify` run per kernel in use, recorded in `docs/test-status.json` (`hw.runtime_20261021_01_carried_over` then
gets the actual result). The text below describes 20261020.03, the newest release run on hardware.

**20261020.03 is promoted, tagged and published** (`docs/RELEASING.md` sections 5 and 6). The published package (sha256 `96a58562...`) is installed
since 2026-10-20 19:01-19:04 (reinstalled over the pre-re-pin build `3fc2fe99...`, byte-identical to the release asset, VERIFIED);
the 6.18.55-2-cachyos-lts boot ran `macbook91-audio-verify` PASS on the pre-re-pin build, which has the same module sources, and the
loaded module equals the on-disk one. Next: reboot (or reload) so that the 20261020.02 facetimehd and backlight builds of the sibling
packages load, and run the verify tools (`macbook91-audio-verify` among them). Accepted by the maintainer on 2026-10-20 without a test run
(not tested, so not pending): the 6.18 suspend/resume series (`hw.suspend_resume_6_18_lts`, stays NOT_RUN, the acceptance is its
`accepted` field), Bluetooth on 6.18 (NOT VERIFIED, accepted by the maintainer; the gate is in the wireless package) and a real call
with a headset plug (`hw.headset_call`, stays NOT_RUN, same acceptance). If the maintainer ever runs the suspend series: deep suspend
under 6.18 with sound surviving the resume, then `macbook91-audio-verify` again, recorded in `docs/test-status.json`.
Rollback to 20261020.02 (7.2 only; it refuses to build for 6.18, where the stock codec then stays) needs a package of that
version, which this repository does not carry (built packages are untracked and releases before 20261021.01 are not part of it).
`pacman -R` and a reboot restore the stock codec.

The next thing that will happen on its own is a kernel update. When it does,
DKMS rebuilds the module offline — the fetch runs only at package build
time — and the honest check afterwards is one command:

```
macbook91-audio-verify
```

Since 20261020.03 the source tree carries one derived `cs420x.c` and one header set per
series, 6.18 and 7.2 (6.18: `macbook91-audio-verify` PASS on hardware, suspend/resume on 6.18 NOT VERIFIED, accepted by the maintainer). If a series the package does not
ship lands (7.2 → 7.3, not 7.2.6 → 7.2.7), DKMS skips it (`BUILD_EXCLUSIVE_KERNEL`) and the
Makefile refuses to build against it, because the private headers are
internal structure definitions with no ABI promise. The remedy is a new
release whose `packaging/upstream.lock` knows the new tag, recorded with
`packaging/fetch-upstream.sh --tag vX.Y.Z --accept-new` (`docs/RELEASING.md`,
section 0), not to override the check.

## Open, and honestly open

| | |
| --- | --- |
| `regress.concurrent_capture` | **PASS** since 2026-10-20 under 20261020.01 with the driver fix `fix.capture_resync_after_jack_replay` (`macbook91-runner jackstream` run `20261020T063948Z-5274`) — listed so the row is not silently dropped: FAIL on 2026-10-19 under 20261015.01, a headphone plug stopped a running capture (`docs/INCIDENT-20261019.md`); a real call with a headset plugged in is not run (`hw.headset_call`, accepted by the maintainer on 2026-10-20 without a test run) |
| jack-callback fix (2026-09-21) | **PASS** since 2026-10-06 — listed so the row is not silently dropped: verifier 27/0/2 and jackstream run `20261006T081744Z-3324` 13/13 on the test machine, whose plug half measured nothing (the headphones were already in) |
| `hw.dkms_kernel_update` | **PASS** since 2026-09-21 — closed, and listed here only so the row is not silently dropped: rebuild on the 7.2.4-3 → 7.2.6-1 kernel update, rebuild again on a package upgrade, reboot, then the maintainer's verifier run at 27/0/2 |
| `hw.suspend_resume_6_18_lts` | NOT_RUN - no suspend happened in the 6.18 gate boot of 2026-10-20, so suspend/resume under 6.18.55-2-cachyos-lts is not verified (accepted by the maintainer on 2026-10-20 without a test run, not tested; the status stays NOT_RUN); the 6.18 audio check itself passed (`hw.runtime_6_18_lts`) |
| `hw.headset_call` | NOT_RUN - a real call with a headset plugged in was never run (accepted by the maintainer on 2026-10-20 without a test run, not tested; the status stays NOT_RUN) |
| `hw.hdmi_preserved`, `hw.hdmi_under_fixed_profile` | SKIPPED — the maintainer's decision, scope limit, not a satisfied gate |
| `transport.discriminates` | FAIL — the amplifier read path is not an instrument; nothing is concluded from it in either direction, and the bring-up stays off by default |
| `hw.amp_i2c_bringup`, `transport.engine_responds` | BLOCKED behind that same instrument |
| `hw.suspend_self_cancel` | NOT_RUN — a diagnostic curiosity, not a product gate |
| D2/D3 in `docs/CLAIMS-AUDIT.md` | UNKNOWN — whether the amplifier supply drops in S3 |
| `env.rtkit_boot_messages` | **PASS** since 2026-10-15, listed so the row is not silently dropped: the boot that started 2026-10-14 12:29:53, after rtkit was installed, holds no RTKit line at `-p4` (`docs/HOST-POLICY.md` 2.4) |
| cachyos-settings `20-audio-pm.rules` lines | upstream defect, fixed in CachyOS-Settings `c8e575bbd4`, not yet packaged on 2026-10-14; no local action (`docs/HOST-POLICY.md` 1.4) |
| audit changes of 2026-10-15 | released as 20261015.01; the packaged verifier PASS on the test machine (maintainer report, counts not recorded). Still NOT_RUN on hardware: the runner's privileged commands other than `jackstream` (run 2026-10-20), a codec-state re-capture with the corrected amplifier addressing, a recovery-archive run (unpackaged development tools) |

Closed on hardware this session: `regress.concurrent_capture`,
`regress.jack_hotplug_stream`, `hw.long_suspend_coverage`,
`hw.cold_boot_jack_plugged`, and the ACP port/jack coupling itself.
`regress.concurrent_capture` was reopened on 2026-10-19 (FAIL) and closed
again on 2026-10-20 under 20261020.01 (PASS, first row of the table above).

## Artifacts

* Built package: `macbook91-cs4208-dkms-20261021.01-1-x86_64.pkg.tar.zst`
  (untracked, kept in `dist/`, not published and not a release asset); its checksum is
  in `release/20261021.01/STATUS.txt` for reference only. `release/` holds the newest promoted
  release (and the one before it, once there is one); older releases are not
  part of this repository, and `promote-release.sh` prunes them rather than a
  human remembering to.
