# Changelog

Versions have the form YYYYMMDD.NN (release date, NN counts releases that
day); the last section summarises the earlier numbering. Only
`release/20261115.01/` and `release/20261119.01/` are part of this repository;
older release directories cited below were removed from it and the citations
are history.

## 20261119.01 (2026-11-19): shorter README, user and developer pages under docs/, short runner help

**No driver behaviour change.** One output changed: `macbook91-runner --help`
no longer prints the environment, the files and the exit status; they moved to
`macbook91-runner --help all`. A script that reads those sections from `--help`
must call `--help all`.

- README: cut to 99 lines. The installation steps moved to `docs/INSTALL.md`,
  the licence map to `docs/LICENSING.md`, the evidence to
  `docs/WHAT-IS-PROVEN.md`, and build, tools, tests and layout to
  `docs/entwicklung/BUILD.md`. The suspend defect has its own page,
  `docs/entwicklung/SUSPEND-DEFECT.md`.
- `tests/run-tests.sh` reads the README's test count from the prose line.
- Hardware: PASS on 2026-11-22 (`hw.runtime_20261119_01`).

## 20261115.01 (2026-11-15): the build fetches from a mirror when git.kernel.org does not answer

**No driver behaviour change.** The tarball differs from 20261109.01 in
`README.md` and `VERSION` only.

- `packaging/fetch-upstream.sh` tries git.kernel.org with a connect timeout of
  10 seconds and, at the first failure, takes the rest of the run from the
  GitHub mirror gregkh/linux (GitHub Actions runners could not reach
  git.kernel.org). New option `--source auto|kernel.org|github`.
- Unchanged: every file is checked against `packaging/upstream.lock`; a wrong
  hash is a hard failure whichever source delivered it.
- Seven new checks in `tests/run-tests.sh` for the fallback.

## 20261109.01 (2026-11-09): documentation follows the house HIG, documentation part

**No driver behaviour change.** Only Markdown files changed.

- README: the installation is a list of numbered steps with the checksum
  check, a check after the install and the way back
  (`sudo pacman -R macbook91-cs4208-dkms`); new "Usage" section for the runner.
- CHANGELOG headings carry ISO dates; incompatible changes come first, in bold.
- Stale statements corrected (`docs/INCIDENT-20261019.md`, `docs/PROJECT_STATE.md`).
- Code blocks in `docs/` carry a language; headings and tables lost their em
  dashes.

## 20261102.01 (2026-11-02): audit findings of the text interfaces

The module and the hook logic are unchanged. Fixes from an audit of the text
interfaces against the house HIG, text part.

- `macbook91-audio-verify`: help lines fit 80 columns; no dash as an aside.
  Check rows, verdict and exit status are unchanged.
- Install text: the rollback command reads `sudo pacman -R
  macbook91-cs4208-dkms` (it failed as typed without root).
- `packaging/promote-release.sh`: the help says that every release directory
  except the two newest is deleted, and the run names each one; status
  messages go to stderr.
- `macbook91-runner` and `dev-audio-collect.sh`: runs and baselines go to
  `$XDG_STATE_HOME/macbook91-cs4208/` (default `~/.local/state`), under sudo to
  the home of the user who ran sudo; recovery hints are error messages.
- Eight new checks in section 7f of `tests/run-tests.sh`.

## 20261026.02 (2026-10-26): text interfaces follow the house text HIG

**Incompatible:** `tools/dev-audio-collect.sh` prints only the output
directory on stdout. A script that read the lines `baseline written to:` and
`files:` from it must read the directory instead.

The module and the hook logic are unchanged. What changed is the text the
package and its tools print and accept at a terminal.

- `macbook91-audio-verify`: `-h/--help`, `-V/--version`, `-y`, `--no-input`,
  `--color=WHEN`/`--no-color`. A wrong option exits 2 with a `Did you mean:`
  line. Questions go to stderr; check lines and verdict stay on stdout. Ctrl+C
  and SIGTERM print `cancelled` and exit 130 and 143. Without a terminal the
  listening checks are reported SKIPPED.
