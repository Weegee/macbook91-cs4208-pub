/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * MacBook9,1 (A1534) speaker/headphone PCM layer for the CS4208.
 *
 * This is a fresh implementation, not the bundled snapshot's PCM layer. The
 * reasons are recorded in docs/AUDIT-BUNDLED-DRIVER.md round 2 (findings
 * F11-F16); the short version is that the snapshot kept per-codec stream state
 * in module-global variables without locking, mutated the shared hda_pcm_stream
 * from .open, copied a private kernel struct out of a .c file, leaked on
 * remove, and bound the PCM to converter 0x04 - which its own bring-up trace
 * powers down.
 *
 * Routing, established in docs/ROOT-CAUSE.md §4 from the codec's connection
 * lists and from the bring-up trace's own format words:
 *
 *   speakers   converter 0x0a -> pin 0x1d   4 ch, 44.1 kHz, 16-bit (fmt 0x4013)
 *   headphones converter 0x02 -> pin 0x10   2 ch, 44.1 kHz, 16-bit (fmt 0x4011)
 *
 * Converter 0x0a is digital and 8-channel, which is why the generic parser
 * cannot bind an analog PCM to it and why this custom PCM has to exist at all.
 * The four channels correspond to the four TAS5758L TDM amplifiers described in
 * docs/HARDWARE-PATH.md §3.
 *
 * Everything here is reached only when cs_spec.is_a1534 is set.
 */

#ifndef CS420X_A1534_PCM_H
#define CS420X_A1534_PCM_H

#define A1534_SPEAKER_DAC	0x0a
#define A1534_SPEAKER_PIN	0x1d
#define A1534_HP_DAC		0x02
#define A1534_HP_PIN		0x10

/*
 * GPIO regime the bring-up sequence ends with.
 *
 * mask 0x37 enables GPIO 0,1,2,4,5; dir 0x31 makes 0,4,5 outputs; data bit 0
 * is the speaker EAPD that cs_automute() toggles, and bits 4/5 low hold the
 * amplifier supply FETs on. Mainline's cs4208_fixup_gpio0() would otherwise
 * narrow the mask to bit 0 and switch the amplifiers off, which is what kept
 * the speakers silent in the first test build.
 */
#define A1534_PIN1D_CFG_BRINGUP		0x90100110u

#define A1534_GPIO_MASK		0x37
#define A1534_GPIO_DIR		0x31
#define A1534_GPIO_DATA_SPEAKER	0x01

/*
 * Per-codec live-stream state.
 *
 * The jack handler has to re-point a *running* stream when headphones are
 * plugged or unplugged, so it needs the current stream tag and format. The
 * bundled snapshot kept these in file-scope statics shared by the whole module
 * and touched them from both the PCM path and the unsolicited-event path with
 * no locking (F11). Here they are per codec and every access holds a1534_lock.
 */
/* struct a1534_state is declared next to struct cs_spec in cs420x.c, which
 * needs it by value. Its fields and their contract:
 *   lock        serialises jack changes against prepare/cleanup
 *   stream_tag  0 when no stream is running
 *   format      the format the PCM actually negotiated
 *   hp          last observed HP jack state, -1 = unknown
 */

/* Which converter should carry audio right now. Caller holds the lock. */
static hda_nid_t a1534_active_dac(struct a1534_state *st)
{
	return st->hp > 0 ? A1534_HP_DAC : A1534_SPEAKER_DAC;
}

/*
 * Point the speaker pin at its only source and enable or mute it.
 *
 * Pin 0x1d's connection list has exactly one entry (0x0a), so the select is
 * index 0. 0x40 is PIN_OUT; 0x00 mutes the pin without disturbing the
 * converter, which is how the headphone path silences the speakers.
 */
static void a1534_speaker_pin(struct hda_codec *codec, bool on)
{
	snd_hda_codec_write(codec, A1534_SPEAKER_PIN, 0,
			    AC_VERB_SET_CONNECT_SEL, 0);
	snd_hda_codec_write(codec, A1534_SPEAKER_PIN, 0,
			    AC_VERB_SET_PIN_WIDGET_CONTROL, on ? PIN_OUT : 0);
}

