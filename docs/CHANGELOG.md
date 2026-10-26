# Changelog

Versions have the form YYYYMMDD.NN (release date, NN counts releases that
day); the last section summarises the earlier numbering. Only
`release/20261021.01/` is part of this repository; older release directories
cited below were removed from it and the citations are history.

## 20261026.02: text interfaces follow the house text HIG

The module, the driver behaviour and the hook logic are unchanged from
20261026.01. What changed is the text the package and its tools print and
accept at a terminal, plus the PKGBUILD change below. Built and tested in
software; NOT RUN on hardware when this section was written
(`docs/test-status.json`, `hw.runtime_20261026_02`).

- `macbook91-audio-verify`: new `-h/--help` (Usage, Examples, Options,
  Environment, Files, Exit status), `-V/--version` (`macbook91-audio-verify
  (macbook91-cs4208-dkms) VERSION`), `-y` for `--yes`, `--no-input` and
  `--color=WHEN`/`--no-color` (also `MACBOOK91_AUDIO_VERIFY_COLOR`,
  `NO_COLOR`). A wrong option exits 2 with `macbook91-audio-verify: error:`,
  a `Did you mean:` line where one fits and `Help: ... --help`. Questions,
  instructions and errors go to stderr; the check lines and the verdict stay
  on stdout. It asks only when stdin and stderr are terminals and accepts
  y, yes, j, ja, n, no and nein; without a terminal the listening checks are
  reported SKIPPED. Ctrl+C and SIGTERM print `cancelled` and exit 130 and 143
  after the cleanup. Durations read `30 s`, one-line messages have no final
  period. Deviations (named in the script): SKIPPED listening checks do not
  change exit 0 (KAN-2), no default answers (EIN-3), one detail level
  (MOD-5).
- Pacman hook `71-macbook91-cs4208-series.hook` and `kernel-series`: the
  warning block is `==> WARNING: macbook91-cs4208` without rule lines;
  `kernel-series` has `--help`, `--version` and the same error form.
  Deviation: `==> WARNING:` is the makepkg/pacman convention (FEH-2, TYP-1).
- Install scriptlet: the post-install text has no capitalised headings or
  dashes and fits 80 columns; the rollback command stands on its own line.
- `make install` stamps the package version into the installed verifier, so
  `--version` is not "unknown"; `make arch-pkg` reports a mismatch as
  `arch-pkg: error: ...`.
- Development tools (not shipped in the package): `macbook91-runner`,
  `macbook91-codec-state`, `macbook91-wake-probe`, `macbook91-amp-transport`,
  `macbook91-codec-dump`, `macbook91-fetch-macos-recovery`,
  `macbook91-verify-recovery-image`, `macbook91-kc-disasm`,
  `macbook91-kc-symbols`, `dev-audio-collect.sh`, `packaging/fetch-upstream.sh`,
  `packaging/promote-release.sh`, `packaging/mkdist.py`,
  `packaging/make-package.sh` and `tests/run-tests.sh` have `--help` and
  `--version`, report errors as `PROG: error: ...` and exit 2 on wrong usage
  with a `Did you mean:` and `Help:` line. The collector takes `-o/--output
  DIR`, prints only the output directory on stdout (it printed
  `baseline written to:` and `files:` before; the file count is a note on
  stderr now), and the macOS recovery fetcher prints progress on stderr.
  The runner reports Ctrl+C and SIGTERM as `cancelled` (130, 143) after it
  restored the machine state. Deviation from
  KAN-3 (named in the tools): the runner and the probes it reads keep exit 2
  for "could not measure" and 3 for usage and runtime errors, 4 for
  INCOMPLETE, because verdict logic and tests depend on them.
- Not changed on purpose: the superseded probes (kept as evidence, nothing
  new is added to them, `tools/README.md`).
- Package: the PKGBUILD sets `depends` inside `package()`, so makepkg also
  builds on a host without the CachyOS repositories (packaging change of
  8d90422, now part of a release). The built package carries the same
  dependencies and files as before apart from the changed scripts.
