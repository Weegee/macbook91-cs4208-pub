# tools

One place that says which tool to reach for.

## Start here

- **`macbook91-runner`** — the single entry point for new measurement work:
  `selfcheck`, `preflight`, `probe` (amplifier transport), `cycle`
  (suspend/resume), `jackstream` (concurrent-capture / jack-power during a
  live stream), `wake`, `report`, `diff`. See its own `--help`.
- **`macbook91-audio-verify`** — the packaged, user-facing post-install
  verifier (installed to `/usr/bin`). Not for development use.
- **`macbook91-codec-state`** — capability-gated codec register capture/diff,
  used by `macbook91-runner` internally and usable standalone.

## Superseded, kept as evidence

These tools predate `macbook91-runner` and are retained because their header
comments record the decision: they document what was actually run, and
nothing new should be added to them. Each carries a `SUPERSEDED` banner at
the top of its own header naming the `macbook91-runner` subcommand (or, for
`macbook91-speaker-probe` and `macbook91-resume-experiment`, the gate id) that
replaced it.

| Tool | Superseded by | Retired |
| --- | --- | --- |
| `macbook91-speaker-probe` | `macbook91-runner probe` | `hw.speaker_rate_44100`, `hw.speaker_channel_map` |
| `macbook91-suspend-probe` | `macbook91-runner cycle` / `jackstream` | — |
| `macbook91-resume-experiment` | `macbook91-runner cycle` | `hw.resume_probe_measured` |
| `macbook91-dfet-probe` | `macbook91-runner probe` | — |
| `macbook91-i2c-clock-probe` | `macbook91-runner probe` | — |
| `macbook91-i2c-probe` | `macbook91-runner probe` (or `macbook91-amp-transport` directly) | — |
| `macbook91-suspend-triage` | `macbook91-runner cycle` | — |

## Other tools

- `macbook91-amp-transport` — the amplifier I2C transport probe
  `macbook91-runner probe` calls internally.
- `macbook91-codec-dump` — plain-text diffable register dump. Not read-only
  (128 `SET_COEF_INDEX` coefficient-selector writes); see its own header.
  `macbook91-codec-state` is the capability-gated successor for new work.
- `macbook91-kc-disasm`, `macbook91-kc-symbols` — read-only Mach-O kernel
  collection disassembly, used against the macOS recovery image, which stays
  outside this repository (`README-macos-extraction.md`).
- `macbook91-fetch-macos-recovery`, `macbook91-verify-recovery-image` —
  evidence acquisition tooling; see `README-macos-extraction.md` for the macOS
  extraction side.
- `macbook91-wake-probe` — suspend/wake-source measurement, used by
  `macbook91-runner wake`.
- `dev-audio-collect.sh` — the Phase 1 read-only diagnostic collector.

See `README-macos-extraction.md` for the macOS/AppleHDA/Boot Camp evidence
extraction tools specifically.
