/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * MacBook9,1 (A1534): the CS4208's I2C master, and the TAS5758L speaker
 * amplifier bring-up.
 *
 * The internal speakers are driven by four TI TAS5758L smart amplifiers on
 * TDM slots behind pin 0x1d. They are separate chips with their own register
 * state, reached over an I2C bus mastered by the codec itself through vendor
 * widget 0x24 - the same architecture Linux already implements for the Cirrus
 * CS8409 in patch_cs8409.c.
 *
 * Whether a deep sleep drops the amplifiers' supply or their configuration is
 * not known (docs/CLAIMS-AUDIT.md, claims D2, D3 and D6); after a resume the
 * speakers came back with the converter channel-count fix alone. Reprogramming
 * them needs the register sequence and the transport, and the vendored macOS
 * verb trace contains no amplifier programming at all, having only ever
 * observed a machine the firmware had already set up.
 *
 * Both are recorded in docs/AMPLIFIER-PROTOCOL.md, recovered from Apple's own
 * AppleHDA in the official macOS recovery image for this board id. This file
 * implements that protocol; no Apple binary is included.
 */

#ifndef A1534_I2C_H
#define A1534_I2C_H

/* Coefficient indices on vendor widget 0x24 that form the I2C master. */
#define A1534_COEF_I2C_ENABLE	0x00	/* bit 3 gates the bridge */
#define A1534_COEF_I2C_ADDR	0x14	/* 7-bit address << 1, bit 0 = read */
#define A1534_COEF_I2C_DATA	0x15
#define A1534_COEF_I2C_CTRL	0x16	/* 0x04 start, 0x02 stop */
#define A1534_COEF_I2C_STATUS	0x17

#define A1534_I2C_ENABLE_BIT	0x08
#define A1534_I2C_CTRL_START	0x04
#define A1534_I2C_CTRL_STOP	0x02

/*
 * Off by default, and the reason has changed.
 *
 * It used to claim the bus gave no response at all. That was never shown.
 * Every amplifier read in this project returned 0x0000 - and so
 * did a read from an address with nothing on it, in the same sweep, while the
 * speakers were working. A procedure that gives the same answer for a present
 * device and an absent one has not measured either of them, so "the amps do
 * not answer" was never a finding, in either direction.
 *
 * Until tools/macbook91-amp-transport shows that a read can tell those
 * two apart, writing eight registers into four amplifiers over that transport
 * is writing into the dark. Enable with a1534_amp=1 only to continue the
 * investigation, never as a fix.
 */
static bool a1534_amp;
module_param(a1534_amp, bool, 0644);
MODULE_PARM_DESC(a1534_amp,
		 "MacBook9,1: program the speaker amplifiers over the codec's I2C master (default off; unproven)");

/*
 * Open or close the bridge.
 *
 * This is `AppleHDAFunctionGroupCS4208::enableI2C(bool)` at 0x9c2dda, verb for
 * verb (docs/APPLE-I2C-AUDIT.md §3): read coefficient 0x00, toggle bit 3,
 * write it back, and when enabling write it once more with bit 3 forced set.
 *
 * It was described here as "clears bit 3 and then sets it (a pulse)". That
 * description is wrong, and it matters: the toggle only clears the bit if it
 * was already set. On this machine coefficient 0x00 reads 0x00c4 at cold
 * boot, so bit 3 is clear and enabling writes 0x00cc twice - no pulse at all.
 * Disabling is a bare toggle in Apple's code too, so calling it twice
 * re-opens the bridge. The code was right; only the comment was inventing a
 * pulse that the binary does not contain.
 */
static void a1534_i2c_enable(struct hda_codec *codec, bool enable)
{
	unsigned int v = cs_vendor_coef_get(codec, A1534_COEF_I2C_ENABLE);

	v ^= A1534_I2C_ENABLE_BIT;
	cs_vendor_coef_set(codec, A1534_COEF_I2C_ENABLE, v);

	if (enable)
		cs_vendor_coef_set(codec, A1534_COEF_I2C_ENABLE,
				   v | A1534_I2C_ENABLE_BIT);
}

