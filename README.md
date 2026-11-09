# macbook91-cs4208

Internal speakers, headphones, microphone and **deep-suspend survival** for the
Cirrus Logic CS4208 in the **MacBook9,1 (A1534)**, as an out-of-tree DKMS
module for Arch-family distributions.

Mainline Linux has no MacBook9,1 entry for this codec. Without one the generic
HD-audio parser cannot bind a PCM to the speaker path at all, and after a
suspend the speakers stay silent until a reboot. This package fixes both.

## AI assistance

This project was written by Claude (an AI model by Anthropic): Claude wrote the
project's own code, tests and documentation, and the maintainer gave the directions
and made the decisions. Hardware checks were run on a MacBook9,1 under the
maintainer's direction and count only as far as docs/test-status.json records them as
run; everything else there is marked as not run or carried over. Commits that Claude
contributed to carry a Co-Authored-By trailer; the first public commit is a snapshot
of the earlier private history and carries it too. Read the code before you load a
kernel module or run a script as root.

## What it does

| | |
| --- | --- |
| Internal speakers | four channels through converter `0x0a` → pin `0x1d`, 44.1 kHz, 16-bit |
| Headphones | converter `0x02` → pin `0x10`, with hotplug in both directions |
| Microphone | internal, unchanged from the generic path; a headset microphone is not detected (`docs/HEADSET-MIC.md`) |
| Deep suspend | speakers keep working across S3 |
| Rollback | `pacman -R` and a reboot restore the stock in-tree codec |

It activates **only** on this machine: DMI must read `MacBook9,1` and the codec
must be a CS4208. Every other CS420x machine keeps mainline behaviour byte for
byte.

## Installation (Arch Linux and derivatives)

Requirements: `base-devel`, `dkms`, the headers of every kernel you use and,
for kernels built with clang (CachyOS), `clang`, `lld` and `llvm`. The build
refuses to run if the toolchain family does not match the kernel's, rather than
producing a module that loads and misbehaves.

