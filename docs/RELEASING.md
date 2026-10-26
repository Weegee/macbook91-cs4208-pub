# Releasing macbook91-cs4208-dkms

The steps a release takes, in order, and where each rule comes from. Nothing
here is automatic: `packaging/promote-release.sh` does not commit, tag, push or
publish. Creating a GitHub release needs the maintainer's authorization and passed
release gates (sections 3 and 4 below).

## 0. Kernel series

The package supports the CachyOS LTS series and the newest CachyOS series,
and depends on the LTS headers: the LTS kernel is the default. The series
before the newest stays while the one `local-changes.patch` applies to it at
`--fuzz=0` and the module builds against its headers without a change (the
headers package from the pacman cache, extracted into a scratch directory,
is enough for that build); it goes when the next series arrives. There is one
patch for every series and no series-dependent code. A kernel of any other
series gets no module: DKMS skips it and the package's pacman hook warns
about it after the transaction.

The lockfile pins one kernel tag per series, and the package ships one derived
`cs420x.c` and one header set for every series pinned. The fetcher writes
them to `kheaders/KERNEL-SERIES`, the one list: dkms.conf's
`BUILD_EXCLUSIVE_KERNEL`, the pacman hook and `macbook91-audio-verify` all take
it from there through `contrib/pacman/kernel-series`. A tag the lockfile does
not know is refused. A tag bump inside a shipped series replaces that series'
newest tag.

    packaging/fetch-upstream.sh --tag vX.Y.Z --accept-new

records the new files' hashes in `packaging/upstream.lock`. `local-changes.patch`
must still apply exactly (`--fuzz=0`); if it does not, the patch needs work
first. Before a new series is accepted, read the diff of `cs420x.c` and of the
five headers against the previous series (quirk tables and
`snd_hda_pick_fixup()`, jack, PCM and power management, struct layouts), check
that the distribution's kernel did not patch those files, and build the module
for every shipped series. Review the lockfile diff and commit it on its own.
Dropping a series removes its rows from the lockfile, and the fetcher stops
assembling it. `tests/run-tests.sh` reads the 7.2 sources for its source-level
checks (`SERIES72`) and pins the 7.2 source identity, so dropping 7.2 moves
both to another series in the same change.

## 1. Version

- `VERSION`: `YYYYMMDD.NN` (the release date, `.01` for the first that day).
- `packaging/arch/PKGBUILD`: `pkgver=` the same value, `pkgrel=1`.
- `docs/CHANGELOG.md`: a section for the new version on top.

## 2. Source tarball and pin

    make dist

writes `dist/macbook91-cs4208-dkms-<VERSION>.tar` and its `.sha256`. Put that hash
into the PKGBUILD's `sha256sums`, then

    make srcinfo

and commit (`release: <VERSION>, <one line on what changed>`). `make arch-pkg`
refuses until the pin and the tarball agree; it prints the hash to use.

## 3. Build and gates

    make arch-pkg

builds `dist/macbook91-cs4208-dkms-<VERSION>-1-x86_64.pkg.tar.zst` from the
pinned tarball. Then, all on the committed tree:

- `bash tests/run-tests.sh` with the tree assembled and the package built: 0
  failed. The hardware checks it cannot run stay BLOCKED. The totals recorded
  in `docs/test-status.json` (`regress.suite`) and `README.md` are those of a
  host with the replacement module loaded; `regress.suite` also states what a
  host running the stock codec reports, which runs one more test and blocks
  the two checks that compare these records.
- `namcap` on the package and on `packaging/arch/PKGBUILD`: no errors, every
  warning explained in `docs/NAMCAP.md`.
- `git diff --check`, ShellCheck at warning level on the shipped scripts.

## 4. Hardware gate

Install the package on the test machine (`sudo pacman -U dist/...pkg.tar.zst`), reboot,
and have the maintainer run `macbook91-audio-verify` in a terminal with the
listening checks answered. A build, a cache or a test run is not a hardware
PASS. Record the result in `docs/test-status.json`.

## 5. Promote

    packaging/promote-release.sh

copies the PKGBUILD, .SRCINFO, install scriptlet, lockfile and tarball into
`release/<VERSION>/`, writes a `STATUS.txt` template (with the checksum of the
package built in `dist/`, which is not copied) and `SHA256SUMS` over the
tracked files, and prunes release directories older than the two newest.
Fill in `STATUS.txt`, then

    packaging/promote-release.sh --seal <VERSION>

writes `SHA256SUMS` again, since it covers `STATUS.txt`.

Update `docs/PROJECT_STATE.md` (its header date and the
"Current promoted package" line) and `docs/test-status.json`, and commit
(`<VERSION>: promote, ...`).

## 6. Tag and publish

With the maintainer's authorization: tag the promote commit `v<VERSION>`, push the
branch and the tag, and publish a GitHub release for the tag (not a
prerelease). The assets are the seven tracked files of `release/<VERSION>/`
and nothing else, passed by explicit name, not by a glob: `PKGBUILD`,
`.SRCINFO`, `macbook91-cs4208.install`, `upstream.lock`, `STATUS.txt`,
`SHA256SUMS` and `macbook91-cs4208-dkms-<VERSION>.tar`. The built package is
not an asset: its `.BUILDINFO` records the builder's directories and its
installed-package list. It stays in `dist/` (`STRUCTURE.md`).