- Tests: `tests/run-tests.sh` has a new section for the text interfaces
  (`--help` first line and exit, `--version`, unknown option, colour
  precedence, suggestions, no tracebacks); `tests/run-tests.sh` answers
  `--help` and `--version` itself.

## 20261026.01: kernel series 7.3, the LTS kernel as the default, one series list

**Driver behaviour changes.** The A1534 path pins its mainline fixup, and the
headphone jack callback re-routes a running stream after the bring-up replay.
Built and tested in software; NOT RUN on hardware when this section was
written (`docs/test-status.json`, `hw.runtime_20261026_01`).

- Linux 7.3 (tag v7.3, for the CachyOS kernel 7.3.0-4) is a supported series
  next to 6.18 (LTS) and 7.2. Linux 7.3 added two quirk rows for PCI
  subsystem 8086:7270 ("MacBookAir 7,2"), which this machine carries; they
  select CS4208_MBA6, whose pin table marks the speaker pin unconnected. On a
  match the patched probe now sets the fixup to CS4208_GPIO0 before the quirk
  tables are consulted, on every series (`local-changes.patch`,
  `docs/ROOT-CAUSE.md`). VERIFIED: the module builds for
  6.18.55-2-cachyos-lts, 7.2.11-1-cachyos and 7.3.0-4-cachyos with no
  compiler diagnostic; the six fetched v7.3 files are byte-identical to
  CachyOS's kernel tree at tag cachyos-7.3.0-4.
- Headphone jack: after the bring-up sequence replay both converters' cached
  stream setup is dropped and a running stream is routed to the converter of
  the current jack state, also when a prepare ran during the replay; a failed
  jack-callback registration is logged.
- One series list: `kheaders/KERNEL-SERIES` drives dkms.conf's
  `BUILD_EXCLUSIVE_KERNEL`, a new pacman hook (`71-macbook91-cs4208-series.hook`)
  that warns after every transaction about each installed kernel of a series
  the package does not support, and the verifier's new "kernel series
  supported" check. The `A1534_ALLOW_SERIES_MISMATCH` override is gone.
- Package: depends on `linux-cachyos-lts-headers`; `linux-cachyos-headers` is
  the one optional kernel. The Arch kernels and clang, lld and llvm are no
  longer named.
- Card profile: `analog-stereo` is an output as well, so a kernel that runs
  the stock codec offers a stereo sink (NOT RUN on hardware).
- `macbook91-audio-verify` FAILs a mainline pin override on the A1534 path,
  and its diagnostic archive keeps only this card's `pactl` block.
- Tests no longer write into the user's state directory; the pin check knows
  the lockfile; the serial scan is case-sensitive.
- Source identity: 6.18 `c7580fd70025fa36` (was `2fc8b8ad2d1b2deb`), 7.2
  `c6661a7c92c95904` (was `3459bbf7be37223c`), 7.3 `6a7014b2db87a081`.

## 20261021.01: first public release; comments, attribution, licence headers and non-code files only

**No driver behaviour change.** No executable line of the source tarball was
added, removed or changed. Outside the tarball, executable lines changed in the
test suite, in `packaging/` (maintainer and URL in the PKGBUILD, the promotion
script) and in `tools/dev-audio-collect.sh` (default output directory); none of
that is part of the module package. The module's source identity changes
anyway, because it hashes files whose comments were reworded: 7.2
`3459bbf7be37223c` (was `79b16c8b296a3821`), 6.18 `2fc8b8ad2d1b2deb` (was
`7fc96add428d9fce`).

Commit hashes named in entries up to 20261021.01 belong to the maintainer's private history and do not exist in the public repository.

