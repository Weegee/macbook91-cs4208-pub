# Line-by-line audit of Apple's I2C / amplifier path against ours

Version 20260914.04. **Method: static disassembly.** No hardware measurement is
claimed anywhere in this file.

## 0. Provenance

Binary: `com.apple.driver.AppleHDA`, fileset entry inside
`BaseSystemKernelExtensions.kc` of the official macOS recovery image Apple
serves for board id `Mac-9AE82516C7C6B903`, product `012-40515`.

    file   <extracted recovery image>/macOS Base System/System/Library/
           KernelCollections/BaseSystemKernelExtensions.kc
    kext   header at file offset 0x9b9000, vmaddr 0x9b9000
    __text vm 0x9b9788 + 0x8a8c7

All addresses below are the collection's **unslid vmaddrs**, exactly as its
symbol table reports them, and are reproducible with

    tools/macbook91-kc-disasm <kc> com.apple.driver.AppleHDA dis 0x...

`macbook91-kc-disasm` is new in this session: it resolves the fileset entry,
its segments and symbols, maps vmaddr to file offset, and disassembles a span
with call targets annotated. It is strictly read-only.

The extracted Apple binaries stay outside this repository and are not
redistributable, and this document copies no Apple code or data. It gives
pseudo-code descriptions of six routines, written for this project from the
disassembly (section 2: `readProcessingCoefficient` and
`writeProcessingCoefficient`; section 3: `enableI2C`; section 4: `i2cWrite`;
section 5: `i2cRead`; section 8: `AppleHDATDMAmpTAS5758L::enable`), and
otherwise the facts recovered from the binaries (addresses, register values,
call targets), in the project's own words and tables.

## 1. The call chain, resolved through the vtables

Devirtualised calls were resolved by reading the vtable object and masking the
chained-fixup pointer (`target = raw & 0x3fffffff`).

| call site | vtable | slot | resolves to |
| --- | --- | --- | --- |
| `this->…(0x24)` | `AppleHDAFunctionGroupCS4208` | vptr+0x218 | `AppleHDAFunctionGroup::getWidgetWithNodeID(ushort)` |
| `node->…(&x)` | `AppleHDAWidget` | vptr+0x180 | `AppleHDAWidget::powerState(uint*)` |
| `node->…(s,b)` | `AppleHDAWidgetCS4208` | vptr+0x188 | `AppleHDAWidgetCS4208::setPowerState(uint,bool)` |
| `node->…(i,&v)` | `AppleHDAWidget` | vptr+0x5c8 | `AppleHDAWidget::readProcessingCoefficient(uint,uint*)` |
| `node->…(i,v)` | `AppleHDAWidget` | vptr+0x5d0 | `AppleHDAWidget::writeProcessingCoefficient(uint,uint)` |
| `fg->…(b)` | `AppleHDAFunctionGroupCS4208` | vptr+0x510 | `…CS4208::enableI2C(bool)` |
| `fg->…(a,r,&v)` | `AppleHDAFunctionGroupCS4208` | vptr+0x518 | `…CS4208::i2cRead(ushort,ushort,uint*)` |
| `fg->…(a,r,v)` | `AppleHDAFunctionGroupCS4208` | vptr+0x520 | `…CS4208::i2cWrite(ushort,ushort,ushort)` |
| `fg->…(s,b)` | `AppleHDAFunctionGroupCS4208` | vptr+0x188 | `AppleHDAFunctionGroup::setPowerState(uint,bool)` |

**The I2C entry points take no bus argument.** `TAS5758L::enable` calls
`i2cWrite(I2Caddress, reg, val)` with three arguments and nothing else. This
settles the open question in `docs/AMPLIFIER-PROTOCOL.md` §4 and the
"`a1534_amp` has no `bus` field" objection: there is **one** I2C transport on
the CS4208, and "Bus 1 / Bus 2" in the layout data are TDM audio buses, not
I2C buses. No bus dispatch is missing from our implementation.

## 2. The coefficient transport — `AppleHDAWidget` @ 0x9f61ba / 0x9f6314

Both go through a verb-issuing virtual at widget vptr+0x120 with the signature
`(verb, parm, uint *res)`, and both use the **4-bit** HDA verb forms:

