/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * MacBook9,1 (A1534): snapshot the codec state that the Mac firmware
 * establishes at power-on and that Linux does not manage, so it can be put
 * back after a deep sleep.
 *
 * Why this exists
 * ---------------
 * Measured on the test machine on 2026-09-14:
 *
 *   - At cold boot, pin 0x1d's configuration default register reads
 *     0x90100110 *before* this driver runs a single verb. The proc pin table,
 *     which the HDA core snapshots earlier still, reads 0x901600f0 - the
 *     codec's own reset value. Something between codec reset and this driver
 *     writes that register, and it is not Linux.
 *   - After an S3 resume the same register reads 0x901600f0 and the internal
 *     speakers are silent. Headphones and capture are unaffected.
 *   - Replaying the bring-up, resetting the function group first, and a full
 *     re-probe through /sys/class/sound/hwC0D0/reconfig all leave it at
 *     0x901600f0. None of them restores sound.
 *
 * The macOS verb trace in vendored/a1534_sequence.h *reads* 0x90100110 from
 * pin 0x1d (line 1046) and never writes it, nor any other configuration
 * default - all 19 of its config-default operations are reads. So macOS did
 * not establish that state either: the firmware did, at power-on, and the
 * trace merely observed it. That is why nothing which replays the trace can
 * bring it back.
 *
 * What this file does
 * -------------------
 * Registers on this codec fall into two groups:
 *
 *   managed by Linux   pin widget control, amp gains, converter format and
 *                      stream id, power states, GPIO - all restored by the
 *                      HDA core's regmap sync and by cs_init().
 *   managed by nobody  the 128 vendor coefficients behind widget 0x24.
 *
 * The second group is exactly the state that survives from firmware into a
 * working Linux session and is lost across S3. This file captures it while
 * the speakers work and writes it back when they do not.
 *
 * Configuration defaults ARE restored. An earlier version of this project
 * believed restoring them was a design error, because a resume once left the
 * microphone pins (0x15, 0x16, 0x1a-0x1c) reading 0x400000f0 - "not present".
 * The full read-only dump later settled this: in the WORKING state those same
 * pins really do read 0x400000f0 while the microphone works, so the captured
 * configuration was correct all along - it was a saved ALSA mixer state, not
 * this restore, that had muted capture. See the test "snapshot restores the
 * captured pin configuration defaults" in tests/run-tests.sh.
 *
 * Scope is otherwise limited to the unmanaged group. Restoring registers the
 * HDA core also drives would fight the core rather than help it.
 *
 * Risk envelope: the restore path only ever runs in a state that is already
 * broken - pin 0x1d has reverted and the speakers are already silent - and
 * only writes values this same codec reported in a working configuration on
 * this same boot. The cold-boot path is untouched.
 */

#ifndef A1534_SNAPSHOT_H
#define A1534_SNAPSHOT_H

/*
 * Vendor-private registers on widget 0x24 that Apple restores by hand after a
 * power-rail loss.
 *
 * AppleHDAWidgetCS4208::performPowerRailRestore() re-issues exactly three
 * verbs, and only for node 0x24: 0x708 (unsolicited enable), 0x7f0 and 0x7f1.
 * Its counterpart is AppleHDAFunctionGroupCS4208::performPowerRailSave().
 *
 * That is Apple stating, in its own driver, which codec state does not survive
 * the rail dropping. 0x7f0 and 0x7f1 are vendor-private - they are not
 * coefficients, and the HDA core's regmap has no idea they exist, so nothing
 * in Linux has ever saved or restored them. The vendored sequence writes
 * 0x7f0 on this same widget (values 0x00 and 0xae), which corroborates that
 * they carry real configuration.
 *
 * GET counterparts follow the usual HDA convention, SET | 0x800.
 */
/* The speaker converter. a1534_pcm.h names it A1534_SPEAKER_DAC, but that
 * header is included after this one. */
#define A1534_SNAP_SPEAKER_DAC	0x0a

#define A1534_VERB_SET_UNSOL	0x708
#define A1534_VERB_GET_UNSOL	0xf08
#define A1534_VERB_SET_VP0	0x7f0
#define A1534_VERB_GET_VP0	0xff0
#define A1534_VERB_SET_VP1	0x7f1
#define A1534_VERB_GET_VP1	0xff1

/* A1534_NCOEF and struct a1534_snapshot are
 * declared in cs420x.c, which needs the struct by value inside struct
 * cs_spec - the same arrangement as struct a1534_state. */

static bool a1534_restore = true;
module_param(a1534_restore, bool, 0644);
MODULE_PARM_DESC(a1534_restore,
		 "MacBook9,1: restore firmware codec state after a deep sleep (default on)");

