# Evidence map

Version 20260915.02.

**This is the Phase 0 inventory, taken on 2026-09-14 before a line of driver
source existed, and kept because the provenance of the inputs has not changed.
It is not a status document.** Section E's verdicts are the verdicts as they
stood that day; the two that have since moved say so in the row and name what
settled them. For what is true now, read `docs/CLAIMS-AUDIT.md` and
`docs/PROJECT_STATE.md` - not this file.

Classification of every input this project relies on.
Confidence vocabulary per Phase 4 of the audio task statement: **confirmed**
(directly observed on the MacBook9,1 or read from primary source), **strongly
indicated** (consistent primary evidence, one inference step), **speculative**
(hypothesis only).

## A. Current source owned by this project

| Path | Status |
| --- | --- |
| `tools/dev-audio-collect.sh` | current, written this session, shellcheck-clean |
| the audio task statement and the bootstrap procedure | archived instructions of this investigation, already executed; kept with the maintainer's private notes and not published |
| `STRUCTURE.md` | layout rules; rewritten for the current directory names |
| `src/cs420x-a1534/` | the module, written after this inventory was taken |

No driver source existed in this repository when this inventory was written.
`src/cs420x-a1534/` is that source; its own provenance is recorded in
`UPSTREAM.txt`, `UPSTREAM.sha256`, `local-changes.patch` and
`vendored/PROVENANCE.md`, each checked by the Makefile before it compiles.

## B. Legacy / prior-attempt evidence (treat as evidence only)

| Item | Present? | Notes |
| --- | --- | --- |
| `legacy-20260913.01-6.bundle` | **ABSENT** | Named in the task as historical only. Not supplied; not required. |
| `prior-attempts/<host>-audio-20260912.01.zip` | **ABSENT** | Same. |
| `macbook91-audio-claude/` (the supplied evidence archive, not part of this repository) | present, verified | 188/188 files match `analysis/SHA256SUMS`; `input.tar.xz` matches `INPUT.sha256`. |
| `linux-driver/` snapshot | present | `leifliddy/macbook12-audio-driver`, based on davidjo's `snd_hda_macbookpro`. |
| `linux-driver-metadata/*` | **EMPTY (0 bytes, all four files)** | Commit id, git log, status and working-tree diff are all empty. **The exact upstream revision of the bundled driver snapshot is therefore unknown.** Provenance must be re-established independently before any of it is reused. |

## C. Primary external evidence

| Source | Retrieved | Confidence |
| --- | --- | --- |
| `sound/hda/codecs/cirrus/cs420x.c` @ tag `v7.2.4`, git.kernel.org | this session | confirmed (authoritative in-tree source for the running kernel) |
| `sound/hda/common/auto_parser.c` @ `v7.2.4` — `snd_hda_pick_fixup` | this session | confirmed |
| `sound/hda/common/hda_local.h` @ `v7.2.4` — `struct hda_quirk`, `HDA_CODEC_QUIRK` | this session | confirmed |
| Live codec dump, `/proc/asound/card0/codec#0` | baseline `20260914T050602Z` | confirmed |
| Running kernel `.config` at `/lib/modules/7.2.4-3-cachyos/build/.config` | baseline | confirmed |
| macOS `AppleHDA.kext` + decompressed layout XML | in archive, analysed — `docs/APPLE-I2C-AUDIT.md` | confirmed for what that document marks confirmed |
| Boot Camp `cs420x_46.inf`, `CS420X64.sys`, `CirrusAPO_x64.dll` | in archive, analysed — `docs/AMPLIFIER-PROTOCOL.md` | see that document's own confidence column |

## D. Directly proven on the test machine (confirmed)

1. DMI is `Apple Inc.` / `MacBook9,1`, board `Mac-9AE82516C7C6B903`.
2. Kernel `7.2.4-3-cachyos`; headers `linux-cachyos-headers 7.2.4-3` present;
   `UTS_RELEASE` and `Module.symvers` both present and matching.
