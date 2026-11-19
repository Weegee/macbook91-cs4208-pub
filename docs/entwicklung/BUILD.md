# Building from source, tools and tests

## Build a package from a checkout

From a checkout the same files are in `release/<version>/`. To build from the
source tree instead (`make dist`, which `make arch-pkg` runs, needs a git
checkout of the repository, not an unpacked tarball or release download):

```bash
make arch-pkg
sudo pacman -U dist/macbook91-cs4208-dkms-*.pkg.tar.zst
```

`make arch-pkg` assembles the upstream-derived sources at the newest kernel tag
`packaging/upstream.lock` records for each supported series (six files per
series from git.kernel.org, or none with `FETCH_ARGS="--offline --all"` and a
filled cache; if git.kernel.org does not answer, the fetcher prints one warning
and takes the rest of the run from the GitHub mirror gregkh/linux, and
`FETCH_ARGS="--source github"` or `--source kernel.org` picks one source),
writes the source tarball, and builds the package in
`build/arch/` (copied to `dist/`). It needs a committed tree whose tarball
checksum is pinned in `packaging/arch/PKGBUILD`; `make arch-pkg-dev` builds an
unreleased tree as it is on disk.

## Measurement tools

After the installation, run `macbook91-audio-verify` (`docs/INSTALL.md`, step 5). The
measurement tools in `tools/` are for work from a checkout; `tools/README.md`
says which one to reach for. Their entry point is `tools/macbook91-runner`:

```bash
tools/macbook91-runner selfcheck        # nothing is touched
tools/macbook91-runner preflight        # identity, versions, sleep mode
sudo tools/macbook91-runner probe --with-stream
tools/macbook91-runner diff             # two captures, field by field
tools/macbook91-runner wake             # what wakes the machine early
```

The output of `selfcheck` on 2026-11-09, shortened to the check lines and the
verdict (the free-space check and the run paths are left out):

```text
== selfcheck (nothing is touched) ==
selfcheck.macbook91-amp-transport      PASS     present and parses
selfcheck.dep.python3                  PASS     /usr/bin/python3
selfcheck.dep.aplay                    PASS     /usr/bin/aplay
selfcheck.dep.systemctl                PASS     /usr/bin/systemctl
selfcheck.dep.modinfo                  PASS     /usr/bin/modinfo
selfcheck.unit_restore                 PASS     save/restore bookkeeping runs and verifies
selfcheck.not_root                     PASS     running unprivileged, as it should

== verdict: PASS ==
```

Every run lands in one directory under `$XDG_STATE_HOME/macbook91-cs4208/runs/`
(by default `~/.local/state/macbook91-cs4208/runs/`) that survives a reboot,
with a human report and a machine-readable result.
Each test reports PASS, FAIL, BLOCKED, NOT_RUN or SKIPPED; a mandatory test
that is never reached forces the verdict to INCOMPLETE rather than disappearing.
The other commands were not run for this revision of the text.

## Tests

The suite is hermetic: no root, no hardware, no sound. `tests/run-tests.sh` runs it.

The test count in the README is that of a host with the replacement module loaded.
A host that still runs the stock codec runs one more test and blocks the two
checks that compare the recorded totals, so it reports 335 passed, 0 failed,
10 blocked. That figure was measured on 2026-11-02 on a development host that
runs the stock codec; the count in the README is derived from it and was not run on a
host with the module loaded. A suite started with SIGINT ignored, as a
background job does, gives
the same result as one started in the foreground.
