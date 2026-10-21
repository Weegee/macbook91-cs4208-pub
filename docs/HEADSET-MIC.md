# Headset microphone: not detected

**Status: open. Calls use the internal microphone even with a four-pole
headset plugged in. Nothing here changes the driver; the probe below has not
been run.**

## What is measured

On 2026-10-19, under 20261015.01, with a four-pole headset plugged into the
combined jack during a call:

- the headphones played, and the capture source stayed the internal
  microphone, which is what KDE named;
- `alsactl monitor` saw `Headphone Jack` events for the plug and the unplug
  and no `Mic Jack` event (`docs/INCIDENT-20261019.md`);
- pin `0x18`, the external microphone pin, read `Pin-ctls: 0x20: IN
  VREF_HIZ` and `Power: setting=D3, actual=D3` in `/proc/asound/card0/codec#0`,
  with unsolicited responses enabled (tag 2).

Idle with the headphones out, read after the reproduction, the same pin read
`Pin-ctls: 0x24: IN VREF_80`, the bias the generic parser sets, and D3.

Pin `0x18` advertises presence detect and the reference voltages HIZ, 50,
GRD and 80 (`Pincap 0x00001724`); its default configuration is a pink
external microphone jack on a combination connector (`Pin Default
0x00ab9030`). The generic parser therefore offers a `Mic Jack` control and
would switch the capture to this pin, through ADC `0x07`, on a jack event.
That event never came.

## What the headphone replay does to the pin

`headphones_a1534()` in `src/cs420x-a1534/vendored/ORIGINAL-a1534_sequence.h`
(the tracked source of the derived `a1534_sequence.h`, which differs from it
in two places that do not touch this function), which the driver replays on
every headphone plug, reads the pin's presence once
(the value the sequence expects is 0), sets its pin control to `0x04` and
then `0x20` (input enabled, no bias) and puts it into D3. It reads as
written for a plug without a microphone. How the upstream author obtained
the sequence is not documented (`src/cs420x-a1534/vendored/PROVENANCE.md`),
so this file does not say where it comes from. Replayed for a headset, it
leaves the headset's microphone without bias, so even a correct switch to the
pin would record silence.

## What macOS does on this machine

The macOS audio layouts for this codec in the macOS recovery image
(`layout121.xml`, `layout127.xml` and `layout129.xml`, decoded; codec
`0x10134208`, path map 73) agree on these points:

- the external microphone is pin `0x18` into ADC `0x07`, with input boost 3
  (`Platforms.xml`, path map 73);
- an `InternalMikey` block: `MikeyDetectDelay` 500, `HeadsetRetryTimeout`
  250, `JackConfig1` 17555 (`0x4493`), `JackConfig2` 6931 (`0x1b13`);
- `ExtMic` with `MikeyDriverRequired` false.

"Mikey" is Apple's name for its headset detection and remote-button logic.
The archive's `AppleMikeyDriver` is the headset-remote path over I2C/SMBus
(all 194 of its matching strings are `AppleMikeyI2C*`). Neither `JackConfig` value
appears in the vendored sequence. So macOS may decide "headset" from the Mikey
logic after a delay, and not from the pin's presence bit. Whether the pin's
presence bit sees the fourth contact at all is not known.

## The probe that decides it

It reads the codec state three times: jack empty, headset in, and, if there
are any, headphones without a microphone in. It needs root, and its only
write is the coefficient index, which it saves and restores. A silent
playback keeps the codec awake between the readings, so a runtime suspend
cannot reset the pin in between. In fish on the test machine, in the checkout, with no
call and no recording running:

```
aplay -D hw:0,0 -q -f S16_LE -r 44100 -c 4 -t raw /dev/zero &
set apid $last_pid
sudo ./tools/macbook91-codec-state capture /tmp/hs-0-empty.json
# plug in the four-pole headset, wait five seconds
sudo ./tools/macbook91-codec-state capture /tmp/hs-1-headset.json
# unplug it; plug in headphones without a microphone, wait five seconds
sudo ./tools/macbook91-codec-state capture /tmp/hs-2-headphones.json
kill $apid
./tools/macbook91-codec-state diff /tmp/hs-0-empty.json /tmp/hs-1-headset.json
./tools/macbook91-codec-state diff /tmp/hs-0-empty.json /tmp/hs-2-headphones.json
```

If `aplay` reports the device busy, close the programs that use audio and
start again. The line that answers the question is node `0x18`, field
`pin_sense_volatile`: bit 31 (`0x80000000`) set means the pin reports
presence. The files hold codec registers only.

## What each result means

| `0x18` presence bit | meaning | next step |
| --- | --- | --- |
| set with the headset, clear when empty and with plain headphones | the pin sees the headset; Linux misses it because nothing reads the pin again after the replay, and the replay removes the bias | a driver change: after the headphone replay, read the pin; if present, give it D0 and pin control `0x24` and report the jack, so the generic parser switches to it; then a hardware gate |
| clear in every case | the pin does not see the fourth contact | detection needs the Mikey path, or a manual choice of the headset microphone; both are separate investigations |
| set with the headset and with plain headphones | the bit reports any plug, not a microphone | as in the row above |

A probe that writes the pin (bias on, D0, then read the presence) would
separate a pin that senses only with bias from one that never senses. It is
not prepared: it needs a tool that sends codec verbs (`hda-verb` from
`alsa-tools` is not installed) and the maintainer's decision.

## Not covered

The headset's buttons (play, volume): they are Mikey's, and nothing here
looks at them.
