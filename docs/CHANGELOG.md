# Changelog

Versions have the form YYYYMMDD.NN (release date, NN counts releases that
day); the last section summarises the earlier numbering. Only
`release/20261115.01/` and `release/20261119.01/` are part of this repository;
older release directories cited below were removed from it and the citations
are history.

## 20261119.01 (2026-11-19): shorter README, user and developer pages under docs/, short runner help

**No driver behaviour change.** `macbook91-runner --help` no longer prints the
environment, the files and the exit status; they moved to `--help all`. A script
that reads those sections from `--help` must call `--help all`.

- README cut to 99 lines: installation in `docs/INSTALL.md`, the licence map in
  `docs/LICENSING.md`, the evidence in `docs/WHAT-IS-PROVEN.md`, build, tools,
  tests and layout in `docs/entwicklung/BUILD.md`.
- The suspend defect has its own page, `docs/entwicklung/SUSPEND-DEFECT.md`.
- `tests/run-tests.sh` reads the README's test count from the prose line.

## 20261115.01 (2026-11-15): the build fetches from a mirror when git.kernel.org does not answer

**No driver behaviour change.** The tarball differs from 20261109.01 in
`README.md` and `VERSION` only.

- `packaging/fetch-upstream.sh` tries git.kernel.org with a connect timeout of
  10 seconds and, at the first failure, takes the rest of the run from the
  GitHub mirror gregkh/linux (CI runners could not reach git.kernel.org).
- New option `--source auto|kernel.org|github`.
- Unchanged: every file is checked against `packaging/upstream.lock`; a wrong
  hash is a hard failure whichever source delivered it.
- Seven new checks in `tests/run-tests.sh` for the fallback.

## 20261109.01 (2026-11-09): documentation follows the house HIG, documentation part

**No driver behaviour change.** Only Markdown files changed.

- README: the installation is a list of numbered steps with a check after the
  install and the way back (`sudo pacman -R macbook91-cs4208-dkms`); new
  "Usage" section for the runner.
- CHANGELOG headings carry ISO dates; incompatible changes come first.
- Stale statements corrected (`docs/INCIDENT-20261019.md`,
  `docs/PROJECT_STATE.md`); code blocks in `docs/` carry a language.

## 20261102.01 (2026-11-02): audit findings of the text interfaces

The module and the hook logic are unchanged. Fixes from an audit of the text
interfaces against the house HIG, text part.

- `macbook91-audio-verify`: help lines fit 80 columns; check rows, verdict and
  exit status are unchanged.
- Install text: the rollback command reads `sudo pacman -R
  macbook91-cs4208-dkms` (it failed as typed without root).
- `promote-release.sh` names each release directory it deletes (all but the two
  newest). `macbook91-runner` and `dev-audio-collect.sh` write to
  `$XDG_STATE_HOME/macbook91-cs4208/`, under sudo to the invoking user's home.
- Eight new checks in section 7f of `tests/run-tests.sh`.

## 20261026.02 (2026-10-26): text interfaces follow the house text HIG

**Incompatible:** `tools/dev-audio-collect.sh` prints only the output
directory on stdout. A script that read the lines `baseline written to:` and
`files:` from it must read the directory instead. The module is unchanged.

- `macbook91-audio-verify`: `-h/--help`, `-V/--version`, `-y`, `--no-input`,
  `--color=WHEN`; a wrong option exits 2; Ctrl+C exits 130, SIGTERM 143;
  without a terminal the listening checks are reported SKIPPED.
- Pacman hook, `kernel-series` and the install scriptlet: one warning block
  (`==> WARNING: macbook91-cs4208`), 80 columns, `--help` and `--version`.
- Development tools (not shipped) have `--help` and `--version`. The PKGBUILD
  sets `depends` inside `package()`, so makepkg builds without CachyOS repositories.

## 20261026.01 (2026-10-26): kernel series 7.3, the LTS kernel as the default, one series list

**Incompatible:** the package depends on `linux-cachyos-lts-headers` now, so
an upgrade installs it. The `A1534_ALLOW_SERIES_MISMATCH` override is gone: a
kernel of a series other than 6.18, 7.2 or 7.3 gets no module. After the
upgrade, check the kernels you use with `macbook91-audio-verify`.

- Driver: Linux 7.3 is supported next to 6.18 (LTS) and 7.2. Its new quirk rows
  for PCI subsystem 8086:7270 select CS4208_MBA6 (speaker pin unconnected); the
  probe now sets CS4208_GPIO0 first, on every series. After the headphone
  replay a running stream follows the jack state.
- One series list (`kheaders/KERNEL-SERIES`), a pacman hook and a verifier check.
- Source identity: 6.18 `c7580fd7...`, 7.2 `c6661a7c...`, 7.3 `6a7014b2...`.

## 20261021.01 (2026-10-21): first public release; comments, attribution, licence headers and non-code files only