/*
 * Pin 0x1d's configuration default once the bring-up has run. The firmware
 * value is 0x901600f0 and nothing in the trace writes this register, so the
 * change is a side effect of the vendor-coefficient work on NID 0x24. Reading
 * it back is a cheap, self-validating test of whether the A1534 configuration
 * still stands - unlike the PM event code an earlier build relied on.
 */
static unsigned int a1534_pin1d_cfg(struct hda_codec *codec)
{
	return snd_hda_codec_read(codec, A1534_SPEAKER_PIN, 0,
				  AC_VERB_GET_CONFIG_DEFAULT, 0);
}

/*
 * The HDA stream format word carries the channel count in bits 3:0 as
 * (channels - 1). The speaker converter 0x0a drives four TDM slots, one per
 * TAS5758L amplifier, so the PCM runs at four channels; the headphone
 * converter 0x02 is stereo and takes the first two slots of that same stream.
 * Rewriting just the channel nibble keeps rate and bit depth exactly as the
 * PCM negotiated them - we never substitute a hardcoded format.
 */
static unsigned int a1534_format_for(hda_nid_t dac, unsigned int format)
{
	if (dac == A1534_HP_DAC)
		return (format & ~0xfu) | 1u;	/* two channels */
	return format;
}

/*
 * Tell the converter how many channels it is carrying.
 *
 * This is a register of its own, separate from the stream format, and it is
 * what silences the speakers after every resume. Measured either side of one
 * deep suspend with the speakers confirmed audible before and silent after,
 * across 722 capability-validated fields, it is the ONLY functional field in
 * the entire codec that moves:
 *
 *     converter 0x0a  cvt_chan_count   0x03 -> 0x00
 *
 * That capture read every amplifier gain/mute field as the input amplifier,
 * right channel, index 0 - a defect of the capture tool, found 2026-10-15 -
 * so amplifier output state was not part of the comparison.
 *
 * The register holds channels - 1 (sound/hda/core/hdmi_chmap.c:199-210), so
 * firmware programs four and a suspend leaves one. The format word still
 * reads 0x4013 - four channels, 44.1 kHz, 16 bit - so everything that looks
 * at the format sees a correct four-channel stream while the converter emits
 * a single channel into a TDM frame the four amplifiers read as four slots.
 *
 * Nothing in Linux restores it. sound/hda/core/regmap.c:132 deliberately
 * keeps AC_VERB_GET_CVT_CHAN_COUNT out of the writeable set - "basically
 * writable, but disabled for reducing unnecessary writes at sync", commented
 * "managed in HDMI CA code" - so snd_hda_regmap_sync() never replays it, and
 * this codec has no HDMI CA code to manage it. The vendored macOS verb trace
 * never writes it either; it only ever observed a machine firmware had
 * already set up.
 *
 * Programmed here from the format the PCM actually negotiated rather than
 * from a constant, and only on a converter that has the field: headphone
 * converter 0x02 reports no AC_WCAP_CHAN_CNT_EXT, which is precisely why
 * headphones kept working after every resume while the speakers did not.
 */
static void a1534_set_chan_count(struct hda_codec *codec, hda_nid_t dac,
				 unsigned int format)
{
	unsigned int chans = (format & 0xf) + 1;
	unsigned int caps = get_wcaps(codec, dac);

	if (!(caps & AC_WCAP_CHAN_CNT_EXT))
		return;

	snd_hda_codec_write(codec, dac, 0, AC_VERB_SET_CVT_CHAN_COUNT,
			    chans - 1);
}

/*
 * Move the running stream onto `dac`, and mark the other one inactive.
 *
 * The cleanup of the converter we are leaving is sticky
 * (__snd_hda_codec_cleanup_stream() without do_now): the core only marks it
 * inactive, and the hardware keeps its stream tag until the next prepare
 * purifies it (purify_inactive_streams()). Until then the converter left
 * behind still receives the stream; behind it is the jack that was just
 * unplugged, or the speaker pin a1534_speaker_pin() has just switched off.
 * Measured by the runner's jackstream on 2026-10-06: after the
 * unplug, converter 0x02 still carried stream tag 1.
 *
 * Caller holds the lock.
 */