1. Open the [latest release](https://github.com/Weegee/macbook91-cs4208-pub/releases/latest)
   and download `PKGBUILD`, `macbook91-cs4208.install`, the source tarball
   `macbook91-cs4208-dkms-VERSION.tar` and `SHA256SUMS` into one new
   directory. VERSION is the release's version, for example `20261102.01`.
2. In that directory, check the files:

   ```bash
   sha256sum -c --ignore-missing SHA256SUMS
   ```

   The output lists three files, each with `OK`:

   ```text
   PKGBUILD: OK
   macbook91-cs4208.install: OK
   macbook91-cs4208-dkms-VERSION.tar: OK
   ```

3. Build and install the package:

   ```bash
   makepkg -si
   ```

4. Reboot.
5. Check the installation in a terminal and answer the listening checks when
   it asks:

   ```bash
   macbook91-audio-verify
   ```

`--ignore-missing` skips the lines of `SHA256SUMS` whose files you did not
download (`.SRCINFO`, `STATUS.txt`, `upstream.lock`, or any of the three files
above). It fails when none of the listed files is there, but it exits
successfully as soon as one of them is, so the exit status alone does not show
that the three files were checked: look for the three `OK` lines.
`macbook91-audio-verify --help` lists the verifier's options; `--no-sound` runs
the software checks only and plays and records nothing.

To undo the installation, remove the package and reboot; the stock in-tree
codec is back:

```bash
sudo pacman -R macbook91-cs4208-dkms
```

Checked on 2026-11-09: step 2, on the files of release 20261102.01. Not run
for this revision of the text: steps 3 to 5 and the removal. What has run on
hardware, release by release, is under "What is proven, and what is not".

From a checkout the same files are in `release/<version>/`. To build from the
source tree instead (`make dist`, which `make arch-pkg` runs, needs a git
checkout of the repository, not an unpacked tarball or release download):

```bash
make arch-pkg
sudo pacman -U dist/macbook91-cs4208-dkms-*.pkg.tar.zst
```

`make arch-pkg` assembles the upstream-derived sources at the newest kernel tag
`packaging/upstream.lock` records for each supported series (six files per
series from git.kernel.org, or none with `FETCH_ARGS="--offline --all"` and a
filled cache), writes the source tarball, and builds the package in
`build/arch/` (copied to `dist/`). It needs a committed tree whose tarball
checksum is pinned in `packaging/arch/PKGBUILD`; `make arch-pkg-dev` builds an
unreleased tree as it is on disk.

No built package is attached to this release; build it with `makepkg` as
above. If a later release lists a ready-built package, install that with
`sudo pacman -U` instead. Packages are not signed. If you maintain your own
pacman repository, add the package to it as usual.

`release/<version>/` carries the `PKGBUILD`, `.SRCINFO`, the source tarball, the
install scriptlet, `upstream.lock` (the pinned hashes of the kernel files the
tarball was assembled from), `SHA256SUMS` and a status note for the newest
promoted release. These files are the release's assets. A built
`.pkg.tar.zst` is neither committed nor attached, because its build metadata
records the builder's directories and installed packages. `STATUS.txt` records
the checksum of the maintainer's local build for reference only; a package you
build yourself has a different checksum.

## Usage

After the installation, run `macbook91-audio-verify` (step 5 above). The
measurement tools in `tools/` are for work from a checkout; `tools/README.md`
says which one to reach for. Their entry point is `tools/macbook91-runner`:

```bash
tools/macbook91-runner selfcheck        # nothing is touched
tools/macbook91-runner preflight        # identity, versions, sleep mode
sudo tools/macbook91-runner probe --with-stream
tools/macbook91-runner diff             # two captures, field by field
tools/macbook91-runner wake             # what wakes the machine early
```

The output of `selfcheck` on 2026-11-09, shortened to the check lines and the
verdict (the free-space check and the run paths are left out):

```text
== selfcheck (nothing is touched) ==
selfcheck.macbook91-amp-transport      PASS     present and parses
selfcheck.dep.python3                  PASS     /usr/bin/python3
selfcheck.dep.aplay                    PASS     /usr/bin/aplay
selfcheck.dep.systemctl                PASS     /usr/bin/systemctl
selfcheck.dep.modinfo                  PASS     /usr/bin/modinfo
selfcheck.unit_restore                 PASS     save/restore bookkeeping runs and verifies
selfcheck.not_root                     PASS     running unprivileged, as it should

== verdict: PASS ==
```

Every run lands in one directory under `$XDG_STATE_HOME/macbook91-cs4208/runs/`
(by default `~/.local/state/macbook91-cs4208/runs/`) that survives a reboot,
with a human report and a machine-readable result.
Each test reports PASS, FAIL, BLOCKED, NOT_RUN or SKIPPED; a mandatory test
that is never reached forces the verdict to INCOMPLETE rather than disappearing.
The other commands were not run for this revision of the text.

## The defect this exists for, and how it was found

After every resume the speakers were silent while headphones worked. Restoring
the codec's 128 vendor coefficients, its 19 pin configuration defaults, a
function reset, a full re-probe and a PCI remove/rescan all failed. So did
`s2idle`.

The cause was a single register:

```text
converter 0x0a   cvt_chan_count   0x03  ->  0x00
```

Found by capturing 722 capability-validated fields of codec state either side
of one suspend, at rest and with a four-channel stream running, with the
speakers confirmed audible before and silent after. It is the **only**
functional field in the whole codec that moves.

One limit of that comparison, found 2026-10-15: the capture tool read every
amplifier gain/mute field as the input amplifier, right channel, index 0,
because it put the direction and channel selector into the 8-bit parameter
the hwdep ioctl passes, where the codec never sees it. Amplifier output state
either side of the suspend was therefore not compared, and "the only field
that moves" holds for the other fields only. macbook91-codec-state
addresses the amplifiers correctly since 20261015.01. The fix itself is measured on its own:
with the channel count programmed on resume the speakers play after deep
suspend (gate fix.cvt_chan_count_programmed in docs/test-status.json).

The register holds *channels − 1*. Firmware programs four; a suspend leaves
one. The stream format word is untouched, so everything that inspects the
format sees a correct four-channel stream while the converter emits a single
channel into a TDM frame the four TAS5758L amplifiers read as four slots.

Nothing in Linux restores it: `sound/hda/core/regmap.c` deliberately keeps
`AC_VERB_GET_CVT_CHAN_COUNT` out of the regmap's writeable set (*"managed in
HDMI CA code"*), so `snd_hda_regmap_sync()` never replays it, and this codec
has no HDMI CA code. Headphone converter `0x02` has no such register, which is
exactly why headphones always survived a resume.

## Layout

```text
src/cs420x-a1534/   the module: mainline cs420x.c plus a gated A1534 path
tools/              measurement tools, one entry point: macbook91-runner
tests/              336 hermetic tests, no root, no hardware, no sound
packaging/          the fetcher, its lockfile, the tarball and release scripts
packaging/arch/     PKGBUILD, .SRCINFO and the install scriptlet
Makefile, VERSION   dist, install and package targets; the version
release/<version>/  the promoted PKGBUILD, source tarball and status note
LICENSES/           the license texts the SPDX lines name
docs/               the investigation, including everything that was wrong
```

`STRUCTURE.md` states the same layout as a rule rather than a description.

The test count above is that of a host with the replacement module loaded.
A host that still runs the stock codec runs one more test and blocks the two
checks that compare the recorded totals, so it reports 335 passed, 0 failed,
10 blocked. That figure was measured on 2026-11-02 on a development host that
runs the stock codec; the count above is derived from it and was not run on a
host with the module loaded. A suite started with SIGINT ignored, as a
background job does, gives
the same result as one started in the foreground.

`docs/CLAIMS-AUDIT.md` is worth reading before trusting anything here: it lists
each claim against the raw evidence, what that evidence actually supports, the
alternative that was not excluded, and the experiment that would decide it.
Several conclusions in this project's own history were withdrawn that way.

## What is proven, and what is not

**Confirmed on the machine:** four-channel speakers from cold boot, software
volume, headphones with hotplug both ways, internal microphone, no codec wedge,
clean rollback to the stock codec, DKMS clang build; sound before *and* after
a deep suspend, across suspends up to 1 h 44 min; and sound through the
headphones while the card keeps its analog profile (without that fix the
machine had no audio device at all whenever the jack was plugged).

**Not working in 20261015.01 and earlier:** a headphone plug during a running
capture stops that capture, and every capture opened after it stays silent,
unplugging included, until the codec suspends (measured 2026-10-19,
`docs/INCIDENT-20261019.md`). In a call the microphone goes quiet when the
headset goes in. The earlier record of a capture surviving the plug was
wrong: the headphones were already in when that test asked for the plug.
20261020.01 re-programs the capture converter after every headphone replay;
measured on hardware on 2026-10-20 (`macbook91-runner jackstream`,
`regress.concurrent_capture` PASS). A real call with a headset plugged in has
not been run. On 20261015.01 or earlier: end the call, or stop every playback
and capture for a few seconds, and the next capture works again.

**Not confirmed:** 20261102.01 (module code of 20261026.01) has not run on hardware, and no kernel of the 7.3
series has run this module: it builds for 7.3.0-4-cachyos with no compiler
diagnostic, nothing more. A kernel update within a series has happened, and
DKMS rebuilt the module for it (2026-09-21, gate `hw.dkms_kernel_update`). A
series the package does not support fails closed (DKMS skips it, the pacman
hook warns about it after the transaction, a direct build stops on the series
check, and the wrong compiler family is refused). **6.18 (LTS): `macbook91-audio-verify`
PASS on hardware** (2026-10-20, 6.18.55-2-cachyos-lts, module
`20261020.03+7fc96add428d9fce`: 31 passed, 0 failed, 2 skipped; the speaker
tone, microphone, headphone detect and the capture across plug and unplug were
confirmed by the maintainer). DKMS installed the package for 6.18.55-2-cachyos-lts
and 7.2.11-1-cachyos. **Not verified on 6.18:** suspend/resume (no suspend
happened in that boot), a real call with a headset, HDMI. The 7.2 runtime
result of 20261020.03 is carried over from 20261020.01 and .02 (module code
identical). **20261021.01 was not run on hardware:** its 6.18 and 7.2 results
are carried over from 20261020.03 and 20261020.01. The tarball differs from
20261020.03 in comments, attribution, licence headers and non-code files
(version, pins, READMEs, provenance notes) only; the module code is the same
(the source identity string changes, `docs/CHANGELOG.md`). HDMI is outside the
validated scope by choice: this machine is practically never connected to an
external display. The amplifier I2C transport
described in `docs/AMPLIFIER-PROTOCOL.md` is **not** a working instrument: it
cannot tell an occupied I2C address from an empty one, so nothing is concluded
from it in either direction, and the amplifier bring-up stays off by default.

## History

The record of the investigation is worth more than the snapshot. It was wrong
several times: the amplifiers were blamed for a week, an I2C transport was read
as evidence when it could not tell an occupied address from an empty one, and a
suspend hook was trusted that had never once executed. `docs/` says what was
measured, what it supported and what had to be withdrawn.

This repository starts from a snapshot of the project. The development history
before it is not published, and older releases are not part of this repository;
`docs/CHANGELOG.md` lists every release and what changed in it. `release/` keeps
only the promoted files of the newest versions (`packaging/promote-release.sh`
prunes the rest).

## Bug reports

Open an issue at <https://github.com/Weegee/macbook91-cs4208-pub/issues>. Name
the kernel (`uname -r`), the package version (`pacman -Q macbook91-cs4208-dkms`)
and attach the output of `macbook91-audio-verify`.

## Provenance and licensing

The module derives from mainline `sound/hda/codecs/cirrus/cs420x.c`; the
local delta is kept small, gated, and recorded in
`src/cs420x-a1534/local-changes.patch`.

Licenses, by path. Source, script and configuration files name the same
license on an `SPDX-License-Identifier` line; documentation, data, patches,
`VERSION` and the generated `.SRCINFO` carry none and follow the table.
`LICENSE` holds the GPL-3.0 text (also as `LICENSES/GPL-3.0-or-later.txt`),
`LICENSES/` the others.

| Path | License |
| --- | --- |
| `src/cs420x-a1534/<series>/cs420x.c`, `upstream/` and `kheaders/` (fetched from Linux at build time, never tracked), `src/cs420x-a1534/local-changes.patch` | GPL-2.0-or-later, as in Linux |
| `src/cs420x-a1534/vendored/ORIGINAL-a1534_sequence.h` (marker: `ORIGINAL-a1534_sequence.h.license`), `a1534_sequence.patch` and the derived `a1534_sequence.h` | GPL-2.0-only, an assumption: `vendored/PROVENANCE.md` |
| `src/cs420x-a1534/a1534_*.h`, `tests/*.c` | GPL-2.0-or-later: built into the kernel module, or with its headers |
| what builds the module or assembles its sources: `src/cs420x-a1534/Makefile` and `dkms.conf`, `packaging/fetch-upstream.sh` and `packaging/upstream.lock`, and the records the fetcher writes for the build (`UPSTREAM.lock`, `UPSTREAM.sha256`, `vendored/PROVENANCE.sha256`, `kheaders/KERNEL-SERIES`) | GPL-2.0-or-later: GPLv2 section 3 counts the scripts that control compiling and installing the module as part of its source |
| `src/cs420x-a1534/contrib/acp/` | LGPL-2.1-or-later, as the alsa-card-profile files they derive from; the upstream notice is retained in each file |
| `tools/macbook91-fetch-macos-recovery`, `tools/macbook91-verify-recovery-image` | BSD-3-Clause, derived from OpenCorePkg's `macrecovery.py` (`LICENSES/BSD-3-Clause.txt`) |
| everything else: tools, tests, packaging, the top-level `Makefile`, configuration, documentation, data | GPL-3.0-or-later |

GPL-3.0 cannot go into the kernel module, because the kernel is GPL-2.0-only,
and whoever passes on a built module has to provide its build files under
GPLv2 as well. A module built from these sources combines GPL-2.0-or-later
and GPL-2.0-only code; `MODULE_LICENSE("GPL")` in `cs420x.c`, unchanged from
Linux, states GPL version 2 to the kernel.

The two recovery tools derive from OpenCorePkg's
`Utilities/macrecovery/macrecovery.py` (<https://github.com/acidanthera/OpenCorePkg>)
and keep its BSD-3-Clause license and copyright notices. The A1534 verb
sequence comes from <https://github.com/leifliddy/macbook12-audio-driver>,
which states no license; `src/cs420x-a1534/vendored/PROVENANCE.md` records
where it comes from, who wrote it, and why it is treated as GPL-2.0-only. If you
hold rights in it and object to its inclusion, open an issue and it will be
removed. Quotations from other works in `docs/` keep those works' terms.
Earlier releases (up to 20261020.01) were made under their own licensing; they
are not part of this repository.

`docs/AMPLIFIER-PROTOCOL.md` and `docs/APPLE-I2C-AUDIT.md` describe an
interface recovered by disassembling Apple's own driver, for the sole purpose
of operating hardware its owner already owns. **No Apple binaries are
included, and no Apple code or data is copied.** For interoperability
research, `docs/` describes what was recovered from Apple's AppleHDA driver:
pseudo-code descriptions of six of its routines, written for this project from
the disassembly (`docs/APPLE-I2C-AUDIT.md`, sections 2 to 5 and 8; sections 2.1
to 2.3 and 3 of `docs/AMPLIFIER-PROTOCOL.md` restate four of them more
compactly), and facts such as register addresses and values, I2C addresses and
layout settings, in the project's own words and tables.
