# macbook91-cs4208

Internal speakers, headphones, microphone and **deep-suspend survival** for the
Cirrus Logic CS4208 in the **MacBook9,1 (A1534)**, as an out-of-tree DKMS
module for Arch-family distributions.

Mainline Linux has no MacBook9,1 entry for this codec. Without one the generic
HD-audio parser cannot bind a PCM to the speaker path at all, and after a
suspend the speakers stay silent until a reboot. This package fixes both.

## Install

Requirements: `base-devel`, `dkms`, the headers of every kernel you use and,
for kernels built with clang (CachyOS), `clang`, `lld` and `llvm`.

1. Download `PKGBUILD`, `macbook91-cs4208.install`, the source tarball
   `macbook91-cs4208-dkms-VERSION.tar` and `SHA256SUMS` from the
   [latest release](https://github.com/Weegee/macbook91-cs4208-pub/releases/latest)
   into one new directory.
2. In that directory, check the files, build and install, then reboot:

   ```bash
   sha256sum -c --ignore-missing SHA256SUMS
   makepkg -si
   ```

   The check prints three `OK` lines (`PKGBUILD`, the `.install` file and the
   tarball). Look for all three: the exit status alone does not show it.

3. After the reboot, run the checks in a terminal and answer the listening
   questions when it asks (`--no-sound` runs the software checks only):

   ```bash
   macbook91-audio-verify
   ```

To undo it, remove the package and reboot; the stock in-tree codec is back:

```bash
sudo pacman -R macbook91-cs4208-dkms
```

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

## What is proven

Confirmed on the machine: four-channel speakers from cold boot,
headphones with hotplug, internal microphone, sound before and after a deep
suspend, clean rollback, DKMS clang build.

The suite in `tests/` has 343 hermetic tests; they need no root, no hardware
and no sound, so they say nothing about the speakers themselves.

Not confirmed: release 20261115.01 has not run on hardware, and no 7.3 kernel
has run this module. A real call with a headset has not been run. HDMI is out
of scope. Per release and per kernel: `docs/WHAT-IS-PROVEN.md`.

## Read on

| You want | Read |
| --- | --- |
| install details, remove, what has not run | `docs/INSTALL.md` |
| what has run on hardware | `docs/WHAT-IS-PROVEN.md` |
| what changed per release | `docs/CHANGELOG.md` |
| why the speakers fell silent | `docs/entwicklung/SUSPEND-DEFECT.md`, `docs/ROOT-CAUSE.md` |
| build, tools, tests, release, layout | `docs/entwicklung/BUILD.md`, `docs/RELEASING.md`, `STRUCTURE.md` |
| licenses, provenance, Apple driver research | `docs/LICENSING.md` |
| the claims and what withdrew them | `docs/CLAIMS-AUDIT.md` |

## AI assistance

Claude (an AI model by Anthropic) wrote the project's own code, tests and
documentation; the maintainer gave the directions and made the decisions.
Hardware checks ran on a MacBook9,1 under the maintainer's direction and count
only as far as `docs/test-status.json` records them as run. Commits that Claude
contributed to carry a Co-Authored-By trailer. Read the code before you load a
kernel module or run a script as root.

## Bug reports and license

Open an issue at <https://github.com/Weegee/macbook91-cs4208-pub/issues> and
name the kernel (`uname -r`), the package version
(`pacman -Q macbook91-cs4208-dkms`) and the output of `macbook91-audio-verify`.

The module derives from mainline `cs420x.c` (GPL-2.0-or-later); everything else
is GPL-3.0-or-later, with named exceptions: `docs/LICENSING.md`.