static void a1534_route_stream(struct hda_codec *codec, struct a1534_state *st,
			       hda_nid_t dac)
{
	hda_nid_t other = (dac == A1534_SPEAKER_DAC) ? A1534_HP_DAC
						     : A1534_SPEAKER_DAC;
	unsigned int fmt;

	snd_hda_codec_cleanup_stream(codec, other);

	if (!st->stream_tag)
		return;

	/*
	 * Use the format the PCM actually negotiated, never a hardcoded one:
	 * the bring-up trace's 0x4013 / 0x4011 describe what macOS happened to
	 * play, not what this stream is.
	 */
	fmt = a1534_format_for(dac, st->format);
	a1534_set_chan_count(codec, dac, fmt);
	snd_hda_codec_setup_stream(codec, dac, st->stream_tag, 0, fmt);
}

/* --- PCM ops ----------------------------------------------------------- */

/*
 * .open deliberately does no hardware switching.
 *
 * The bundled snapshot ran the whole bring-up trace here and rewrote the shared
 * hda_pcm_stream's nid (F12). Both are avoided: the converter is chosen at
 * prepare time from the jack state, and .open only records that state so the
 * jack handler and the PCM agree.
 */
static int a1534_playback_open(struct hda_pcm_stream *hinfo,
			       struct hda_codec *codec,
			       struct snd_pcm_substream *substream)
{
	struct cs_spec *spec = codec->spec;
	struct a1534_state *st = &spec->a1534;
	int hp;

	hp = snd_hda_jack_detect(codec, A1534_HP_PIN);
	mutex_lock(&st->lock);
	st->hp = hp;
	mutex_unlock(&st->lock);
	return 0;
}

static int a1534_playback_prepare(struct hda_pcm_stream *hinfo,
				  struct hda_codec *codec,
				  unsigned int stream_tag, unsigned int format,
				  struct snd_pcm_substream *substream)
{
	struct cs_spec *spec = codec->spec;
	struct a1534_state *st = &spec->a1534;
	hda_nid_t dac;
	int hp;

	/* PM reference before the lock - see a1534_hp_jack_callback(). */
	snd_hda_power_up_pm(codec);
	hp = snd_hda_jack_detect(codec, A1534_HP_PIN);

	mutex_lock(&st->lock);
	st->stream_tag = stream_tag;
	st->format = format;
	st->hp = hp;
	dac = a1534_active_dac(st);

	a1534_speaker_pin(codec, dac == A1534_SPEAKER_DAC);
	a1534_route_stream(codec, st, dac);
	mutex_unlock(&st->lock);

	snd_hda_power_down_pm(codec);
	return 0;
}

static int a1534_playback_cleanup(struct hda_pcm_stream *hinfo,
				  struct hda_codec *codec,
				  struct snd_pcm_substream *substream)
{
	struct cs_spec *spec = codec->spec;
	struct a1534_state *st = &spec->a1534;

	snd_hda_power_up_pm(codec);
	mutex_lock(&st->lock);
	st->stream_tag = 0;
	st->format = 0;
	snd_hda_codec_cleanup_stream(codec, A1534_SPEAKER_DAC);
	snd_hda_codec_cleanup_stream(codec, A1534_HP_DAC);
	mutex_unlock(&st->lock);
	snd_hda_power_down_pm(codec);
	return 0;
}

/*
 * Capabilities are queried from converter 0x0a rather than hardcoded, so the
 * PCM can never advertise something the hardware does not support. The bundled
 * snapshot hardcoded 44.1 kHz / S16 / 4 ch and attached them to converter 0x04,
 * which the hardware reports as stereo (F15).
 *
 * channels_max stays at 4: that is what the bring-up trace programs (fmt
 * 0x4013) and what the four TAS5758L TDM amplifiers expect. It is NOT raised to
 * the 8 the converter advertises, because the physical meaning of the remaining
 * slots is unproven - see docs/HARDWARE-PATH.md §4.
 */
