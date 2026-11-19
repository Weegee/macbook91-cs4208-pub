# What is proven, and what is not

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

**Not confirmed:** 20261119.01 (module code of 20261026.01) has not run on hardware, and no kernel of the 7.3
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