/*
 * Every transaction step is followed by a status read.
 *
 * Apple reads coefficient 0x17 after each step and stores it in a stack slot
 * that no later instruction reads - in i2cWrite four times, in i2cRead six,
 * and never once examined (docs/APPLE-I2C-AUDIT.md §6). There is no ACK, NACK
 * or timeout evaluation to transcribe because Apple's driver does not have
 * any: what the read is for is reaching the hardware, not what it returns.
 *
 * So this must not be optimised away, and it must not be "improved" into a
 * completion poll on the strength of the register's name. In Linux the read
 * does reach the hardware: snd_hda_codec_read() goes through
 * snd_hdac_exec_verb() straight to the controller, with the HDA regmap cache
 * nowhere in the path.
 */
static void a1534_i2c_sync(struct hda_codec *codec)
{
	cs_vendor_coef_get(codec, A1534_COEF_I2C_STATUS);
}

static void a1534_i2c_write(struct hda_codec *codec, unsigned int addr,
			    unsigned int reg, unsigned int val)
{
	cs_vendor_coef_set(codec, A1534_COEF_I2C_ADDR, addr << 1);
	cs_vendor_coef_set(codec, A1534_COEF_I2C_CTRL, A1534_I2C_CTRL_START);
	a1534_i2c_sync(codec);
	cs_vendor_coef_set(codec, A1534_COEF_I2C_DATA, reg);
	a1534_i2c_sync(codec);
	cs_vendor_coef_set(codec, A1534_COEF_I2C_DATA, val);
	a1534_i2c_sync(codec);
	cs_vendor_coef_set(codec, A1534_COEF_I2C_CTRL, A1534_I2C_CTRL_STOP);
	a1534_i2c_sync(codec);
}

static unsigned int a1534_i2c_read(struct hda_codec *codec, unsigned int addr,
				   unsigned int reg)
{
	unsigned int val;

	cs_vendor_coef_set(codec, A1534_COEF_I2C_ADDR, addr << 1);
	cs_vendor_coef_set(codec, A1534_COEF_I2C_CTRL, A1534_I2C_CTRL_START);
	a1534_i2c_sync(codec);
	cs_vendor_coef_set(codec, A1534_COEF_I2C_DATA, reg);
	a1534_i2c_sync(codec);
	cs_vendor_coef_set(codec, A1534_COEF_I2C_ADDR, (addr << 1) | 1);
	cs_vendor_coef_set(codec, A1534_COEF_I2C_CTRL, A1534_I2C_CTRL_START);
	a1534_i2c_sync(codec);
	val = cs_vendor_coef_get(codec, A1534_COEF_I2C_DATA);
	a1534_i2c_sync(codec);
	/*
	 * STOP.
	 *
	 * This was missing. Apple's i2cRead (0x9c2f1e) ends the transaction
	 * the same way its i2cWrite does - `set(0x16, 0x02)` and one more
	 * status read - and without it the bus is left in a started state and
	 * the next transaction opens with a START that never saw a STOP.
	 *
	 * The userspace probes in tools/ DID send it, so the kernel path
	 * and the probes were not running the same protocol; that alone makes
	 * their results incomparable and is reason enough not to carry any
	 * conclusion across from one to the other.
	 */
	cs_vendor_coef_set(codec, A1534_COEF_I2C_CTRL, A1534_I2C_CTRL_STOP);
	a1534_i2c_sync(codec);

	return val;
}

/*
 * The TAS5758L bring-up, in Apple's order.
 *
 * Register 0x03 carries the amplifier's TDM slot in its low bits, so it is the
 * one entry that differs between the four chips. Register 0x08 is the one
 * Apple does not verify by read-back, so neither does this.
 */
