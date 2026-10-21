# macbook91-cs4208

*This README is package-scoped: what the module does, its scope, provenance
and rollback. The top-level `README.md` owns overall project status and what
is and is not currently confirmed.*

Out-of-tree CS4208 codec driver that restores internal-speaker audio on the
Apple **MacBook9,1** (12-inch, Early 2016, A1534).

## What it does

Mainline Linux detects the CS4208 but leaves the internal speakers silent. On
this machine the speakers hang off a **digital, 8-channel** pin (`0x1d`) whose
only source is a **digital** converter (`0x0a`). The generic HD-audio parser
cannot bind an analog PCM to a digital converter, so no PCM is ever created for
that path, and the one analog device that does exist drives the headphone jack.

This module adds a playback PCM on converter `0x0a` and replays the amplifier
bring-up the four TAS5758L smart amplifiers need.

Full analysis: `docs/ROOT-CAUSE.md`, `docs/HARDWARE-PATH.md`.

## Scope

It activates **only** on a genuine MacBook9,1: DMI `Apple Inc.` / `MacBook9,1`
**and** codec SSID `106b:6500` - or `1013:4208`, which this codec reports in
its place once firmware state has been lost; that is accepted only because the
DMI check comes first. On every other CS4206/CS4207/CS4208 machine it behaves
exactly like the mainline driver it is built from. See
`a1534_match.h` and `../../tests/test_a1534_match.c` in the repository.

MacBook10,1 (2017) is **not** covered: it may well work, but there is no such
machine to verify it on, and this project does not ship untested claims.

## Deep suspend: fixed, confirmed on hardware

In early versions, the internal speakers stayed silent after a deep suspend (S3)
until the machine was rebooted. Headphones and the microphone were
unaffected; HDMI was not tested.

The cause, found 2026-09-14 and confirmed by measuring 722 capability-validated
codec fields either side of one deep suspend:

    converter 0x0a   cvt_chan_count   0x03  ->  0x00

`cvt_chan_count` is a register of its own, separate from the stream format,
holding channels minus one. Firmware programs four; a suspend leaves one. The
format word still reads four channels, so everything above the converter sees
four channels while the converter itself emits one into a four-slot TDM frame.
Nothing in Linux restores it: the HDA regmap deliberately keeps this register
out of its writeable set ("managed in HDMI CA code", which this codec has
none of), so `snd_hda_regmap_sync()` never replays it, and the vendored macOS
trace never writes it either. Headphone converter `0x02` has no such register,
which is why headphones survived every resume.

One limit of that comparison, found 2026-10-15: the capture tool read every
amplifier gain/mute field as the input amplifier, right channel, index 0,
because it put the direction and channel selector into the 8-bit parameter
the hwdep ioctl passes, where the codec never sees it. Amplifier output state
either side of the suspend was therefore not compared, and "the only field
that moves" holds for the other fields only. macbook91-codec-state now
addresses the amplifiers correctly. The fix itself is measured on its own:
with the channel count programmed on resume the speakers play after deep
suspend (gate fix.cvt_chan_count_programmed in docs/test-status.json).

