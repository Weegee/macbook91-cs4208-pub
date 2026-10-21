#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Build macbook91-cs4208-dkms from the working tree. Kept for the commands and
# documents that name it; it runs `make arch-pkg-dev` (see the root
# Makefile), which assembles the upstream-derived sources, writes the source
# tarball from the tracked files as they are on disk, and builds in a fresh
# build/arch. The package lands in dist/.
#
# A1534_FETCH_ARGS replaces the fetcher options, whose default is `--all`
# (the newest tag in upstream.lock for every kernel series), so name every tag
# yourself: A1534_FETCH_ARGS='--tag vA.B.C --tag vX.Y.Z --offline' builds from
# the cache only.
# Arguments go to makepkg.
#
# A release is built with `make arch-pkg` instead, which also requires a
# committed tree and the tarball checksum pinned in packaging/arch/PKGBUILD.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
args=(-C "$ROOT" --no-print-directory arch-pkg-dev "MAKEPKG_FLAGS=$*")
if [ -n "${A1534_FETCH_ARGS:-}" ]; then
	args+=("FETCH_ARGS=$A1534_FETCH_ARGS")
fi
exec make "${args[@]}"