static const struct hda_pcm_stream a1534_pcm_playback = {
	.substreams = 1,
	/*
	 * Four channels, fixed.
	 *
	 * Measured on the test machine: a 4-channel tone played straight to this device is
	 * audible on the internal speakers, and the macOS bring-up programs
	 * converter 0x0a with format 0x4013, which is also four channels. The
	 * four TAS5758L amplifiers occupy four TDM slots, so a 2-channel frame
	 * does not carry the slots they read.
	 *
	 * channels_min was 2, which let PipeWire settle on an "Analog Stereo"
	 * profile and leave the speakers silent. Pinning both ends to 4 is what
	 * makes the normal desktop path reach the amplifiers. Headphones still
	 * work: a1534_format_for() gives converter 0x02 a 2-channel format over
	 * the first two slots of the same stream.
	 *
	 * No channel map is asserted. Which physical speaker each TDM slot
	 * drives is still unproven (docs/HARDWARE-PATH.md §4), so the generic
	 * layout stands until it is measured.
	 */
	.channels_min = 4,
	.channels_max = 4,
	/*
	 * 44.1 kHz only.
	 *
	 * Measured on the test machine: the same 440 Hz tone played straight to this device
	 * is clean at 44100 Hz and audibly distorted at 48000 Hz. The codec
	 * advertises both rates for converter 0x0a, but the four TAS5758L
	 * amplifiers are clocked from the codec (AppleHDA layouts 121/127/129:
	 * SRMultiple = 64) and only track the rate the macOS bring-up
	 * programs - format 0x4013, which is 44.1 kHz.
	 *
	 * Leaving 48 kHz advertised let PipeWire run the sink at its default
	 * 48 kHz, which is why every desktop sound was distorted while the
	 * 44.1 kHz probe tone was clean. Restricting the rate here makes
	 * userspace resample instead, which is correct and cheap.
	 *
	 * Leaving formats unset was the same mistake one level down.
	 * set_pcm_default_values() then filled them from the converter, which
	 * advertises 16, 20 and 24 bit, so the PCM offered S16_LE and S32_LE.
	 *
	 * Measured on the test machine, working state versus after a resume:
	 *
	 *     converter 0x0a stream_format  0x4013  ->  0x4033
	 *
	 * 0x4013 is 44.1 kHz / 16 bit / 4 ch; 0x4033 is the same but 24 bit.
	 * PipeWire picked S16_LE at cold boot and S32_LE when it renegotiated
	 * after a resume, and the speakers went silent at exactly that point.
	 *
	 * They have to be 16 bit. The amplifiers sit on a TDM frame of
	 * SRMultiple = 64 bit clocks (AppleHDA layouts 121/127/129), which is
	 * exactly four slots of sixteen bits. A 24-bit sample does not fit that
	 * frame, so the slots the amplifiers read carry nothing usable.
	 *
	 * This is why "silent after resume" looked like lost state for so long:
	 * the state really was lost, but what actually silenced the speakers was
	 * the stream width changing underneath.
	 */
	.rates = SNDRV_PCM_RATE_44100,
	.formats = SNDRV_PCM_FMTBIT_S16_LE,
	.maxbps = 16,
	.nid = A1534_SPEAKER_DAC,
	.ops = {
		.open = a1534_playback_open,
		.prepare = a1534_playback_prepare,
		.cleanup = a1534_playback_cleanup,
	},
};

/* --- capture converter resync ------------------------------------------- */