3. Kernel was built with **clang 22.1.8 / LLD 22.1.8**;
   `CONFIG_CC_IS_CLANG=y`, `CONFIG_LD_IS_LLD=y`, `CONFIG_LTO_CLANG_THIN=y`,
   `CONFIG_CFI` **not** set. Host also has GCC 16.2.1 installed.
4. `CONFIG_SND_DEBUG=y` but `CONFIG_SND_DEBUG_VERBOSE` is **not** set.
5. HDA controller `8086:9d70`, PCI subsystem **`8086:7270`**.
6. Codec `Cirrus Logic CS4208`, vendor `0x10134208`, subsystem
   **`0x106b6500`**, revision `0x100401`.
7. Currently loaded codec module is the **stock in-tree**
   `snd_hda_codec_cs420x` (`intree: Y`, vermagic `7.2.4-3-cachyos`).
   **No DKMS module is installed** (`dkms status` empty); DKMS 3.4.3-1 is
   available.
8. PipeWire 1.6.8, WirePlumber 0.5.17, Plasma/Wayland session, deep suspend
   available (`/sys/power/mem_sleep` = `s2idle [deep]`).
9. All collector items were obtainable **unprivileged**. No root-only
   evidence gap exists at this stage.

## E. Hypotheses and their current status

| Hypothesis (from the audio task statement) | Verdict |
| --- | --- |
| Speaker path is Converter `0x0a` / Pin `0x1d` | **CONFIRMED** from live codec dump — see `docs/ROOT-CAUSE.md` §2. |
| Headphone path is Converter `0x02` / Pin `0x10` | **CONFIRMED** from live codec dump. |
| The failure is a PCI-vs-codec subsystem mis-match selecting a generic/MacBookAir path | **REFUTED as stated / replaced by a proven mechanism.** No MacBookAir fixup is selected; `CS4208_GPIO0` is. See `docs/ROOT-CAUSE.md` §3. |
| A previous implementation wrongly converted `HDA_CODEC_QUIRK` → `SND_PCI_QUIRK` | **NOT REPRODUCIBLE** against available artifacts: the bundled out-of-tree snapshot uses `HDA_CODEC_QUIRK`, while *mainline* uses `SND_PCI_QUIRK`. The blamed artifact is absent. |
| Correct fixup selection alone restores speakers | **REFUTED.** See `docs/ROOT-CAUSE.md` §4 — a fixup cannot create the missing PCM. |
| Headphone sequence drives the whole AFG through D3/D0 and may break concurrent capture | **REOPENED 2026-10-19: the effect is real.** A headphone plug during a running capture stops it, and later captures stay silent until the codec suspends; after the replay, capture converter `0x06` reads stream tag 0 (`docs/INCIDENT-20261019.md`). The entry "closed 2026-09-15" was wrong: the headphones were already in when that run asked for the plug, so only the unplug was measured. A driver fix is in the tree, not yet measured on hardware. |
| Four-channel speaker operation | **CONFIRMED 2026-09-15 and shipped.** The mapping is two stereo pairs, not a surround layout, measured a slot at a time; the internal PCM accepts only `S16_LE / 44100 / 4ch`. |

## F. Requiring independent revalidation before reuse

- Every line of the bundled `linux-driver` snapshot, because its upstream
  revision is unrecorded (§B) and mainline has moved on (§C).
- The A1534 vendor-coefficient sequence, then in the bundled snapshot's
  `patch_cirrus_a1534_setup.h` — cross-checked against AppleHDA and carried
  as `src/cs420x-a1534/vendored/ORIGINAL-a1534_sequence.h` plus
  `a1534_sequence.patch`, from which the build derives `a1534_sequence.h`
  (see `vendored/PROVENANCE.md`), with a checksum the Makefile enforces.
- The custom PCM implementation, then `patch_cirrus_a1534_pcm.h` — rewritten
  as `src/cs420x-a1534/a1534_pcm.h` rather than reused.