**Incompatible:** the audio baseline collector is `tools/dev-audio-collect.sh`
now (it carried the name of the maintainer's machine); its default output
directory is `${XDG_STATE_HOME:-~/.local/state}/macbook91-cs4208/baselines`.

**No driver behaviour change.** The source identity changes because it hashes
reworded comments (7.2 `3459bbf7be37223c`, 6.18 `2fc8b8ad2d1b2deb`). Commit
hashes in older entries belong to the maintainer's private history.

- `vendored/PROVENANCE.md` rewritten (the vendored trace is treated as
  GPL-2.0-only, an assumption stated as one); ACP profile files carry SPDX and
  derivation notices; no Apple binaries, code or data; unsupported claims corrected.
- Tests: 253 passed, 0 failed, 9 blocked. Hardware: NOT RUN, carried over.

## 20261020.03 (2026-10-20): builds for the 6.18 LTS series as well as 7.2

**6.18: `macbook91-audio-verify` PASS on hardware; suspend/resume on 6.18 NOT
VERIFIED.** The 7.2 module is unchanged (source identity `79b16c8b296a3821`).
Under 6.18.55-2-cachyos-lts: 31 passed, 0 failed, 2 skipped; listening checks
confirmed by the maintainer.

- One source tree, several series: `upstream/<series>/`, `kheaders/<series>/`
  and the derived `cs420x.c` exist for every series `packaging/upstream.lock`
  pins (v6.18.55, v7.2.6); the module Makefile refuses other series.
- `packaging/fetch-upstream.sh` takes several `--tag`.
- `dkms.conf` gets `BUILD_EXCLUSIVE_KERNEL="^(6\.18|7\.2)\."`.
- Not run: suspend and resume on 6.18, the DKMS rebuild on a kernel update.

## 20261020.02 (2026-10-20): GPL-3.0-or-later outside the kernel module; the provenance record brought up to date

**No driver behaviour change.** The source identity (`+79b16c8b296a3821`) is
unchanged.

- License, the maintainer's decision of 2026-10-20: everything outside the
  kernel module is GPL-3.0-or-later. The module, its headers and what builds it
  stay GPL-2.0-or-later; nothing derived from other works is relicensed.
- Own files name their license on an SPDX line; `tests/run-tests.sh` 4e checks
  the lines against the map in the README.
- `vendored/PROVENANCE.md` records the capture measurement of 2026-10-20 and the
  license of `ORIGINAL-a1534_sequence.h` (no upstream license; GPL-2.0-only).
- English throughout; `docs/HEADSET-MIC.md` records the headset-microphone question.

## 20261020.01 (2026-10-20): a headphone plug no longer stops a running capture

**Driver fix.** A headphone plug during a running capture stopped it, and later
captures stayed silent until the codec suspended (`docs/INCIDENT-20261019.md`).
`a1534_pcm.h` now re-programs the capture converter after every headphone replay
and on every capture prepare. Measured on 2026-10-20: `macbook91-runner
jackstream` run `20261020T063948Z-5274` PASS. Not run: a real call with a headset.

- `macbook91-runner jackstream` waits for a real plug state before each prompt.
- `macbook91-audio-verify`'s headphone step keeps a capture running across the plug.
- `tests/test_lock_discipline.py` checks the lock order of the capture resync.
- `regress.concurrent_capture` is FAIL for 20261015.01 and earlier, PASS since 2026-10-20.

## 20261015.01 (2026-10-15): a corrected verifier and tools from an audit of the tree

**No driver behaviour change.** Comments and two Makefile messages changed; the
compiled logic is that of 20261006.01.

- `macbook91-audio-verify` ends on Ctrl-C, checks this card's own sink and the
  DKMS entry of the running kernel, and plays a quiet tone in the hotplug step.
- `macbook91-codec-state` addresses amplifier gain and mute by direction and channel.
- The runner restores wake sources on every exit.
- `tests/run-tests.sh`: `contains_str` no longer fails with 141 under `pipefail`.
- `docs/RELEASING.md` collects the release procedure.

## 20261006.01 (2026-10-06): date-based versions

**No driver or content change.** The package is 0.5.1 under a new version
number. pacman orders `20261006.01` after `0.5.1`, so the update needs no
epoch; DKMS rebuilds the module. Release tags are `v<VERSION>`.

## 0.1.0 to 0.5.1 (2026-09-14 to 2026-10-06)

Before 20261006.01 the versions were numbered 0.1.0 to 0.5.1; their releases
are not part of this repository, and it describes that time by date. In short:
0.1 was the first bring-up (2026-09-14); 0.2 and 0.3 added the resume path and
the optional amplifier bring-up; 0.4.4 fixed silent speakers after a deep
suspend; 0.4.5 the missing audio device with headphones plugged in; 0.4.6
renamed the package to `macbook91-cs4208-dkms`; 0.5.0 stopped carrying kernel
source; 0.5.1 made the tarball reproducible and fixed the jack callback.