- Pacman hook and `kernel-series`: the warning block is `==> WARNING:
  macbook91-cs4208` without rule lines; `kernel-series` has `--help` and
  `--version`.
- Install scriptlet: no capitalised headings or dashes, 80 columns.
- `make install` stamps the package version into the installed verifier.
- Development tools (not shipped) have `--help` and `--version` and report
  errors as `PROG: error: ...`; the runner keeps its exit codes 2, 3 and 4.
- The PKGBUILD sets `depends` inside `package()`, so makepkg also builds on a
  host without the CachyOS repositories.
- New section for the text interfaces in `tests/run-tests.sh`.

## 20261026.01 (2026-10-26): kernel series 7.3, the LTS kernel as the default, one series list

**Incompatible:** the package depends on `linux-cachyos-lts-headers` now, so
an upgrade installs it. The `A1534_ALLOW_SERIES_MISMATCH` override is gone: a
kernel of a series other than 6.18, 7.2 or 7.3 gets no module. After the
upgrade, check the kernels you use with `macbook91-audio-verify`.

**Driver behaviour changes.** The A1534 path pins its mainline fixup, and the
headphone jack callback re-routes a running stream after the bring-up replay.

- Linux 7.3 is a supported series next to 6.18 (LTS) and 7.2. Linux 7.3 added
  quirk rows for PCI subsystem 8086:7270 that select CS4208_MBA6, whose pin
  table marks the speaker pin unconnected. The patched probe now sets the
  fixup to CS4208_GPIO0 before the quirk tables are consulted, on every series
  (`local-changes.patch`, `docs/ROOT-CAUSE.md`).
- Headphone jack: after the replay both converters' cached stream setup is
  dropped and a running stream follows the jack state.
- One series list, `kheaders/KERNEL-SERIES`, drives `dkms.conf`, a new pacman
  hook (`71-macbook91-cs4208-series.hook`) that warns about unsupported
  kernels, and the verifier's "kernel series supported" check, which also
  FAILs a mainline pin override.
- Card profile: `analog-stereo` is an output as well (NOT RUN on hardware).
- Source identity: 6.18 `c7580fd70025fa36`, 7.2 `c6661a7c92c95904`, 7.3
  `6a7014b2db87a081`.

## 20261021.01 (2026-10-21): first public release; comments, attribution, licence headers and non-code files only