The driver programs `cvt_chan_count` from the negotiated format at every stream
setup, and carries it in the probe-time snapshot so a resume with no stream
running is also correct. Confirmed audible on hardware after a deep suspend.
Measured across five deep suspends on 2026-09-15, the longest 1 h 44 min
(gate `hw.long_suspend_coverage` in the repository's `docs/test-status.json`).

### What the snapshot/restore mechanism does

At probe, while state is still intact, the driver reads the registers Linux
does not manage — the 128 vendor coefficients behind widget `0x24`, the
per-pin configuration defaults, and `cvt_chan_count` — and after a deep sleep
it writes all of them back, then runs the normal bring-up on top. Nothing is
compared first: on the resume path a read is answered from a stale cache, so
the write is unconditional.

The recovery only ever runs in a state that is already broken, and only writes
values this same codec reported on this same boot, so it cannot affect a
working cold boot. It can be turned off with `a1534_restore=0`.

Pin configuration defaults are restored as part of this mechanism. An earlier
version of this project believed restoring them was a mistake because a
resume once left the microphone pins reading "not present" — that was traced
to a saved ALSA mixer state, not to this restore; see
`tests/run-tests.sh` around the pin-configuration-restore test.

### The amplifiers, recovered from Apple's own driver

The internal speakers are driven by four TI TAS5758L amplifiers — separate
chips with their own register state, reached over an I2C bus mastered by the
codec itself through vendor widget `0x24`. Whether a deep sleep drops their
supply or their configuration is not known (`docs/CLAIMS-AUDIT.md`, claims D2,
D3 and D6): macOS has no resume path for these amplifiers, and the
converter fix alone brought the speakers back.

The driver can replay their bring-up, off by default (below). The
transport and the eight-register bring-up sequence were
recovered from `AppleHDA` in the official macOS recovery image Apple serves for
this machine's board id, verified against Apple's own RSA-signed chunklist.
See `docs/AMPLIFIER-PROTOCOL.md`. The driver implements the protocol; no Apple
binary is included.

The bring-up reads every register back and reports how many of the four
amplifiers verified, so the kernel log says plainly whether the bus answered.

Every amplifier read on this machine returned `0x0000` — but so did a read
from an I2C address with nothing on it, in the same sweep, while the speakers
were working. A read procedure that gives the same answer for a present
device and an absent one has not measured either of them, so nothing is
concluded in either direction: the transport is unproven, not disproven. The
bring-up stays off by default for that reason.

Enable it with `a1534_amp=1` to continue the investigation;
`tools/macbook91-amp-transport` exists to first show whether the read
path can even tell an amplifier address from an empty one before any write is
trusted.

**If the bring-up does not work, the behaviour is exactly as before: nothing
about this is destructive, and headphones and the microphone keep working
either way.**

The kernel log carries the firmware state as found at probe (the 128
coefficients and the vendor widget's registers) and, at every resume, one
summary line: how many coefficients and pin configurations were written, and
the converter's channel count. Which registers a deep sleep actually changes
is not logged; that would need a trustworthy read on the resume path.

### s2idle is not a workaround

An s2idle cycle left the internal speakers silent as well (maintainer-reported,
2026-09-14, before the fix), and since the fix deep suspend needs none. This
package does not change your suspend mode.

## Building it

You need the kernel headers of the kernel you are building **for** - that is
the only distribution-specific requirement, and this package does not name a
kernel of its own:

```
sudo pacman -S linux-cachyos-headers      # CachyOS default kernel
sudo pacman -S linux-cachyos-lts-headers  # CachyOS LTS
sudo pacman -S linux-headers              # Arch default kernel
sudo pacman -S linux-lts-headers          # Arch LTS
```

The compiler follows from that kernel's own `.config`, not from this machine:
a kernel built with clang needs `clang lld llvm`, a kernel built with GCC
needs `gcc`. Nothing guesses on your behalf - `make check` and the install
scriptlet each name the one that is missing, and the command that installs it.

Then, from the repository root:

```
make arch-pkg-dev
```

That assembles the upstream-derived sources first — one download, from
git.kernel.org, every file checked against `packaging/upstream.lock` before it
is allowed into the tree — then stages the tarball and runs `makepkg`. Every
rebuild afterwards, including the automatic DKMS rebuild during a kernel
upgrade, touches no network at all.

One rule worth knowing: the private HDA headers are per **kernel series**.
The package ships a separate set for 6.18 (the LTS series) and 7.2, and the
build picks the set that matches the target kernel's `utsrelease.h`. A series
the package does not ship is refused, and `dkms.conf` limits DKMS to the
shipped series, so a 6.19 or 7.3 kernel is skipped rather than built against
the wrong headers. They are internal structure definitions with no ABI
promise, so a mismatch can be silent, which is exactly the class of bug this
project has already paid for once. A new series needs its tag in
`packaging/upstream.lock` first: `packaging/fetch-upstream.sh --tag vX.Y.Z
--accept-new` records its hashes, and `local-changes.patch` must still apply
exactly (`--fuzz=0`) or the fetch fails. Review and commit the lockfile
change; `make arch-pkg-dev` then builds from the newest tag it lists for each
series. Do not override the check.

Status: 7.2 is the series the speaker, microphone and suspend results were
obtained on. 6.18 (LTS): `macbook91-audio-verify` passed on this machine under
6.18.55-2-cachyos-lts with module `20261020.03+7fc96add428d9fce` (31 passed,
0 failed, 2 skipped; the listening and jack checks were confirmed by the
maintainer). Suspend/resume on 6.18 is NOT VERIFIED: no suspend happened in that
boot. The 7.2 runtime result of 20261020.03 is carried over from the previous
release, whose module code is identical.

## Provenance

- `upstream/<series>/cs420x.c` and `kheaders/<series>/` are verbatim kernel
  sources, fetched at the tag recorded in `packaging/upstream.lock` for each
  series rather than stored in this repository. Integrity in `UPSTREAM.sha256`, this project's changes in
  `local-changes.patch`, the whole scheme in `UPSTREAM.txt`.
- `vendored/a1534_sequence.h` is the amplifier bring-up trace. It is
  **empirical, not derived** — read `vendored/PROVENANCE.md` before touching
  it. It is never downloaded: it is derived offline from
  `vendored/ORIGINAL-a1534_sequence.h`, which is a permanent part of this
  repository and of the package.

## License

What the package installs, by license. Source, script and configuration files
name their license on an `SPDX-License-Identifier` line, with two exceptions:
the vendored upstream header `vendored/ORIGINAL-a1534_sequence.h` (it has a
`.license` marker file) and the header made from it, `vendored/a1534_sequence.h`;
both are hash-pinned in `vendored/PROVENANCE.sha256`. Documentation, data,
patches, license texts and the records the build writes carry none and follow
the list below.

- GPL-2.0-or-later, as in Linux: `<series>/cs420x.c`, `upstream/`, `kheaders/` and
  `local-changes.patch`.
- GPL-2.0-only, an assumption recorded in `vendored/PROVENANCE.md`:
  `vendored/ORIGINAL-a1534_sequence.h`, `vendored/a1534_sequence.patch` and
  `vendored/a1534_sequence.h`.
- GPL-2.0-or-later: this project's module headers, `a1534_*.h`, and what
  builds the module: `Makefile`, `dkms.conf` and the records `UPSTREAM.lock`,
  `UPSTREAM.sha256`, `vendored/PROVENANCE.sha256` and
  `kheaders/KERNEL-SERIES`.
- LGPL-2.1-or-later, as the alsa-card-profile files they derive from:
  `contrib/acp/`, also installed to `/usr/share/macbook91-cs4208/acp/`.
- GPL-3.0-or-later: everything else, `/usr/bin/macbook91-audio-verify`
  included.

The license texts are in `/usr/share/licenses/spdx/`, from the `licenses`
package.

## Rollback

This package is not only a kernel module. It installs, and `pacman -R
macbook91-cs4208-dkms` removes again:

- the DKMS source tree under `/usr/src/macbook91-cs4208-<version>`, and the
  module DKMS builds from it — `snd-hda-codec-cs420x` under
  `/lib/modules/<kver>/updates/`, which depmod prefers over the in-tree copy;
- `/usr/bin/macbook91-audio-verify`, the verification tool;
- the WirePlumber drop-in
  `/usr/share/wireplumber/wireplumber.conf.d/51-macbook91-cs4208.conf`. It is
  card policy for this machine and it is **not** optional: the internal speaker
  path has no hardware volume control, so without the software mixer the
  desktop slider does nothing and output stays at full scale, and the stock ACP
  profile set drops this card's only analog output port whenever the headphone
  jack is plugged;
- the two ACP files that drop-in names, under this package's own prefix so they
  cannot collide with another package's:
  `/usr/share/macbook91-cs4208/acp/macbook91-cs4208.conf` and
  `/usr/share/macbook91-cs4208/acp/macbook91-output-speaker.conf`;
- this README, as `/usr/share/doc/macbook91-cs4208-dkms/README.md`.

Removing the package removes every one of those files and runs depmod. The
module that is already loaded stays in memory until the next reboot; after
that, the stock kernel codec is used again. Restart WirePlumber
(`systemctl --user restart wireplumber`) afterwards, the same command the
install scriptlet asks for, so the drop-in stops applying without a logout.

What stays true is the part worth keeping: nothing outside this package's own
files is touched. No blacklists, no modprobe.d overrides, no edits to anyone
else's configuration, no change to the suspend mode — so rollback is complete,
and it is pacman that makes it complete.