- Comments in the files the source tarball is built from (`src/cs420x-a1534/`
  and `tools/`) were reworded for a public reader. The two derived `cs420x.c`
  files change by three comments through `local-changes.patch`, so
  `packaging/upstream.lock` pins new hashes for them.
  VERIFIED: every changed C file is identical to 20261020.03 once comments are
  stripped, with the same line count. Modules built from both tarballs at one
  fixed build path for 6.18.55-2-cachyos-lts (gcc) and 7.2.11-1-cachyos (clang)
  differ only in the embedded source-identity string, the build id and, for the
  clang build, the source-file checksums in the line table.
- Attribution and licences. `vendored/PROVENANCE.md` is rewritten: where the
  verb sequence comes from, who wrote it, why it is treated as GPL-2.0-only
  (an assumption, stated as one) and how to ask for its removal; the license
  marker sits in a sidecar file because the header is hash-pinned. The ACP
  profile files carry SPDX and derivation notices. `LICENSES/` gains
  GPL-3.0-or-later and BSD-3-Clause; the two macOS recovery helpers carry
  OpenCorePkg's BSD-3-Clause notice and name the upstream revision they derive
  from. `tests/run-tests.sh` checks these headers.
- The version history is shorter. The versions before 20261006.01 (0.1.0 to
  0.5.1) are summarised in one section at the end of this file, and the other
  documents, comments, tests and evidence notes describe that time by date
  instead of by version. Their full changelog entries, the incident log of
  2026-09-14, the deep-suspend and spurious-wakeup investigations and the
  state sections from before 20261006.01 in `docs/PROJECT_STATE.md` are no
  longer part of the repository; the measurements they recorded that the
  current claims rest on stay in `docs/test-status.json`,
  `docs/CLAIMS-AUDIT.md` and `docs/HARDWARE-PATH.md`. The install message and
  the README no longer carry the upgrade notes for the package's early name and
  for the early optional-dependency change; the package still `replaces`,
  `conflicts` with and `provides` the early name `macbook91-cs4208`.
- Apple-derived material: no Apple binaries are included, and the documents no
  longer copy Apple code or data. The 32-byte dump of the amplifier register
  table and a four-line disassembly fragment (`docs/APPLE-I2C-AUDIT.md`), the
  rendering of the `Info.plist` layout data and the four raw configuration
  verbs (`docs/HARDWARE-PATH.md`) are replaced by descriptions in the project's
  own words; the facts they carried (register values, I2C addresses, buses,
  slots, GPIO roles, the resulting pin default) stay. The pseudo-code
  descriptions of six routines stay. The earlier claim that no Apple code is
  copied was too broad for the earlier documents; it holds for these.
- Claims that the evidence did not carry were corrected. The conclusion that
  the pin defaults a vendored verb trace expects are another machine's state
  stays withdrawn: the gate
  `evidence.trace_is_foreign_machine` in `docs/test-status.json` is FAIL, not
  PASS. Where the documents and `tools/macbook91-dfet-probe` called the
  vendored sequence a "capture" or "replay", they now say what is known: the
  upstream README says only that the module replays the macOS init, "verb
  trace" and "capture" are this project's own shorthand, and how the sequence
  was obtained is not known (`vendored/PROVENANCE.md`, which now quotes what
  the upstream README says). The documents that cite
  the derived `a1534_sequence.h` cite the tracked original and the patch that
  produces it. Two comments in the tarball inputs that said "owner" now say
  "maintainer", and the packaged README says exactly which
  files carry an `SPDX-License-Identifier` line.