**Incompatible:** the audio baseline collector is `tools/dev-audio-collect.sh`
now (it carried the name of the maintainer's machine), and its default output
directory is `${XDG_STATE_HOME:-~/.local/state}/macbook91-cs4208/baselines`.
Scripts that call the old name or read the old directory must change.

**No driver behaviour change.** No executable line of the source tarball
changed; the module's source identity changes because it hashes files whose
comments were reworded (7.2 `3459bbf7be37223c`, 6.18 `2fc8b8ad2d1b2deb`).
Commit hashes named in entries up to this version belong to the maintainer's
private history and do not exist in the public repository.

- Comments reworded for a public reader; every changed C file is identical to
  20261020.03 once comments are stripped.
- Attribution and licences: `vendored/PROVENANCE.md` rewritten (the vendored
  trace is treated as GPL-2.0-only, an assumption stated as one); ACP profile
  files carry SPDX and derivation notices; `LICENSES/` gains GPL-3.0-or-later
  and BSD-3-Clause. No Apple binaries or copied Apple code or data are
  included; the documents describe the facts in the project's own words.
- Claims the evidence did not carry were corrected; the gate
  `evidence.trace_is_foreign_machine` stays FAIL.
- The history before 20261006.01 is summarised at the end of this file.
- README: installation from a release, a note on AI assistance, a license table.
- Tests: 253 passed, 0 failed, 9 blocked on a host with the module loaded.
- Hardware: NOT RUN; the results of 20261020.03 (6.18) and 20261020.01 (7.2)
  are carried over.

## 20261020.03 (2026-10-20): builds for the 6.18 LTS series as well as 7.2

**6.18: `macbook91-audio-verify` PASS on hardware; suspend/resume on 6.18 NOT
VERIFIED.** The 7.2 module is unchanged (source identity `79b16c8b296a3821`).
The maintainer ran the verifier under 6.18.55-2-cachyos-lts: 31 passed, 0
failed, 2 skipped (jack profile without headphones, HDMI not connected); the
listening checks were confirmed. The 7.2 result is carried over from 20261020.01.

- One source tree, several series: `upstream/<series>/cs420x.c`,
  `kheaders/<series>/` and the derived `<series>/cs420x.c` exist for every
  series `packaging/upstream.lock` pins (v6.18.55, v7.2.6). The module Makefile
  builds the matching series and refuses one the package does not ship.
- `packaging/fetch-upstream.sh` takes several `--tag`; `kheaders/KERNEL-SERIES`
  is a list.
- `dkms.conf` gets `BUILD_EXCLUSIVE_KERNEL="^(6\.18|7\.2)\."`.
- Tests: per-series lock coverage; the `dkms.conf` regex equals the shipped set.
- Not run: suspend and resume on 6.18, the DKMS rebuild on a kernel update.

## 20261020.02 (2026-10-20): GPL-3.0-or-later outside the kernel module; the provenance record brought up to date

**No driver behaviour change.** The module's source identity (`+79b16c8b296a3821`)
is unchanged.

- License, the maintainer's decision of 2026-10-20: everything written outside
  the kernel module is GPL-3.0-or-later. The module, its headers and what
  builds it or assembles its sources stay GPL-2.0-or-later. Nothing derived
  from other works is relicensed. Own files name their license on an SPDX
  line; `tests/run-tests.sh` 4e checks the lines against the map in the README.
- `vendored/PROVENANCE.md` records the capture measurement of 2026-10-20 and a
  license section for `ORIGINAL-a1534_sequence.h` (no upstream license;
  treated as GPL-2.0-only).
- English throughout; German evidence quotes stay verbatim.
- `docs/HEADSET-MIC.md` records the headset-microphone question.

## 20261020.01 (2026-10-20): a headphone plug no longer stops a running capture

**Driver fix.** A headphone plug during a running capture stopped it, and every
later capture stayed silent until the codec suspended (measured 2026-10-19
under 20261015.01, `docs/INCIDENT-20261019.md`). After the headphone replay the
capture converter had lost its stream tag. `a1534_pcm.h` now re-programs the
capture converter after every headphone replay and on every capture prepare.
Measured on hardware on 2026-10-20: `macbook91-runner jackstream` run
`20261020T063948Z-5274` PASS. Not run: a real call with a headset.

- `macbook91-runner jackstream` waits for a real plug state before each prompt
  and compares the source identity of the loaded and the on-disk module.
- `macbook91-audio-verify`'s headphone step keeps a capture running across the
  plug and the unplug.
- `tests/test_lock_discipline.py` checks the lock order of the capture resync.
- `docs/test-status.json`: `regress.concurrent_capture` is FAIL for 20261015.01
  and earlier and PASS since 2026-10-20.

## 20261015.01 (2026-10-15): a corrected verifier and tools from an audit of the tree

**No driver behaviour change.** Comments and two Makefile messages changed, so
the source identity is new; the compiled logic is that of 20261006.01.

- `macbook91-audio-verify` ends on Ctrl-C, checks this card's own sink and the
  DKMS entry of the running kernel, and plays a quiet tone in the hotplug step.
- `tools/macbook91-codec-state` addresses amplifier gain and mute by direction
  and channel (the 2026-09-14 comparison had read every field as input).
- The runner restores wake sources on every exit.
- `tests/run-tests.sh`: `contains_str` no longer fails with 141 under
  `pipefail`. `docs/RELEASING.md` collects the release procedure.

## 20261006.01 (2026-10-06): date-based versions

**No driver or content change.** The package is 0.5.1 under a new version
number. pacman orders `20261006.01` after `0.5.1`, so the update needs no
epoch; DKMS rebuilds the module under the new version. Release tags are
`v<VERSION>`.

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