/*
 * Re-program the capture converter in use, past the core's converter cache.
 *
 * headphones_a1534() replays the macOS bring-up, which takes the audio
 * function group to D3 and back eight times (tests/run-tests.sh, section 7e).
 * Measured on the test machine (docs/INCIDENT-20261019.md): after a headphone
 * plug, the running capture's converter 0x06 read stream=0 and the capture
 * stopped. snd_hda_codec_setup_stream() writes a converter only when the
 * stream tag or format it cached differ, so every later capture that got the
 * same tag stayed silent too, until the codec runtime-suspended and the cache
 * was dropped.
 *
 * A do_now cleanup writes zero and forgets the cached values; the setup that
 * follows then writes the stream tag and format for real. The generic parser
 * swaps ADCs under a running stream the same way (dyn_adc_pcm_resetup()).
 *
 * cur_adc is recorded by the dynamic-ADC capture path, which this codec takes
 * because its two ADCs reach different inputs; it is 0 while no capture is
 * prepared, and then there is nothing to re-program.
 *
 * Caller holds codec->bus->prepare_mutex: capture prepare and cleanup, the
 * only writers of cur_adc and its stream parameters, run under it.
 */
static void a1534_capture_resync(struct hda_codec *codec)
{
	struct cs_spec *spec = codec->spec;
	hda_nid_t adc = spec->gen.cur_adc;

	lockdep_assert_held(&codec->bus->prepare_mutex);
	if (!spec->gen.dyn_adc_switch || !adc)
		return;

	__snd_hda_codec_cleanup_stream(codec, adc, 1);
	snd_hda_codec_setup_stream(codec, adc, spec->gen.cur_adc_stream_tag, 0,
				   spec->gen.cur_adc_format);
}

/*
 * A capture prepared after a plug usually gets the stream tag of the one
 * before it, so the core would skip the converter write the replay undid.
 * Runs from snd_hda_codec_prepare(), which holds prepare_mutex.
 */
static void a1534_capture_hook(struct hda_pcm_stream *hinfo,
			       struct hda_codec *codec,
			       struct snd_pcm_substream *substream,
			       int action)
{
	if (action == HDA_GEN_PCM_ACT_PREPARE)
		a1534_capture_resync(codec);
}

/* --- jack handling ------------------------------------------------------ */

static int setup_a1534(struct hda_codec *codec);
static int play_a1534(struct hda_codec *codec);
static int headphones_a1534(struct hda_codec *codec);

/*
 * Speaker <-> headphone switching for a stream that is already running.
 *
 * The bring-up helpers are replayed because they are what powers the amplifier
 * path up or down; the stream is then re-pointed with the format the PCM really
 * negotiated. The lock is what keeps this from racing a concurrent
 * prepare/cleanup - the serialisation the project's audio plan asks for.
 */
static void a1534_hp_jack_callback(struct hda_codec *codec,
				   struct hda_jack_callback *cb)
{
	struct cs_spec *spec = codec->spec;
	struct a1534_state *st = &spec->a1534;
	int hp;

	/*
	 * Hold a runtime-PM reference across the whole sequence, and take it
	 * BEFORE st->lock.
	 *
	 * The bring-up helpers issue ~1700 verb operations. If the codec has
	 * runtime-suspended, the first snd_hda_codec_read() inside them calls
	 * snd_hdac_power_up_pm() -> pm_runtime_get_sync() -> rpm_resume, which
	 * invokes .resume -> a1534_init(). The first test build held st->lock
	 * while doing exactly that, so the resume blocked on the lock this
	 * callback held while it waited for the resume: an AB-BA deadlock that
	 * wedged the codec permanently (tests/test_lock_discipline.py).
	 *
	 * Powering up first means no nested resume can occur; taking the
	 * reference before the lock means we never block on PM while holding
	 * it.
	 */
	snd_hda_power_up_pm(codec);

	hp = snd_hda_jack_detect(codec, A1534_HP_PIN);

	mutex_lock(&st->lock);
	if (hp == st->hp) {
		mutex_unlock(&st->lock);
		goto out;
	}
	st->hp = hp;
	mutex_unlock(&st->lock);

	/*
	 * The verb replay below runs with the lock DROPPED: it takes several
	 * milliseconds and must not block a concurrent prepare or cleanup.
	 * Nothing that mutates pin or stream routing may live here - every such
	 * write happens in the locked region that follows, re-validated against
	 * the jack state this callback sampled.
	 */
	if (hp)
		headphones_a1534(codec);
	else
		play_a1534(codec);