- The audio baseline collector is now `tools/dev-audio-collect.sh` (it was
  named after the maintainer's machine). Its default output directory moved to
  `${XDG_STATE_HOME:-~/.local/state}/macbook91-cs4208/baselines`.
- README: installation from a release (`PKGBUILD`, install scriptlet, source
  tarball, `SHA256SUMS`), a note on AI assistance, a history section and a
  license table by path. Documentation prose, test comments and `.gitignore`
  are written for a reader without access to the maintainer's machines; commit
  hashes in the documents are replaced by dates. Working notes of the AI
  sessions and one maintenance helper are no longer part of the repository.
- Tests: checks that needed files outside this repository were removed; the
  suite scans the tracked files for identifiers that must not be published.
  Two checks are new (a release directory holds no file the repository does
  not track; no symbolic link is tracked), and two scans that had matched no
  file (leftover agent paths; withdrawn claims) now cover `src/`, `tools/`
  and `packaging/`.
  Two checks no longer depend on how the suite is started: the recording
  cleanup trap test resets a SIGINT that a background job inherits as ignored
  (it is BLOCKED without python3 instead of failing), and the two checks that
  compare the recorded totals with the run are BLOCKED on a host that still
  runs the stock codec, where `verifier fails on the stock codec` runs instead
  of being BLOCKED.
  The check that the install message and the README explain pacman's prompt
  when the early package name is replaced is removed with those notes.
  Counts: 253 passed, 0 failed, 9 blocked on a host with the replacement
  module loaded (the hardware checks stay BLOCKED); a host without it would
  report 252 passed, 0 failed, 10 blocked (derived, not run on such a host).
- `release/` holds only this release. Older releases are not part of this
  repository. The release assets are the tracked files of
  `release/20261021.01/` and nothing else; no built package is attached, and
  `packaging/promote-release.sh` no longer copies the package into that
  directory (its `.BUILDINFO` records the builder's directories and installed
  packages). The package checksum in `STATUS.txt` is for reference only.
- **Hardware: NOT RUN for 20261021.01.** The runtime results of 20261020.03
  (6.18: `macbook91-audio-verify` 31 passed, 0 failed, 2 skipped; 7.2: carried
  over from 20261020.01) are carried over on the evidence above. The package
  was not installed, `makepkg -si` was not run, and the new modules were not
  loaded.

## 20261020.03: builds for the 6.18 LTS series as well as 7.2

**6.18: `macbook91-audio-verify` PASS on hardware; suspend/resume on 6.18 NOT
VERIFIED.** The 7.2 module is unchanged: its source identity is still
`79b16c8b296a3821`, only the version in front of it moves. The maintainer ran the
verifier on 2026-10-20 under 6.18.55-2-cachyos-lts with module
`20261020.03+7fc96add428d9fce` (the on-disk module): 31 passed, 0 failed, 2
skipped (the jack-profile check needs headphones plugged in, HDMI was
not connected). The speaker tone, the microphone, the headphone jack detect,
the capture across a plug and an unplug and the headphone tone were confirmed
by the maintainer. DKMS had installed the package for 6.18.55-2-cachyos-lts and
7.2.11-1-cachyos (`pacman -U` exit 0). The runtime run used the package built
before the documentation-only re-pin of this release; the module source
identity is the same. The 7.2 runtime result of 20261020.03 was not run: it is
carried over from 20261020.01 and .02, whose module code is identical.

- One source tree, several kernel series. `upstream/<series>/cs420x.c`,
  `kheaders/<series>/` and the derived `<series>/cs420x.c` exist for every
  series `packaging/upstream.lock` pins (v6.18.55 and v7.2.6). The module
  Makefile reads the target kernel's `utsrelease.h`, builds the matching
  series, and refuses one the package does not ship (`make srcid` prints the
  source identity: 7.2 `79b16c8b296a3821`, 6.18 `7fc96add428d9fce`).
- `packaging/fetch-upstream.sh` takes several `--tag` (one per series); with
  no flag, or `--all`, it assembles the newest lock tag of every series.
  `kheaders/KERNEL-SERIES` is now a list. `UPSTREAM.sha256` and
  `UPSTREAM.lock` cover all series. `packaging/mkdist.py` derives its list of
  generated files per series.
- `dkms.conf` gets `BUILD_EXCLUSIVE_KERNEL="^(6\.18|7\.2)\."`, so DKMS skips a
  kernel series the package does not ship instead of failing its build.
- Built and checked against 6.18.55-2-cachyos-lts (gcc) and 7.2.11-1-cachyos
  (clang): both build clean; `modinfo` reports the expected version and
  vermagic. Then run on hardware under 6.18 (see above). Not run: suspend and
  resume on 6.18, the DKMS rebuild on a kernel update and the removal for
  either series.
- Tests (`tests/run-tests.sh`): the fake-kernel guard now uses an unshipped
  series (9.9), the fuzz-0 patch reproduction runs per series, section 4f
  checks per-series lock coverage, that the `dkms.conf` regex equals the
  shipped set, and that the 7.2 source identity stays pinned.

## 20261020.02 — GPL-3.0-or-later outside the kernel module; the provenance record brought up to date

**No driver behaviour change.** The module's source identity hashes none of
the changed files, so it stays that of 20261020.01 (`+79b16c8b296a3821`),
behind the new version.

- License, the maintainer's decision of 2026-10-20: everything this project wrote
  outside the kernel module is GPL-3.0-or-later. What is built into the
  module, or with its headers (`a1534_*.h`, `tests/test_a1534_match.c`),
  stays GPL-2.0-or-later, because GPL-3.0 cannot go into a GPL-2.0-only
  kernel. So does what builds the module or assembles its sources (the
  module's `Makefile` and `dkms.conf`, `packaging/fetch-upstream.sh` and
  `packaging/upstream.lock`), because GPLv2 section 3 counts the scripts that
  control compiling and installing it as part of its source. Nothing derived
  from other works is relicensed: Linux's files stay GPL-2.0-or-later, the
  vendored trace GPL-2.0-only, the ACP profiles LGPL-2.1-or-later. Own source, script and configuration files
  name their license on an SPDX line, `LICENSE` is the GPL-3.0
  text, `LICENSES/` holds the others, the source tarball carries every text
  its files need, and the PKGBUILD lists the four licenses of what the
  package installs. `README.md` maps paths to licenses; `tests/run-tests.sh`
  4e checks the SPDX lines against that map.
- `vendored/PROVENANCE.md` still called the capture resync after a headphone
  replay not yet measured on hardware. It now records the measurement of
  2026-10-20 under 20261020.01 (`macbook91-runner jackstream` run
  `20261020T063948Z-5274`, `regress.concurrent_capture` PASS) and what is
  still not run: a real call with a headset plugged in.
- `vendored/PROVENANCE.md` has a license section for
  `ORIGINAL-a1534_sequence.h`. Its source, `leifliddy/macbook12-audio-driver`,
  states no license; by the maintainer's decision the file is treated as GPL-2.0,
  read conservatively as GPL-2.0-only, on grounds checked on 2026-10-20 and
  recorded there together with what they do not show.
- English throughout, a step towards publishing the project. The German
  prose of the archived working notes and the messages of a helper script
  are translated; commands, paths, dates and numbers are unchanged. The
  evidence labels in `docs/HOST-POLICY.md` and in the packaged
  `vendored/PROVENANCE.md` read VERIFIED, NOT VERIFIED and REFUTED; a German
  quote in the spurious-wakeup investigation has an English translation beside
  it. Recorded German output, such as the desktop's "Schein-Ausgabe" (Dummy
  Output), and quotes stay verbatim as evidence.