struct a1534_amp_reg {
	unsigned char reg;
	unsigned char val;
	bool slot;		/* OR the TDM slot into the value */
	bool verify;
};

static const struct a1534_amp_reg a1534_amp_init_seq[] = {
	{ 0x01, 0xfd, false, true  },
	{ 0x02, 0xc4, false, true  },
	{ 0x03, 0x80, true,  true  },
	{ 0x04, 0xcf, false, true  },
	{ 0x06, 0x55, false, true  },
	{ 0x08, 0x10, false, false },
	{ 0x10, 0xff, false, true  },
	{ 0x11, 0xfc, false, true  },
};

/* I2C address and TDM slot of each amplifier, from AppleHDA layouts
 * 121/127/129 and confirmed by the code that consumes that table. */
struct a1534_amp {
	unsigned char addr;
	unsigned char slot;
};

static const struct a1534_amp a1534_amps[] = {
	{ 0x6c, 0 },
	{ 0x6d, 1 },
	{ 0x6e, 0 },
	{ 0x6f, 1 },
};

/*
 * Program all four amplifiers.
 *
 * Returns the number of amplifiers whose verified registers read back as
 * written. Zero does not show that the bus is silent: a read on this path has
 * answered an empty address exactly like an amplifier one (see the comment
 * above a1534_amp), so zero only says that nothing verified.
 */
static int a1534_amp_bringup(struct hda_codec *codec)
{
	unsigned int i, j;
	int live = 0;

	if (!a1534_amp)
		return -EPERM;

	a1534_i2c_enable(codec, true);

	/*
	 * Before trusting any read-back, establish whether the I2C engine
	 * accepts writes at all. Write the address register, read it straight
	 * back, and say so. If this does not hold, nothing downstream of it
	 * means anything - which is exactly the mistake that cost four
	 * releases: acting on a read whose path had never been checked.
	 */
	{
		unsigned int probe = a1534_amps[0].addr << 1;
		unsigned int back;

		cs_vendor_coef_set(codec, A1534_COEF_I2C_ADDR, probe);
		back = cs_vendor_coef_get(codec, A1534_COEF_I2C_ADDR);
		codec_info(codec,
			   "A1534: I2C engine check: coef %#04x wrote %#06x read %#06x, enable coef %#04x = %#06x\n",
			   A1534_COEF_I2C_ADDR, probe, back,
			   A1534_COEF_I2C_ENABLE,
			   cs_vendor_coef_get(codec, A1534_COEF_I2C_ENABLE));
	}

	for (i = 0; i < ARRAY_SIZE(a1534_amps); i++) {
		unsigned int addr = a1534_amps[i].addr;
		int bad = 0;

		for (j = 0; j < ARRAY_SIZE(a1534_amp_init_seq); j++) {
			const struct a1534_amp_reg *e = &a1534_amp_init_seq[j];
			unsigned int val = e->val;
			unsigned int got;

			if (e->slot)
				val |= a1534_amps[i].slot;

			a1534_i2c_write(codec, addr, e->reg, val);

			if (!e->verify)
				continue;

			got = a1534_i2c_read(codec, addr, e->reg) & 0xff;
			if (got != val) {
				if (!bad)
					codec_warn(codec,
						   "A1534: amp %#04x reg %#04x read back %#04x, wrote %#04x\n",
						   addr, e->reg, got, val);
				bad++;
			}
		}

		if (bad)
			codec_warn(codec, "A1534: amp %#04x: %d of %zu registers did not verify\n",
				   addr, bad, ARRAY_SIZE(a1534_amp_init_seq));
		else
			live++;
	}

	a1534_i2c_enable(codec, false);

	codec_info(codec, "A1534: amplifier bring-up: %d of %zu amplifiers verified\n",
		   live, ARRAY_SIZE(a1534_amps));

	return live;
}

#endif /* A1534_I2C_H */