/*
 * Read the whole unmanaged register set.
 *
 * Called at probe entry, before setup_a1534() has issued anything, so what it
 * captures is firmware state and nothing else.
 */
static void a1534_snapshot_take(struct hda_codec *codec,
				struct a1534_snapshot *snap)
{
	unsigned int i;

	for (i = 0; i < A1534_NCOEF; i++)
		snap->coef[i] = cs_vendor_coef_get(codec, i);

	for (i = 0; i < A1534_NPIN; i++)
		snap->pincfg[i] = snd_hda_codec_read(codec, A1534_PIN_FIRST + i, 0,
						     AC_VERB_GET_CONFIG_DEFAULT, 0);

	snap->digi = snd_hda_codec_read(codec, A1534_SNAP_SPEAKER_DAC, 0,
					AC_VERB_GET_DIGI_CONVERT_1, 0);

	snap->cvt_chan_count = snd_hda_codec_read(codec, A1534_SNAP_SPEAKER_DAC, 0,
						  AC_VERB_GET_CVT_CHAN_COUNT, 0);

	snap->proc_state = snd_hda_codec_read(codec, CS4208_VENDOR_NID, 0,
					      AC_VERB_GET_PROC_STATE, 0);

	snap->unsol = snd_hda_codec_read(codec, CS4208_VENDOR_NID, 0,
					 A1534_VERB_GET_UNSOL, 0);
	snap->vp0 = snd_hda_codec_read(codec, CS4208_VENDOR_NID, 0,
				       A1534_VERB_GET_VP0, 0);
	snap->vp1 = snd_hda_codec_read(codec, CS4208_VENDOR_NID, 0,
				       A1534_VERB_GET_VP1, 0);
	snap->valid = 1;
}

/*
 * Log the captured coefficient space once per boot.
 *
 * This is the firmware-programmed state of a machine whose speakers work.
 * Nothing in the evidence archive contains it - the AppleHDA binaries hold no
 * amplifier or TDM programming at all (docs/HARDWARE-PATH.md §5.2, re-checked
 * against the Mach-O files themselves) - so capturing it here is the only
 * record of what the firmware actually did.
 */
static void a1534_snapshot_log(struct hda_codec *codec,
			       const struct a1534_snapshot *snap)
{
	unsigned int i;

	codec_info(codec,
		   "A1534: firmware state (widget %#x): proc_state %#x, unsol %#x, 0x7f0 %#x, 0x7f1 %#x\n",
		   CS4208_VENDOR_NID, snap->proc_state, snap->unsol,
		   snap->vp0, snap->vp1);
	for (i = 0; i < A1534_NCOEF; i += 8)
		codec_info(codec,
			   "A1534: coef %02x: %04x %04x %04x %04x %04x %04x %04x %04x\n",
			   i,
			   snap->coef[i],     snap->coef[i + 1],
			   snap->coef[i + 2], snap->coef[i + 3],
			   snap->coef[i + 4], snap->coef[i + 5],
			   snap->coef[i + 6], snap->coef[i + 7]);
}

/* Write one pin's configuration default. The four bytes are separate verbs. */
static void a1534_write_pincfg(struct hda_codec *codec, hda_nid_t nid,
			       unsigned int cfg)
{
	snd_hda_codec_write(codec, nid, 0,
			    AC_VERB_SET_CONFIG_DEFAULT_BYTES_0, cfg & 0xff);
	snd_hda_codec_write(codec, nid, 0,
			    AC_VERB_SET_CONFIG_DEFAULT_BYTES_1, (cfg >> 8) & 0xff);
	snd_hda_codec_write(codec, nid, 0,
			    AC_VERB_SET_CONFIG_DEFAULT_BYTES_2, (cfg >> 16) & 0xff);
	snd_hda_codec_write(codec, nid, 0,
			    AC_VERB_SET_CONFIG_DEFAULT_BYTES_3, (cfg >> 24) & 0xff);
}

/*
 * Put the firmware state back.
 *
 * The whole snapshot is written back unconditionally. No per-register
 * comparison is made and no per-register difference is logged, because a
 * resume-path read is answered from a stale regmap cache - the defect that
 * made an earlier build write garbage, spelled out in the body comment below.
 * The test "restore does not read back on the resume path" in tests/run-tests.sh
 * enforces this: it fails if any non-comment line
 * of this function reads the codec back. Do not re-add reads here. Naming the
 * registers a deep sleep destroys would need an uncached read in a separate
 * function and a justified refinement of that test; it is deferred, not
 * forgotten.
 *
 * What is logged is the summary line at the end of this function: how many
 * coefficients and pin configs were written, plus the digi, converter and
 * channel-count values.
 *
 * Returns 0 on success, negative errno on failure.
 */