- Not in the package: `docs/HEADSET-MIC.md` records the headset-microphone
  question, what macOS does and the probe that decides it; dead paths and
  stale current-state claims in the documentation are corrected.

## 20261020.01 — a headphone plug no longer stops a running capture

**Driver fix.** A headphone plug during a running capture stopped that
capture, and every capture opened after it stayed silent, unplugging
included, until the codec suspended: in a call, the microphone went quiet
when the headset went in (measured 2026-10-19 under 20261015.01,
`docs/INCIDENT-20261019.md`). After the headphone replay the capture
converter had lost its stream tag, and the HDA core's converter cache kept
later captures from writing it back. `a1534_pcm.h` now re-programs the
capture converter after every headphone replay and on every capture prepare.
Measured on hardware on 2026-10-20, before the release: `macbook91-runner
jackstream` run `20261020T063948Z-5274` PASS (`regress.concurrent_capture`,
`regress.jack_hotplug_stream`). Not run: a real call with a headset plugged in.

- `tools/macbook91-runner jackstream` waits for the jack to read the opposite
  state before each prompt (the PASS records of 2026-09-15 and 2026-10-06
  never had a real plug), restarts the capture after each transition, names
  the ADC stream tags, and compares the source identity in the module
  version of the loaded and the on-disk module, not only `srcversion`, which
  does not see the driver headers.