```
readProcessingCoefficient(index, *out):
    runVerb(0x0d, 0, &saved)      GET_COEF_INDEX     save the current index
    runVerb(0x05, index, &scratch) SET_COEF_INDEX
    runVerb(0x0c, 0, out)          GET_PROC_COEF
    runVerb(0x05, saved, &scratch) SET_COEF_INDEX    restore it

writeProcessingCoefficient(index, value):
    if (!this->cache)            -> error (line 0x147e)
    if (index >= this->ncoef)    -> error (line 0x1482)   bounds check
    runVerb(0x0d, 0, &saved)      GET_COEF_INDEX
    runVerb(0x05, index, &scratch) SET_COEF_INDEX
    runVerb(0x04, value, &scratch) SET_PROC_COEF
    this->cache[index] = value                       software shadow
    runVerb(0x05, saved, &scratch) SET_COEF_INDEX    restore it
```

These are exactly `AC_VERB_GET_COEF_INDEX` 0x0d, `AC_VERB_SET_COEF_INDEX` 0x5,
`AC_VERB_GET_PROC_COEF` 0xc, `AC_VERB_SET_PROC_COEF` 0x4 — the same four verbs
mainline `cs_vendor_coef_get()` / `cs_vendor_coef_set()` use. **The transport
primitive is not where we differ.** The only difference is that Apple saves
and restores the coefficient index around every access; ours leaves the index
where it was last set. That is harmless for a single-threaded sequence that
sets the index itself before every access, which ours does.

### 2.1 `runVerb` @ 0x9c25ea — and what it asserts

For every verb except the 4-bit `0xa`–`0xd` group and `SET_POWER_STATE`
(0x705), `runVerb` first issues `GET_POWER_STATE` (0xf05) and asserts that the
low nibble of the answer is 0, i.e. **D0**, logging an assertion otherwise. It
does not force the state; it only complains. Note that `SET_COEF_INDEX` (0x5)
and `SET_PROC_COEF` (0x4) are *not* in the exempt group but `GET_PROC_COEF`
(0xc) and `GET_COEF_INDEX` (0xd) are.

## 3. `enableI2C(bool)` @ 0x9c2dda — the bridge

```
node = getWidgetWithNodeID(0x24)      ; !node -> kIOReturnNoDevice, line 0x394
readProcessingCoefficient(0x00, &v)   ; error -> return,            line 0x398
v ^= 0x08
r = writeProcessingCoefficient(0x00, v)
if (enable) {
    if (r) -> return r                                              line 0x3a2
    v |= 0x08
    writeProcessingCoefficient(0x00, v)                             line 0x3a9
} else {
    if (r) -> return r                                              line 0x3b1
}
```

**Our `a1534_i2c_enable()` is algebraically identical to this.** The prose in
`docs/AMPLIFIER-PROTOCOL.md` §2.1 — "enabling clears bit 3 and then sets it" —
is the part that is wrong, and the objection to it is correct: with bit 3
initially **clear** the sequence is SET then SET, not CLEAR then SET. On this
machine coefficient 0x00 reads `0x00c4` at cold boot, bit 3 clear, so enabling
writes `0x00cc` twice and there is **no pulse at all**. Disabling is a pure
toggle in Apple's code too, so calling disable twice re-enables the bridge.
The code is faithful; the documentation is being corrected, not the code.

## 4. `i2cWrite(addr, reg, val)` @ 0x9c328c

```
node = getWidgetWithNodeID(0x24)                    ; !node -> line 0x41a
node->powerState(&saved)
if (saved == 3) node->setPowerState(D0, false)
set(0x14, (ushort)(addr << 1))                      ; error -> line 0x42d
set(0x16, 0x04)                     START           ; error -> line 0x430
get(0x17, &status)                  status          ; error -> line 0x433
set(0x15, (ushort)reg)                              ; error -> line 0x437
get(0x17, &status)                                  ; error -> line 0x43a
set(0x15, (ushort)val)                              ; error -> line 0x43e
get(0x17, &status)                                  ; error -> line 0x441
set(0x16, 0x02)                     STOP            ; error -> line 0x445
get(0x17, &status)                                  ; error -> line 0x448
if (saved == 3) node->setPowerState(saved, false)   ; success path only
return 0
```

## 5. `i2cRead(addr, reg, *out)` @ 0x9c2f1e

```
node = getWidgetWithNodeID(0x24)                    ; !node -> line 0x3c6
node->powerState(&saved)
if (saved == 3) node->setPowerState(D0, false)
set(0x14, (ushort)(addr << 1))                      ; line 0x3d9
set(0x16, 0x04)                     START           ; line 0x3dc
get(0x17, &status)
set(0x15, (ushort)reg)
get(0x17, &status)
set(0x14, (ushort)((addr << 1) | 1))                repeated address, read
set(0x16, 0x04)                     repeated START
get(0x17, &status)
get(0x15, &data)                    DATA -> *out
get(0x17, &status)
set(0x16, 0x02)                     STOP
get(0x17, &status)
if (saved == 3) node->setPowerState(saved, false)
return 0
```