	mutex_lock(&st->lock);
	/*
	 * Re-check under the lock: a prepare or cleanup may have run while the
	 * sequence was replaying. The speaker pin follows jack validity alone,
	 * because a jack change with no stream running must still mute the
	 * speakers.
	 *
	 * Both converters are cleaned up do_now first. The replay writes
	 * SET_CHANNEL_STREAMID 0x10 (stream tag 1) and a stream format to
	 * converters 0x02 and 0x0a behind the core's back
	 * (vendored/a1534_sequence.h), and snd_hda_codec_setup_stream() writes
	 * only what differs from the values it cached. Without the cleanup a
	 * converter with no stream keeps listening to tag 1, which belongs to
	 * another stream (HDMI's, say) whenever that one holds it, and a stream
	 * whose tag and format did not change is never written back. The
	 * cleanup writes zero and forgets the cached values, as
	 * a1534_capture_resync() does for the capture converter.
	 *
	 * A prepared stream is then re-pointed to the converter of the current
	 * jack state, a1534_active_dac(): the state this callback sampled, or a
	 * newer one that a prepare sampled while the replay ran. That prepare
	 * set its stream up before the replay could overwrite it, so it is
	 * re-pointed too.
	 *
	 * Known limitation, not an oversight: st->hp carries two meanings - the
	 * jack state the PCM last sampled (written by .open, .prepare and
	 * a1534_init) and the jack state the bring-up sequence has been replayed
	 * for (written above). If a prepare advances st->hp while the replay is
	 * running, the dedup at the top of this function makes the next callback
	 * for that plug return early, so the matching sequence replay is skipped.
	 * Whether the headphone path degrades without it is not established by
	 * any measurement in this repository; separating the two meanings needs a
	 * second field in struct a1534_state, which lives in local-changes.patch.
	 */
	__snd_hda_codec_cleanup_stream(codec, A1534_SPEAKER_DAC, 1);
	__snd_hda_codec_cleanup_stream(codec, A1534_HP_DAC, 1);
	if (st->hp == hp)
		a1534_speaker_pin(codec, !hp);
	if (st->stream_tag)
		a1534_route_stream(codec, st, a1534_active_dac(st));
	mutex_unlock(&st->lock);

	/*
	 * The replay may have reset the running capture's converter (see
	 * a1534_capture_resync()). prepare_mutex is taken here, after st->lock
	 * is dropped and never inside it: snd_hda_codec_prepare() holds
	 * prepare_mutex when it calls a1534_playback_prepare(), which then takes
	 * st->lock, so the other order would deadlock.
	 */
	mutex_lock(&codec->bus->prepare_mutex);
	a1534_capture_resync(codec);
	mutex_unlock(&codec->bus->prepare_mutex);
out:
	snd_hda_power_down_pm(codec);
}

/* --- codec ops, reached only when spec->is_a1534 ------------------------ */

/*
 * Override only the analog playback stream. snd_hda_gen_build_pcms() still runs
 * first, so capture (internal and external mic) and any digital streams keep
 * the standard generic handling; capture only gains a1534_capture_hook(), which
 * re-programs the capture converter on every prepare.
 */
static int a1534_build_pcms(struct hda_codec *codec)
{
	struct cs_spec *spec = codec->spec;
	struct hda_pcm *info;
	int err;

	err = snd_hda_gen_build_pcms(codec);
	if (err < 0)
		return err;

	info = spec->gen.pcm_rec[0];
	if (!info)
		return -ENODEV;

	info->stream[SNDRV_PCM_STREAM_PLAYBACK] = a1534_pcm_playback;
	info->pcm_type = HDA_PCM_TYPE_AUDIO;
	spec->gen.pcm_capture_hook = a1534_capture_hook;
	return 0;
}

