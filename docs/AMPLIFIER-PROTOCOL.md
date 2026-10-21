# The A1534 speaker amplifier path, recovered from AppleHDA

Version 20260914.04. The protocol below is **confirmed** by disassembly, and
three statements that were not have been corrected in place. See
`docs/APPLE-I2C-AUDIT.md` for the disassembly itself, with offsets.

Source: `com.apple.driver.AppleHDA`, extracted from
`System/Library/KernelCollections/BaseSystemKernelExtensions.kc` inside the
official macOS recovery image Apple serves for board id
`Mac-9AE82516C7C6B903` (this machine), product `012-40515`, dated
2022-08-24 (Monterey 12.5.x). The image was verified against Apple's
RSA-signed chunklist: signature **valid**, 63/63 chunks matching.

The binaries themselves are **not** in this repository. They are kept outside
it, on the maintainer's machine. Only the protocol facts are recorded here.

## 1. Why this was missing for so long

`docs/HARDWARE-PATH.md` §5.2 concluded that AppleHDA contains no amplifier
programming. That conclusion was drawn from the six *plug-in* binaries, which
were all the earlier evidence archive contained. It was correct about those
binaries and wrong about AppleHDA as a whole.

Since Big Sur, `AppleHDA.kext/Contents/MacOS/` does not exist on disk at all —
the main binary lives only inside the kernel collection. That is why it was
never collected, and why no amount of searching the archive could find it.

The main binary contains, among others:

```
AppleHDATDMBusManagerCS4208      AppleHDATDMAmpTAS5758L
AppleHDATDMBusManagerCS8409      AppleHDATDMAmpTAS5764L
AppleHDATDMDevice                AppleHDATDMAmpMAX98706
AppleHDAFunctionGroupCS4208      AppleHDATDMAmpSSM3515
```

## 2. The CS4208 is an I2C master — confirmed

`AppleHDAFunctionGroupCS4208` implements:

```
enableI2C(bool)
i2cRead (unsigned short addr, unsigned short reg, unsigned int *val)
i2cWrite(unsigned short addr, unsigned short reg, unsigned short val)
```

All three operate on **vendor widget NID `0x24`** — the widget this machine
reports as `[Vendor Defined Widget] wcaps 0xf0e2c1`, `ncoeff=128`. This is the
same architecture Linux already implements for the Cirrus CS8409
(`patch_cs8409.c`), and it settles `docs/HARDWARE-PATH.md` §5.4: AppleHDA's
"Bus 1" and "Bus 2" are the codec's own buses, not SoC I2C controllers.

### 2.1 Enabling the bridge

```
v = coef[0x00]
coef[0x00] = v ^ 0x08          /* pulse bit 3 */
if (enable)
        coef[0x00] = (v ^ 0x08) | 0x08
```

**Correction (20260914.04).** This said "enabling clears bit 3 and then sets
it". That is not what the code does and not what happens on this machine. The
first write is a **toggle**, so it clears bit 3 only when bit 3 was already
set. Coefficient 0x00 reads `0x00c4` here at cold boot, bit 3 clear, so
enabling writes `0x00cc` and then `0x00cc` again — there is no pulse. Disabling
is a bare toggle, so calling it twice re-opens the bridge. The transcription in
`a1534_i2c.h` was always algebraically identical to Apple's; only this sentence
was wrong.

### 2.2 Write transaction

```
coef[0x14] = addr << 1         /* 7-bit address, write direction */
coef[0x16] = 0x04              /* start */
read coef[0x17]                /* status */
coef[0x15] = reg               /* data byte */
read coef[0x17]
coef[0x15] = val               /* data byte */
read coef[0x17]
coef[0x16] = 0x02              /* stop */
read coef[0x17]
```

### 2.3 Read transaction