## 6. What the status register is for

`i2cWrite` reads coefficient `0x17` four times and `i2cRead` six times. In
both functions the value is stored in **one stack slot that is never read
back**: `-0x2c(%rbp)` is written by every `get(0x17, …)` and is not an operand
of any later instruction. The *return code of the verb* is checked every time;
the *value of the status register* is checked **never**.

So the objection that our implementation "reads the status once and throws it
away, so there is no ACK/NACK/completion evidence" describes Apple's driver
exactly as much as ours. There is no ACK/NACK/timeout logic to transcribe,
because Apple does not have any. The status read is a **bus-paced dummy read**,
and the thing that matters about it is that it reaches the hardware at all.

That is a real constraint on our side and it holds: in Linux
`snd_hda_codec_read()` → `snd_hdac_codec_read()` → `codec_read()` →
`snd_hdac_exec_verb()` goes **straight to the controller**
(`device.c:1066-1091` of the Linux 7.2.4 tree, which is not part of this repository). The HDA **regmap cache
is not in this path at all** — `snd_hda_codec_write_cache()` would be, and we
do not use it. An earlier suspicion that the regmap cache silently drops a
repeated identical `SET_COEF_INDEX`, or answers `GET_PROC_COEF` from a shadow
copy, is therefore **refuted for this code path** and must not be revived.

## 7. Two real differences from our implementation

**D1 — `a1534_i2c_read()` never issues STOP.** Apple ends the read transaction
with `set(0x16, 0x02)` + a status read (§5); ours returns straight after
reading the data register. The bus is then left in a started state. The next
transaction issues a START on a bus that never saw a STOP. Our *userspace*
probes do send the STOP, so this defect is in the kernel path only — and it
means the kernel-side amplifier bring-up and the userspace probes were not
running the same protocol, which by itself invalidates comparing their results.

**D2 — no widget power handling.** Apple saves widget 0x24's power state and
forces D0 for the transaction. We never do. On *this* codec widget 0x24 reports
`wcaps 0xf0e2c1`, and bit 10 `AC_WCAP_POWER` is **clear** — the widget has no
power control, which is why `/proc/asound/card0/codec#0` prints no "Power
states" line for it. So this difference is very probably inert here. It is
recorded as a difference, not as a cause, and must not be "fixed" on the
strength of the analogy alone.

A third difference is not in the transport but in the caller: Apple checks the
return code of every coefficient access and aborts the transaction on the first
failure. `cs_vendor_coef_get()` returns `-1` on a failed verb, which our code
would silently use as `0xffff`.

## 8. The TAS5758L bring-up — read out of the binary, not inferred

`AppleHDATDMAmpTAS5758L::enable(bool)` @ 0xa2e1b4:

```
fg = this->fg                       (this+0x10)
fg->setPowerState(D0, false)                                   ; line 0x6d
fg->enableI2C(true)                                            ; line 0x71
for (i = 0; i < 8; i++) {
    if (i == 2) this->tbl[2].val |= this->TDMSlot               (this+0x5c)
    fg->i2cWrite(this->I2Caddress, tbl[i].reg, tbl[i].val)      ; line 0x7d
    fg->i2cRead (this->I2Caddress, tbl[i].reg, &back)           ; line 0x7f
    if (tbl[i].reg != 0x08 && back != tbl[i].val)
        log(line 0x88)             /* logs and CONTINUES */
}
fg->enableI2C(false)                                           ; line 0x8f
fg->setPowerState(D3, false)                                   ; line 0x93
```

The table is instance data copied from a static initialiser at **0xa48c42** by
the constructor @ 0xa2df9c; the loop indexes it at `this+0x3a + 4*i` as
`{u16 reg, u16 val}`. Its eight register/value pairs, read from the binary:

| i | reg | val | note |
| --- | --- | --- | --- |
| 0 | 0x01 | 0xfd | |
| 1 | 0x02 | 0xc4 | |
| 2 | 0x03 | 0x80 | `\|= TDMSlot` at run time |
| 3 | 0x04 | 0xcf | |
| 4 | 0x06 | 0x55 | |
| 5 | 0x08 | 0x10 | read-back **not** compared |
| 6 | 0x10 | 0xff | |
| 7 | 0x11 | 0xfc | |

