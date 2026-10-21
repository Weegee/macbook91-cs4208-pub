/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * MacBook9,1 (A1534) target-device gate for the CS4208 codec.
 *
 * The whole point of this header is that the decision is a *pure function* of
 * five inputs, so the kernel module and the host-side regression tests
 * (tests/test_a1534_match.c) exercise the identical code. Nothing here
 * may include kernel headers or touch global state.
 *
 * Why this gate exists at all
 * --------------------------
 * The A1534 initialisation is a machine-specific sequence. Mainline has no
 * MacBook9,1 entry, and the codec SSID alone is not sufficient proof of the
 * machine: see docs/ROOT-CAUSE.md §3 for how a bare vendor match reaches this
 * codec through snd_hda_pick_fixup()'s codec-SSID fallback even though the PCI
 * subsystem is 8086:7270. We therefore require BOTH the exact codec SSID and
 * the DMI identity before running anything machine-specific.
 *
 * Deliberately NOT part of the gate: the PCI subsystem id. On this machine it
 * is 8086:7270 (an Intel id, not an Apple one), so it carries no Apple model
 * information and must never be used to select an Apple fixup.
 */

#ifndef CS420X_A1534_MATCH_H
#define CS420X_A1534_MATCH_H

/* Codec subsystem id of the CS4208 in the 12-inch MacBook (MacBook9,1). */
#define A1534_CODEC_SSID	0x106b6500u

/*
 * The CS4208's own vendor/device id, which is what the HDA core reports as the
 * subsystem id when the real one cannot be read.
 *
 * Measured on the test machine after a PCI remove/rescan of the audio controller:
 *
 *     Vendor Id:    0x10134208
 *     Subsystem Id: 0x10134208      (was 0x106b6500 at boot)
 *
 * The subsystem id is firmware-written state, exactly like pin 0x1d's
 * configuration default, and a re-initialisation without firmware help loses
 * it. When that happened the gate stopped matching, the driver silently took
 * the generic path, and hw:0,0 became a 2-channel device - so every
 * four-channel playback failed with "channel count not supported" and was
 * misread as silence.
 *
 * Accepting this value is safe because the DMI identity is checked first and
 * pins the exact machine; this only says "the SSID is unavailable, and the
 * codec is a CS4208".
 */
#define A1534_CODEC_VENDOR_ID	0x10134208u

/* DMI identity of the target machine. */
#define A1534_DMI_VENDOR	"Apple Inc."
#define A1534_DMI_PRODUCT	"MacBook9,1"

/*
 * a1534_match() - decide whether the A1534 path may run.
 * @codec_ssid:  codec subsystem id, i.e. hda_codec.core.subsystem_id
 * @dmi_vendor:  DMI_SYS_VENDOR, or NULL when unreadable
 * @dmi_product: DMI_PRODUCT_NAME, or NULL when unreadable
 * @streq:       string comparison returning non-zero on equality
 *
 * Returns 1 only when this is genuinely a MacBook9,1 carrying a CS4208. Any
 * missing or mismatching input yields 0, so an unreadable DMI fails closed and
 * the codec keeps unmodified mainline behaviour.
 *
 * The comparison function is injected so the kernel build can pass strcmp-like
 * semantics without this header depending on a libc or on kernel string.h.
 */
static inline int a1534_match(unsigned int codec_ssid,
			      const char *dmi_vendor,
			      const char *dmi_product,
			      int (*streq)(const char *a, const char *b))
{
	/* DMI first: it is the strong identity and it never degrades. */
	if (!dmi_vendor || !dmi_product || !streq)
		return 0;
	if (!streq(dmi_vendor, A1534_DMI_VENDOR))
		return 0;
	if (!streq(dmi_product, A1534_DMI_PRODUCT))
		return 0;

	/* Then the codec: either its Apple subsystem id, or - when firmware
	 * state has been lost - the CS4208's own id reported in its place. */
	if (codec_ssid == A1534_CODEC_SSID)
		return 1;
	if (codec_ssid == A1534_CODEC_VENDOR_ID)
		return 1;
	return 0;
}

#endif /* CS420X_A1534_MATCH_H */