```
coef[0x14] = addr << 1
coef[0x16] = 0x04
read coef[0x17]
coef[0x15] = reg
read coef[0x17]
coef[0x14] = (addr << 1) | 1   /* read direction */
coef[0x16] = 0x04
read coef[0x17]
val = coef[0x15]
read coef[0x17]
coef[0x16] = 0x02              /* stop */
read coef[0x17]
```

**Correction (20260914.04).** The two closing lines were missing here and in
`a1534_i2c_read()`. Apple's `i2cRead` ends the read transaction with a STOP and
a final status read, exactly as its `i2cWrite` does. The kernel path has been
fixed. Note that the userspace probes in `tools/` *did* send the STOP, so
the kernel driver and the probes were never running the same protocol and
their results cannot be compared.

Apple additionally saves widget `0x24`'s power state around each transaction
and forces D0 if it was D3. On this codec widget `0x24` reports `wcaps
0xf0e2c1`, in which `AC_WCAP_POWER` (bit 10) is **clear**, so the widget has no
power control and this bracket is very probably inert here. It is recorded as a
difference, not as a cause.

### 2.4 What the status register is *not*

In both `i2cWrite` and `i2cRead` the value read from coefficient `0x17` is
stored in one stack slot that no later instruction reads. Apple checks the
**return code of the verb** every time and the **contents of the status
register** never. There is no ACK, NACK, busy or timeout evaluation in Apple's
driver to transcribe, so its absence from ours is not a defect and inventing
one would be inventing hardware behaviour. What the status read is for is
reaching the hardware.

## 3. The TAS5758L bring-up — confirmed

`AppleHDATDMAmpTAS5758L::enable(true)` writes eight registers, in this order,
reading each back afterwards to verify. The table is a static initialiser
copied into the object by the constructor.

| # | register | value | note |
| --- | --- | --- | --- |
| 0 | `0x01` | `0xfd` | |
| 1 | `0x02` | `0xc4` | |
| 2 | `0x03` | `0x80 \| TDMSlot` | slot OR'd in at run time |
| 3 | `0x04` | `0xcf` | |
| 4 | `0x06` | `0x55` | |
| 5 | `0x08` | `0x10` | **read-back verification skipped** |
| 6 | `0x10` | `0xff` | |
| 7 | `0x11` | `0xfc` | |

Surrounding sequence:

```
FunctionGroup::setPowerState(D0)
enableI2C(true)
for each entry: i2cWrite(addr, reg, val); i2cRead(addr, reg) and compare
enableI2C(false)
FunctionGroup::setPowerState(D3)
```

## 4. The four amplifiers

From `layout121/127/129.xml`, corroborated by the code that consumes it:

| amp | I2C address | bus | TDM slot |
| --- | --- | --- | --- |
| 0 | `0x6c` | 1 | 0 |
| 1 | `0x6d` | 1 | 1 |
| 2 | `0x6e` | 2 | 0 |
| 3 | `0x6f` | 2 | 1 |

Supply FETs on GPIO 4 (`CHDFETControl`) and GPIO 5 (`USDFETControl`);
amp-fault input on GPIO 1.

## 5. What this means for the deep-suspend defect

**Rewritten 20260914.04.** What stood here was a chain of four claims presented
as one fact: that the amplifiers lose supply in S3, that they therefore lose
their configuration, that Mac firmware programs them at power-on, and that
nothing in Linux reprograms them. Only the last is established. The others are
separated and tracked individually in `docs/CLAIMS-AUDIT.md`.

One piece of evidence now argues against the firmware-only story.
`AppleHDATDMAmpTAS5758L` has **no** `performPowerRailRestore` of its own, while
`AppleHDATDMAmpTAS5764L` and several widget classes do. If macOS relied on a
one-shot power-on programming it would need a restore path after sleep; if it
instead runs `enable(true)` whenever a TDM path is set up, it needs none. The
second shape fits the binary. That has not been traced to a call site yet and
is recorded as an open question, not as a conclusion.

## 6. Hardware corroboration — what the coefficient dump does and does not show

