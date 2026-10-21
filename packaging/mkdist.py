#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the package's source tarball, byte-reproducibly.

Output: dist/NAME-VERSION.tar and .sha256 (or --out DIR). The tarball is
what packaging/arch/PKGBUILD pins, so it has to be the same bytes every time
it is built from the same inputs - the `tar -caf` tarball it replaces was
not, which is why that PKGBUILD's checksums were "a formality".

Contents, under NAME-VERSION/, laid out as in the repository so the Makefile's
`install` target works in both places:

  src/cs420x-a1534/   every tracked file, plus exactly the files
                      packaging/fetch-upstream.sh assembles (GENERATED below,
                      each one checked against packaging/upstream.lock by the
                      fetcher before it exists at all)
  tools/macbook91-audio-verify, Makefile, VERSION, LICENSE, and LICENSES/
                      with the texts of the licenses besides LICENSE's
                      GPL-3.0 that files in the tarball carry

Anything else in the module tree that git ignores and that is not a build
artifact is refused: an unknown file must never reach /usr/src unseen. So is a
tree that is not assembled, and - unless --allow-dirty - a tracked file with
uncommitted changes, because a release tarball holds committed content only.

Entries are sorted, owned by 0:0, mode 0755 for executables and 0644
otherwise, all with mtime 0. The tar is not compressed: gzip output depends on
the zlib implementation (zlib and zlib-ng give different bytes for the same
input), and the checksum pinned in the PKGBUILD has to hold on every machine.
"""

from __future__ import annotations

import fnmatch
import hashlib
import io
import os
import re
import subprocess
import sys
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "macbook91-cs4208-dkms"
MODULE = "src/cs420x-a1534"
# What fetch-upstream.sh writes into the module tree (src/cs420x-a1534/.gitignore).
# The per-series files are listed for every series packaging/upstream.lock
# records, so that a tree assembled for fewer series than the lock knows is
# refused rather than packaged.
HEADERS = ("generic.h", "hda_auto_parser.h", "hda_beep.h", "hda_jack.h", "hda_local.h")


def lock_series() -> list[str]:
    """The kernel series the lockfile has a tag for, oldest first."""
    found = set()
    with open(os.path.join(ROOT, "packaging", "upstream.lock"), encoding="ascii") as fh:
        for line in fh:
            m = re.match(r"v(\d+)\.(\d+)(\.\d+)?\s", line)
            if m:
                found.add((int(m.group(1)), int(m.group(2))))
    return [f"{a}.{b}" for a, b in sorted(found)]


def generated(series: list[str]) -> tuple[str, ...]:
    per_series = []
    for s in series:
        per_series += [f"upstream/{s}/cs420x.c", f"{s}/cs420x.c"]
        per_series += [f"kheaders/{s}/{h}" for h in HEADERS]
    return (
        *per_series,
        "kheaders/KERNEL-SERIES",
        "vendored/a1534_sequence.h",
        "vendored/PROVENANCE.sha256",
        "UPSTREAM.sha256",
        "UPSTREAM.lock",
    )


GENERATED = generated(lock_series())
# Build output a module build leaves behind; never packaged, never an error.
ARTIFACTS = ("*.o", "*.ko", "*.mod", "*.mod.c", "*.symvers", "*.order", ".*.cmd", ".tmp_versions/*")
EXTRA = ("tools/macbook91-audio-verify", "Makefile", "VERSION", "LICENSE",
         "LICENSES/GPL-2.0-only.txt", "LICENSES/GPL-2.0-or-later.txt",
         "LICENSES/LGPL-2.1-or-later.txt")


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True, text=True).stdout


def fail(msg: str) -> int:
    print(f"mkdist: {msg}", file=sys.stderr)
    return 1


def main(argv: list[str]) -> int:
    allow_dirty = "--allow-dirty" in argv
    out_dir = os.path.join(ROOT, "dist")
    if "--out" in argv:
        out_dir = os.path.abspath(argv[argv.index("--out") + 1])
    with open(os.path.join(ROOT, "VERSION"), encoding="ascii") as fh:
        version = fh.read().strip()

    if not allow_dirty and git("status", "--porcelain", "--untracked-files=no").strip():
        return fail("working tree has uncommitted changes; commit first (or --allow-dirty)")

    tracked = [f for f in git("ls-files", "-z", "--", MODULE, *EXTRA).split("\0") if f]
    missing = [g for g in GENERATED if not os.path.isfile(os.path.join(ROOT, MODULE, g))]
    if missing:
        return fail(f"module tree not assembled ({', '.join(missing)}); run packaging/fetch-upstream.sh")
    others = git("ls-files", "-z", "--others", "--", MODULE).split("\0")
    unknown = []
    for f in (o for o in others if o):
        rel = f[len(MODULE) + 1 :]
        if rel in GENERATED or any(fnmatch.fnmatch(os.path.basename(rel), p) or fnmatch.fnmatch(rel, p) for p in ARTIFACTS):
            continue
        unknown.append(f)
    if unknown:
        return fail(f"unexpected files in the module tree: {', '.join(sorted(unknown))}")

    files = sorted(set(tracked) | {f"{MODULE}/{g}" for g in GENERATED})
    for f in EXTRA:
        if f not in files:
            return fail(f"{f} is not tracked")

    prefix = f"{NAME}-{version}"
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as tar:
        parents = {os.path.dirname(f) for f in files} - {""}
        all_dirs = sorted({"/".join(d.split("/")[: i + 1]) for d in parents for i in range(d.count("/") + 1)})
        for d in ["", *all_dirs]:
            info = tarfile.TarInfo(f"{prefix}/{d}".rstrip("/"))
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.mtime = 0
            tar.addfile(info)
        for f in files:
            path = os.path.join(ROOT, f)
            with open(path, "rb") as fh:
                data = fh.read()
            info = tarfile.TarInfo(f"{prefix}/{f}")
            info.size = len(data)
            info.mode = 0o755 if os.stat(path).st_mode & 0o111 else 0o644
            info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
    os.makedirs(out_dir, exist_ok=True)
    target = os.path.join(out_dir, f"{prefix}.tar")
    with open(target, "wb") as fh:
        fh.write(raw.getvalue())
    with open(target, "rb") as fh:
        digest = hashlib.sha256(fh.read()).hexdigest()
    with open(target + ".sha256", "w", encoding="ascii") as fh:
        fh.write(f"{digest}  {prefix}.tar\n")
    print(f"{digest}  {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