This is byte-for-byte what `a1534_i2c.h` already carries, now confirmed
directly from the binary rather than from the previous session's notes. The
read-back skip is on **register 0x08**, matched by register number, not by
table position. A failed read-back is logged and the loop **continues** — Apple
does not treat it as fatal, and neither should a verdict drawn from it.

Instance fields: `I2Caddress` at `this+0x5a`, `TDMSlot` at `this+0x5c`, both
read from the layout dictionary by `init()` @ 0xa2e000 using the property keys
`"I2Caddress"` and `"TDMSlot"` (strings at 0xa4408b, 0xa44096).

`this->tbl[2].val |= slot` mutates the **instance's own copy**, so it is
idempotent across repeated `enable(true)` calls.

## 9. The power state Apple drives is the function group, not the widget

`TAS5758L::enable` brackets the whole bring-up with
`AppleHDAFunctionGroup::setPowerState(D0)` … `setPowerState(D3)` on the
**function group** (the AFG), not on widget 0x24. Our resume path does not
control the AFG power state around the bring-up either way.

## 10. When does macOS program the amplifiers? Once, at init.

`AppleHDATDMAmpTAS5758L::init(...)` ends, at 0xa2e126, with a virtual call
through slot 0x1a8 of the object's own vtable, with the argument `true`.

vptr+0x1a8 in `__ZTV22AppleHDATDMAmpTAS5758L` (0xa66a70) resolves to
`AppleHDATDMAmpTAS5758L::enable(bool)` @ 0xa2e1b4 — the eight-register
bring-up of §8. The amplifier objects are created by
`AppleHDATDMDeviceFactory::createAppleHDATDMDevice` @ 0xa12b66, called from
`AppleHDAFunctionGroup::setupTDMDevices` @ 0x9fbd4c.

So on macOS the four amplifiers are programmed **once, when AppleHDA builds
its TDM device list**, and not per stream: `AppleHDAPath::enable` @ 0x9ecb3c
contains no call to that slot at all.

### 10.1 And nothing puts them back after a sleep

`AppleHDATDMAmpTAS5758L` has **no** `performPowerRailSave` and **no**
`performPowerRailRestore`. `AppleHDATDMAmpTAS5764L` has both (0xa11052,
0xa110c8), and so do `AppleHDAWidgetCS4208`, `AppleHDAFunctionGroupCS8409`,
`AppleHDATDM_CS42L83` and others. `AppleHDATDMDevice`'s vtable is 0x1c0 bytes
against `AppleHDANode`'s 0x210, so the TDM device classes are not even in the
node hierarchy that carries those methods — TAS5764L had to add them
deliberately.

That asymmetry is evidence, and it points away from the story this project has
been telling itself. If the TAS5758L amplifiers lost their configuration across
a system sleep, macOS would need a restore path for them and Apple would have
written one, as they did for the 5764L. There is none.

Two readings survive:

1. **The amplifiers keep their configuration across sleep on this machine**,
   because their supply is maintained. Then "the amps lose state in S3" is
   simply false, and the speaker silence after resume is a codec- or TDM-side
   fault — which is where an earlier build already found one real cause, the stream width
   changing from 16 to 24 bit.
2. Something outside AppleHDA re-establishes them, or AppleHDA is re-initialised
   on wake.

Neither is settled here, and macOS's actual behaviour after sleep on *this*
unit has not been observed by this project. But claim D4 in
`docs/CLAIMS-AUDIT.md` — "Mac firmware programs them at power-on" — is now
positively contradicted for the programming step: **AppleHDA does it, in
`init()`.** What the firmware does before AppleHDA loads remains unknown.

## 11. What this does *not* establish

- Nothing here measures this machine. Every statement above is about a binary.
- It does not show that the amplifiers are at 0x6c–0x6f on this unit, that they
  answer, or that they lose state in S3.
- `AppleHDATDMAmpTAS5758L` has **no** `performPowerRailRestore` of its own,
  while `TAS5764L` and several widget classes do. What re-runs `enable(true)`
  after a sleep, and whether anything does, is **not yet established** and is
  the next thing to read (`AppleHDAFunctionGroup::setupTDMDevices` @ 0x9fbd4c,
  `AppleHDATDMBusManagerCS4208::setupTDMPath` @ 0xa37916,
  `AppleHDAWidgetCS4208::performPowerRailRestore` @ 0x9bf7ba).