static int a1534_snapshot_restore(struct hda_codec *codec,
				  const struct a1534_snapshot *snap)
{
	unsigned int i;

	if (!snap->valid)
		return -ENODATA;

	/*
	 * Write the captured state back UNCONDITIONALLY.
	 *
	 * Not "write only what differs". Comparing against a live read on the
	 * resume path is exactly what produced an earlier build's nonsense: the
	 * "current" values it read were stale, and the restore wrote garbage
	 * over correct registers. That build blamed the HDA regmap cache, but
	 * snd_hda_codec_read() does not go through it (see a1534_i2c_sync() in
	 * a1534_i2c.h), so why those reads were stale is not established. The
	 * snapshot was taken at probe, before any suspend, and is the only
	 * trustworthy source here. Re-writing a register that already holds
	 * the right value costs nothing.
	 */
	snd_hda_codec_write(codec, CS4208_VENDOR_NID, 0, AC_VERB_SET_PROC_STATE, 1);

	for (i = 0; i < A1534_NCOEF; i++)
		cs_vendor_coef_set(codec, i, snap->coef[i]);

	for (i = 0; i < A1534_NPIN; i++)
		a1534_write_pincfg(codec, A1534_PIN_FIRST + i, snap->pincfg[i]);

	/*
	 * The speaker path is a digital converter, so its digital-enable bit
	 * is not optional. Measured at 0x111 while the speakers work.
	 */
	snd_hda_codec_write(codec, A1534_SNAP_SPEAKER_DAC, 0,
			    AC_VERB_SET_DIGI_CONVERT_1, snap->digi & 0xff);

	/*
	 * Converter 0x0a's channel count.
	 *
	 * This is the register that was silencing the speakers after every
	 * resume, and it took a 722-field capability-validated capture either
	 * side of one suspend to find it, because it is the only functional
	 * field in the whole codec that moves:
	 *
	 *     0x0a cvt_chan_count   03 -> 00
	 *
	 * That capture read every amplifier gain/mute field as the input
	 * amplifier, right channel, index 0 - a defect of the capture tool,
	 * found 2026-10-15 - so amplifier output state was not compared.
	 *
	 * The value is channels - 1 (sound/hda/core/hdmi_chmap.c:199-210), so
	 * firmware programs four channels and a suspend leaves one. The stream
	 * format still says four - 0x4013 survives - but the converter emits a
	 * single channel into a TDM frame the four TAS5758L amplifiers read as
	 * four slots, so nothing usable reaches them.
	 *
	 * Nothing in Linux restores it. It is deliberately excluded from the
	 * HDA regmap's writeable set - sound/hda/core/regmap.c:132 lists it
	 * under "basically writable, but disabled for reducing unnecessary
	 * writes at sync", with the comment "managed in HDMI CA code" - so
	 * snd_hda_regmap_sync() will never replay it, and for this codec there
	 * is no HDMI CA code to manage it. The vendored macOS verb trace never
	 * touches it either: it only ever observed a machine the firmware had
	 * already set up, which is the same blind spot that hid pin 0x1d's
	 * configuration default for so long.
	 *
	 * Headphone converter 0x02 has no AC_WCAP_CHAN_CNT_EXT field at all,
	 * which is exactly why headphones kept working after every resume
	 * while the speakers did not.
	 */
	snd_hda_codec_write(codec, A1534_SNAP_SPEAKER_DAC, 0,
			    AC_VERB_SET_CVT_CHAN_COUNT,
			    snap->cvt_chan_count & 0xff);

	/*
	 * The three verbs Apple restores by hand after a power-rail loss.
	 * Written unconditionally: they have no readable "current" value worth
	 * diffing against, and re-issuing a value the widget already holds is
	 * harmless. Measured on the test machine they all read 0x0 even while the speakers
	 * work, so there is no state in them here and these writes are no-ops
	 * - kept only because Apple's own driver does them and they cost
	 * nothing. Deliberately no read-back: a resume-path read is not
	 * trustworthy.
	 */
	snd_hda_codec_write(codec, CS4208_VENDOR_NID, 0,
			    A1534_VERB_SET_UNSOL, snap->unsol & 0xff);
	snd_hda_codec_write(codec, CS4208_VENDOR_NID, 0,
			    A1534_VERB_SET_VP0, snap->vp0 & 0xff);
	snd_hda_codec_write(codec, CS4208_VENDOR_NID, 0,
			    A1534_VERB_SET_VP1, snap->vp1 & 0xff);

	codec_info(codec,
		   "A1534: restored %d coefficients, %d pin configs, digi 0x%x, converter 0x%02x channel count %u\n",
		   A1534_NCOEF, A1534_NPIN, snap->digi,
		   A1534_SNAP_SPEAKER_DAC, (snap->cvt_chan_count & 0xff) + 1);
	return 0;
}

#endif /* A1534_SNAPSHOT_H */