The first build with the amplifier bring-up captured the firmware-programmed
coefficient space at probe, boot
12:07:13, while the internal speakers were working (`proc_state = 0x1`):

    coef 00: 00c4 0000 003a 0baa 0c04 1000 9f9f 9f9f
    coef 08: 1f1f 1f1f 1f1f 1f1f 9f9f 9f9f 9f9f 9f9f
    coef 10: 1f1f 1f1f 1f1f 1f1f 0000 0000 0000 0000
    coef 18: 0400 0088 00f3 0002 0103 0bdf 016d 0000
    coef 20: 0000 0000 0080 0000 0000 0001 0000 0000
    coef 28: 0000 0000 0000 0000 0000 0000 0000 0000
    coef 30: 0000 0000 0000 0001 0301 0000 0034 0000
    coef 38: 0000 0000 0000 0000 0000 0000 0000 0000
    coef 40: 0000 0000 0000 0000 0000 0000 0000 0000
    coef 48: 0000 0000 0000 0000 0000 0000 0000 0000
    coef 50: 0000 0000 0000 0000 0000 0000 0000 0000
    coef 58: 0000 0000 0000 0000 0000 0000 0000 0000
    coef 60: 0000 0000 0000 0000 0000 0000 0000 0000
    coef 68: 0000 0000 0000 0000 0000 0000 0000 0000
    coef 70: 0000 0000 0000 0000 0000 0000 0000 0000
    coef 78: 0000 0000 0000 0000 0000 0000 0000 0000

Two details are **consistent with** §2:

- Coefficient `0x00` is `0x00c4`. Bit 3 — the I2C bridge enable — is **clear**.
- Coefficients `0x14`–`0x17` (address, data, control, status) are **all zero**.

**Correction (20260914.04).** This section previously read: "The firmware
programmed the four amplifiers at power-on and then closed the bridge behind
itself, leaving the engine idle." That is a story, not a measurement. An idle
engine with a closed bridge is equally consistent with an engine that was
*never used on this machine*, with amplifiers that need no programming, and
with amplifiers that are not on this bus at all. Zeroes in `0x14`–`0x17` are
evidence of *nothing having run recently*; they are not evidence of what ran
earlier, and reading them as a firmware signature was reading a story into a
blank register.

What the same kernel log shows a minute later is more informative. After the
triage script's I2C probing on 2026-09-14 13:41:13, the re-probe dump reads

    coef 10: 1f1f 1f1f 1f1f 1f1f 0041 0000 0002 0000
                                   ^0x14 ^0x15 ^0x16 ^0x17

- `0x14` holds `0x41`, the last address the probe wrote (`0x20 << 1 | 1`), so
  the **address register latches**;
- `0x16` still holds `0x02`, the STOP the probe wrote last, so the **control
  register is not cleared by anything**;
- `0x15` reads `0x00` although the probe last wrote a register number to it, so
  the **data register does not read back what was written**;
- `0x17` is `0x00` throughout.

Those four facts are the actual state of the evidence about this engine, and
they are what `tools/macbook91-amp-transport` is built to turn into a
verdict.

About 40 of the 128 coefficients are non-zero, so there is real state for the
resume path to restore. Nothing in the evidence archive contained any of this:
the macOS verb trace only ever *read* from this codec.

## 7. Provenance and licensing

This describes an interface recovered from a proprietary binary, for the sole
purpose of operating hardware its owner already owns. No Apple binaries are
included, and no Apple code or data is copied. For interoperability
research, `docs/` describes what was recovered from Apple's AppleHDA driver:
pseudo-code descriptions of six of its routines, written for this project from
the disassembly (`docs/APPLE-I2C-AUDIT.md`, sections 2 to 5 and 8; sections 2.1
to 2.3 and 3 above restate four of them more compactly), and facts such as
register addresses and values, I2C addresses and layout settings, in the
project's own words and tables. The driver implements the protocol from the
description above. The extracted binaries are kept outside the repository
and must not be redistributed.