static int a1534_init(struct hda_codec *codec)
{
	struct cs_spec *spec = codec->spec;
	struct a1534_state *st = &spec->a1534;
	struct hda_jack_callback *cb;
	int err;

	int hp;

	err = cs_init(codec);
	if (err < 0)
		return err;

	/* Codec I/O first, with no lock held: this runs from probe and from
	 * the resume path and must never block on PM while holding st->lock. */
	hp = snd_hda_jack_detect(codec, A1534_HP_PIN);
	a1534_speaker_pin(codec, hp <= 0);

	mutex_lock(&st->lock);
	st->hp = hp;
	mutex_unlock(&st->lock);

	/*
	 * Idempotent: the core keeps one callback per function per pin.
	 * snd_hda_jack_detect_enable_callback_mst() looks the callback up by
	 * function pointer (find_callback_from_list()) before appending, so
	 * calling this again on every resume does not grow the callback list.
	 * (sound/hda/common/jack.c:296-306,335,
	 * in linux 7.2.4)
	 */
	cb = snd_hda_jack_detect_enable_callback(codec, A1534_HP_PIN,
						 a1534_hp_jack_callback);
	/*
	 * An ERR_PTR (out of memory) means output will not follow the jack.
	 * Say so rather than lose it silently; it is not fatal, because this
	 * also runs on resume and the speakers work without the callback.
	 */
	if (IS_ERR(cb))
		codec_warn(codec, "A1534: no headphone jack callback (%ld); output will not follow the jack\n",
			   PTR_ERR(cb));
	return 0;
}

/*
 * The amplifiers behind vendor widget 0x24 lose their configuration across a
 * system sleep, so the bring-up has to be replayed.
 *
 * It is replayed on every resume, runtime resumes included. The driver's
 * .suspend callback (cs_suspend(), added by local-changes.patch) clears
 * bringup_valid, and the core reaches that callback on every D3 transition,
 * not only on system sleep: hda_codec_runtime_suspend() ->
 * hda_call_codec_suspend() -> driver->ops->suspend
 * (linux 7.2.4 codec.c:2909, :2861-2868), and the same
 * helper serves the system-sleep path. So bringup_valid is always 0 by the
 * time a1534_resume() runs, and the "configuration intact" branch below
 * always takes the replay. There is no runtime fast path here, and an earlier
 * version of this comment claiming one described an optimisation the code
 * does not implement.
 *
 * That is conservative by choice. The cost is unmeasured latency on each
 * runtime resume; the alternative - letting the pin 0x1d marker decide
 * whether the replay can be skipped - risks silent speakers after every idle
 * wake, which is a core-function regression traded for an unmeasured win. It
 * stays deferred until the replay cost is measured and a maintainer-run
 * suspend/idle gate is available.
 */
/*
 * Deep sleep resets this codec: after a resume, pin 0x1d's configuration
 * default reads back as the BIOS value again and the speakers are silent
 * because nothing has re-run the amplifier bring-up.
 *
 * An earlier build gated the replay on
 * `codec->core.dev.power.power_state.event != PM_EVENT_ON`. That is not
 * reliable: power_state is only touched by the system-sleep callbacks, and the
 * core resets it to PMSG_ON at the end of every resume, so depending on
 * whether the codec was already runtime-suspended when the machine slept the
 * replay could be skipped exactly when it was needed. On the test machine it was: the
 * kernel log showed `PM: suspend exit` with no codec activity after it at all.
 *
 * The flag is set when the bring-up succeeds and cleared by the driver's
 * .suspend callback, so it states plainly whether the configuration still
 * stands, with no dependence on PM event codes. Because that callback fires
 * on runtime suspends too, the flag is in practice always 0 at resume; it is
 * kept rather than deleted because two tests in tests/run-tests.sh ("bring-up
 * validity is cleared on suspend and replayed on resume", "driver hooks
 * .suspend to invalidate the bring-up") assert that it and .suspend =
 * cs_suspend both exist, and those assertions are what keep
 * that PM-event gating from coming back.
 */
