# Provenance and licensing

The module derives from mainline `sound/hda/codecs/cirrus/cs420x.c`; the
local delta is kept small, gated, and recorded in
`src/cs420x-a1534/local-changes.patch`.

Licenses, by path. Source, script and configuration files name the same
license on an `SPDX-License-Identifier` line; documentation, data, patches,
`VERSION` and the generated `.SRCINFO` carry none and follow the table.
`LICENSE` holds the GPL-3.0 text (also as `LICENSES/GPL-3.0-or-later.txt`),
`LICENSES/` the others.

| Path | License |
| --- | --- |
| `src/cs420x-a1534/<series>/cs420x.c`, `upstream/` and `kheaders/` (fetched from Linux at build time, never tracked), `src/cs420x-a1534/local-changes.patch` | GPL-2.0-or-later, as in Linux |
| `src/cs420x-a1534/vendored/ORIGINAL-a1534_sequence.h` (marker: `ORIGINAL-a1534_sequence.h.license`), `a1534_sequence.patch` and the derived `a1534_sequence.h` | GPL-2.0-only, an assumption: `vendored/PROVENANCE.md` |
| `src/cs420x-a1534/a1534_*.h`, `tests/*.c` | GPL-2.0-or-later: built into the kernel module, or with its headers |
| what builds the module or assembles its sources: `src/cs420x-a1534/Makefile` and `dkms.conf`, `packaging/fetch-upstream.sh` and `packaging/upstream.lock`, and the records the fetcher writes for the build (`UPSTREAM.lock`, `UPSTREAM.sha256`, `vendored/PROVENANCE.sha256`, `kheaders/KERNEL-SERIES`) | GPL-2.0-or-later: GPLv2 section 3 counts the scripts that control compiling and installing the module as part of its source |
| `src/cs420x-a1534/contrib/acp/` | LGPL-2.1-or-later, as the alsa-card-profile files they derive from; the upstream notice is retained in each file |
| `tools/macbook91-fetch-macos-recovery`, `tools/macbook91-verify-recovery-image` | BSD-3-Clause, derived from OpenCorePkg's `macrecovery.py` (`LICENSES/BSD-3-Clause.txt`) |
| everything else: tools, tests, packaging, the top-level `Makefile`, configuration, documentation, data | GPL-3.0-or-later |

GPL-3.0 cannot go into the kernel module, because the kernel is GPL-2.0-only,
and whoever passes on a built module has to provide its build files under
GPLv2 as well. A module built from these sources combines GPL-2.0-or-later
and GPL-2.0-only code; `MODULE_LICENSE("GPL")` in `cs420x.c`, unchanged from
Linux, states GPL version 2 to the kernel.

The two recovery tools derive from OpenCorePkg's
`Utilities/macrecovery/macrecovery.py` (<https://github.com/acidanthera/OpenCorePkg>)
and keep its BSD-3-Clause license and copyright notices. The A1534 verb
sequence comes from <https://github.com/leifliddy/macbook12-audio-driver>,
which states no license; `src/cs420x-a1534/vendored/PROVENANCE.md` records
where it comes from, who wrote it, and why it is treated as GPL-2.0-only. If you
hold rights in it and object to its inclusion, open an issue and it will be
removed. Quotations from other works in `docs/` keep those works' terms.
Earlier releases (up to 20261020.01) were made under their own licensing; they
are not part of this repository.

`docs/AMPLIFIER-PROTOCOL.md` and `docs/APPLE-I2C-AUDIT.md` describe an
interface recovered by disassembling Apple's own driver, for the sole purpose
of operating hardware its owner already owns. **No Apple binaries are
included, and no Apple code or data is copied.** For interoperability
research, `docs/` describes what was recovered from Apple's AppleHDA driver:
pseudo-code descriptions of six of its routines, written for this project from
the disassembly (`docs/APPLE-I2C-AUDIT.md`, sections 2 to 5 and 8; sections 2.1
to 2.3 and 3 of `docs/AMPLIFIER-PROTOCOL.md` restate four of them more
compactly), and facts such as register addresses and values, I2C addresses and
layout settings, in the project's own words and tables.
