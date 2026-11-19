# The deep-suspend defect and how it was found

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