static int a1534_resume(struct hda_codec *codec)
{
	struct cs_spec *spec = codec->spec;
	unsigned int cfg;
	int err;

	cfg = a1534_pin1d_cfg(codec);

	if (cfg != A1534_PIN1D_CFG_BRINGUP) {
		/*
		 * A deep sleep resets this codec and loses state the firmware
		 * established at power-on - state this driver never wrote and
		 * the macOS trace only ever read (vendored/a1534_sequence.h
		 * line 1046 reads pin 0x1d as 0x90100110 and writes no
		 * configuration default at all).
		 *
		 * Measured on the test machine, in this order: replaying the bring-up does
		 * nothing; an HDA Function Reset followed by the bring-up does
		 * nothing; and a full codec re-probe through
		 * /sys/class/sound/hwC0D0/reconfig also leaves pin 0x1d at
		 * 0x901600f0 and the speakers silent. All three re-run the
		 * bring-up, and the bring-up was never what established this
		 * state, so none of them could have worked.
		 *
		 * What has not been tried is putting the firmware's own values
		 * back. a1534_snapshot_take() captured them at probe while the
		 * speakers still worked; write them back here and let the
		 * normal bring-up run on top, exactly as at cold boot.
		 *
		 * The snapshot is written back whole: nothing is compared
		 * against a live read, because a resume-path read comes from a
		 * stale cache (see a1534_snapshot.h). So the log does not name
		 * which firmware-owned registers a deep sleep destroys - it
		 * reports the summary line "A1534: restored N coefficients, N
		 * pin configs, ..." and the pin 0x1d value read below.
		 */
		if (a1534_restore && spec->a1534_snap.valid) {
			int rc = a1534_snapshot_restore(codec, &spec->a1534_snap);

			if (rc < 0) {
				codec_warn(codec, "A1534: firmware state restore failed: %d\n", rc);
			} else {
				cfg = a1534_pin1d_cfg(codec);
				codec_info(codec,
					   "A1534: pin 0x1d after restore: %08x (want %08x)\n",
					   cfg, A1534_PIN1D_CFG_BRINGUP);
			}
		}

		/*
		 * Reprogram the four TAS5758L amplifiers - a no-op unless
		 * a1534_amp=1. The transport to these chips is unproven, not
		 * disproven (see a1534_i2c.h), so this is opt-in investigation,
		 * not a fix this driver relies on. It runs regardless of
		 * whether the codec's own state was restorable, because if the
		 * amplifiers do need reprogramming, they need it either way.
		 */
		a1534_amp_bringup(codec);

		if (cfg != A1534_PIN1D_CFG_BRINGUP) {
			if (!spec->a1534.config_lost_reported) {
				codec_warn(codec,
					   "A1534: speaker configuration lost across suspend (pin 0x1d %08x, want %08x)\n",
					   cfg, A1534_PIN1D_CFG_BRINGUP);
				codec_warn(codec,
					   "A1534: internal speakers stay silent until reboot; headphones and capture are unaffected\n");
				spec->a1534.config_lost_reported = 1;
			}
		} else {
			/* The firmware state is back. Run the bring-up on top
			 * of it, the same way probe does at cold boot. */
			spec->a1534.config_lost_reported = 0;
			err = setup_a1534(codec);
			if (err < 0)
				codec_warn(codec, "A1534: setup replay failed after restore: %d\n", err);
			err = play_a1534(codec);
			if (err < 0)
				codec_warn(codec, "A1534: speaker enable failed after restore: %d\n", err);
			else
				spec->a1534.bringup_valid = 1;
		}
	} else if (!spec->a1534.bringup_valid) {
		/*
		 * Resume with the configuration intact - the codec was only in
		 * D3, not powered down. Here the bring-up does take effect, so
		 * replay it.
		 *
		 * The !bringup_valid test is not a filter in practice: .suspend
		 * clears the flag on every D3 transition, so this branch is
		 * reached on every resume that finds pin 0x1d intact. See the
		 * header comment above.
		 */
		err = setup_a1534(codec);
		if (err < 0)
			codec_warn(codec, "A1534: setup replay failed on resume: %d\n", err);
		err = play_a1534(codec);
		if (err < 0)
			codec_warn(codec, "A1534: play replay failed on resume: %d\n", err);
		else
			spec->a1534.bringup_valid = 1;
	}

	err = a1534_init(codec);
	if (err < 0)
		return err;

	snd_hda_regmap_sync(codec);
	return 0;
}

#endif /* CS420X_A1534_PCM_H */