- `macbook91-audio-verify`'s headphone step waits for an empty jack first and
  keeps a capture to `/dev/null` running across the plug and the unplug.
- `tests/test_lock_discipline.py` checks that `prepare_mutex` is never taken
  under `st->lock` and that the capture resync runs under `prepare_mutex`.
- `docs/test-status.json`: `regress.concurrent_capture` is FAIL for
  20261015.01 and earlier; the fix's gate
  `fix.capture_resync_after_jack_replay` was NOT_RUN until the hardware gate
  and is PASS since 2026-10-20. `README.md`,
  `docs/EVIDENCE-MAP.md`, `docs/CLAIMS-AUDIT.md`, `vendored/PROVENANCE.md`,
  `docs/HARDWARE-PATH.md` and `docs/PROJECT_STATE.md` no longer call the plug
  harmless for a running capture.

## 20261015.01 — a corrected verifier and tools from an audit of the tree

**No driver behaviour change.** The driver headers' comments and two build
messages in the module `Makefile` changed, so the module's source identity is
new; the compiled logic is that of 20261006.01.

- `macbook91-audio-verify` ends on Ctrl-C, does not count journalctl's
  "-- No entries --" as a kernel log, checks this card's own sink and the DKMS
  entry of the running kernel, and in the hotplug step plays a quiet tone into
  the headphones and waits for the unplug.
- `tools/macbook91-codec-state` addresses amplifier gain/mute by direction and
  channel; the 722-field comparison of 2026-09-14 had read every amplifier
  field as input, right channel, index 0 (caveat added where it is cited).
- The runner restores wake sources on every exit; the evidence-archiving helper no
  longer packs a microphone recording.
- `tests/run-tests.sh`: `contains_str` no longer pipes into `grep -q`, which
  under `pipefail` returned 141 for an early match in text larger than the
  pipe and made the systemd-sleep check fail once in three runs; a self-test
  covers it.
- `docs/RELEASING.md` collects the release procedure.

## 20261006.01 — date-based versions

**No driver or content change.** The package is 0.5.1 under a new version
number, so that the maintainer's packages are versioned the same way. pacman (`vercmp`) orders `20261006.01` after `0.5.1`, so the
update is an ordinary upgrade and needs no epoch; DKMS rebuilds the module
under the new version.

- `VERSION`, `pkgver`, the source tarball's name, the DKMS source directory
  (`/usr/src/macbook91-cs4208-20261006.01`) and the module's version string
  carry the new number. Release tags are `v<VERSION>`, so this one is
  `v20261006.01`.
- `tests/run-tests.sh` accepts both forms where it reads the promoted version
  from `docs/PROJECT_STATE.md`.

## 0.1.0 to 0.5.1 (2026-09-14 to 2026-10-06)

Before 20261006.01 the versions were numbered 0.1.0 to 0.5.1. Their releases
are not part of this repository, and the rest of this repository describes
that time by date rather than by version. In short: the 0.1 series was the
first bring-up on the hardware (2026-09-14, documented as it happened, with
two withdrawn candidates); 0.2 and 0.3 added the resume path and the optional
amplifier bring-up; 0.4.4 fixed the silent speakers after a deep suspend;
0.4.5 fixed the missing audio device while headphones are plugged in; 0.4.6
renamed the package to `macbook91-cs4208-dkms`; 0.5.0 stopped carrying kernel
source in the repository; 0.5.1 made the source tarball reproducible and fixed
the jack callback. The full entries are kept in the maintainer's private
records.
