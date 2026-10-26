#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# promote-release.sh: copy the release files into release/<pkgver>/.
#
# Promotion used to be done by hand, and .SRCINFO was then missing from
# thirteen releases in a row. A gate enforced by memory is the same gate that
# gets missed, so this script does it.
#
# This script does not commit, tag, push or publish anything.
#
# Where the maintainer's private tree is present, promotion also runs its
# test scripts and the export guard over what a commit would carry, and
# removes the new release directory again when either fails. A clone without
# that tree (the published mirror) skips the gate. `--gate` runs the gate on
# its own, without promoting anything.
#
# SHA256SUMS covers exactly the files the repository tracks. It used to list
# the built .pkg.tar.zst as well, which is gitignored: `sha256sum -c` therefore
# passed only on the machine that built the release and failed in every fresh
# clone. The built package is not copied into release/<pkgver>/ at all: that
# directory is what gets published, and a package carries a .BUILDINFO with
# the builder's directories and its installed-package list. It stays in dist/.
# Its checksum is recorded in STATUS.txt for reference only.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PROG=promote-release.sh

err() { printf '%s: error: %s\n' "$PROG" "$*" >&2; }
say() { printf '%s\n' "$*" >&2; }

usage() {
	cat <<'USAGE'
Usage: promote-release.sh
       promote-release.sh --seal VERSION
       promote-release.sh --gate

Copy the release files into release/<pkgver>/ and seal them with SHA256SUMS.
Where the maintainer's private tree is present, run its tests and the export
guard as well. Nothing is committed, tagged, pushed or published.

Examples:
  packaging/promote-release.sh
  packaging/promote-release.sh --seal 20261026.02

Options:
      --seal VERSION  regenerate SHA256SUMS of release/VERSION after STATUS.txt
                      was filled in
      --gate          run only the private gate and promote nothing
  -h, --help          show this help and exit
  -V, --version       show the version and exit

Exit status:
  0  done
  1  a check refused the promotion or the gate failed
  2  usage error

Docs and bug reports: https://github.com/Weegee/macbook91-cs4208-pub
USAGE
}

version() {
	local v=unknown
	[ -r "$ROOT/VERSION" ] && v=$(head -n1 "$ROOT/VERSION")
	printf '%s (macbook91-cs4208-dkms) %s\n' "$PROG" "$v"
}

usage_error() {  # <message> [<option the user probably meant>]
	printf '%s: error: %s\n' "$PROG" "$1" >&2
	[ -z "${2:-}" ] || printf 'Did you mean: %s %s\n' "$PROG" "$2" >&2
	printf 'Help: %s --help\n' "$PROG" >&2
	exit 2
}

for arg in "$@"; do
	case "$arg" in
		-h|--help) usage; exit 0 ;;
		-V|--version) version; exit 0 ;;
	esac
done

# --seal <version>: regenerate an existing release directory's SHA256SUMS.
# Promotion writes a STATUS.txt template that has to be filled in by hand, and
# STATUS.txt is itself covered by SHA256SUMS - so the checksums must be redone
# afterwards. Doing that by hand is the same kind of remembered step that left
# thirteen releases without a .SRCINFO.
SEALED=""
GATE_ONLY=0
if [ $# -gt 0 ]; then
	case "$1" in
		--seal)
			[ $# -ge 2 ] || usage_error "--seal needs a version"
			[ $# -eq 2 ] || usage_error "unexpected argument: $3"
			SEALED=$2 ;;
		--gate)
			[ $# -eq 1 ] || usage_error "unexpected argument: $2"
			GATE_ONLY=1 ;;
		--se*|--s) usage_error "unknown option: $1" "--seal" ;;
		--ga*|--g) usage_error "unknown option: $1" "--gate" ;;
		-*) usage_error "unknown option: $1" ;;
		*) usage_error "unexpected argument: $1" ;;
	esac
fi

# The files a clone has, and therefore the ones SHA256SUMS may name.
# upstream.lock is on the list: a promoted release has to say which kernel
# bytes it was assembled from, and that is not deducible from the repository
# at the release's tag - the sources are fetched, so the lockfile is the record.
# The source is the reproducible tarball NAME-VERSION.tar that
# packaging/arch/PKGBUILD pins (releases before 20261006.01 had
# cs420x-a1534.tar.zst); seal takes whichever of the two the release directory
# holds.
TRACKED_FILES='PKGBUILD .SRCINFO macbook91-cs4208.install upstream.lock STATUS.txt'
seal() { # seal DIR
	local src="" f
	for f in "$1"/*.tar "$1"/cs420x-a1534.tar.zst; do
		[ -e "$f" ] && { src=$(basename "$f"); break; }
	done
	[ -n "$src" ] || { err "no source tarball in $1"; return 1; }
	(cd "$1" && sha256sum -- $TRACKED_FILES "$src" > SHA256SUMS)
	echo "sealed $1/SHA256SUMS over: $TRACKED_FILES $src"
}

# The gate. The directory name is spelled with a bracket so that this shared
# file does not name it; the glob finds the same directory.
PRIV=""
for d in "$ROOT"/priv[a]te; do
	[ -d "$d" ] && PRIV="$d"
done

private_gate() {
	local t ex stage rc=0 found=0
	if [ -z "$PRIV" ]; then
		say "private gate: skipped (no private tree in this clone)"
		return 0
	fi
	# 1. the private test scripts, each with its own counters.
	for t in "$PRIV"/tests/run-*.sh; do
		[ -e "$t" ] || continue
		found=1
		say "private gate: running ${t#"$ROOT"/}"
		bash "$t" || { err "private gate: ${t#"$ROOT"/} failed"; rc=1; }
	done
	[ "$found" -eq 1 ] || say "private gate: no private test script found"
	# 2. the export guard over the files a commit would carry: tracked and
	# untracked-but-not-ignored files of the working tree, minus the private
	# paths. Group P (private path names) is a hard failure here.
	ex="$PRIV/export"
	if [ ! -f "$ex/guard.sh" ]; then
		err "private gate: the export guard is missing"
		return 1
	fi
	stage=$(mktemp -d "${TMPDIR:-/tmp}/promote-gate.XXXXXX")
	local -a specs=()
	mapfile -t specs < <(bash -c 'source "$1/lib.sh"; kit_pathspecs exclude "$1/private-paths.txt"' _ "$ex")
	[ "${#specs[@]}" -gt 0 ] || { err "private gate: no private path list"; rm -rf "$stage"; return 1; }
	(
		cd "$ROOT"
		git ls-files -z --cached --others --exclude-standard --deduplicate -- . "${specs[@]}" \
			| while IFS= read -r -d '' f; do
				{ [ -e "$f" ] || [ -L "$f" ]; } && printf '%s\0' "$f"
			done \
			| tar --null --no-recursion -T - -cf - | tar -C "$stage" -xf -
	) || { err "private gate: could not stage the files"; rm -rf "$stage"; return 1; }
	say "private gate: scanning $(find "$stage" -type f | wc -l) files with the export guard"
	bash "$ex/guard.sh" --conf "$ex" --strict tree "$stage" || { err "private gate: the export guard found hits"; rc=1; }
	rm -rf "$stage"
	return "$rc"
}

if [ "$GATE_ONLY" -eq 1 ]; then
	private_gate
	exit $?
fi

if [ -n "$SEALED" ]; then
	DIR="$ROOT/release/$SEALED"
	[ -d "$DIR" ] || { err "no such release: $DIR"; exit 1; }
	seal "$DIR"
	exit 0
fi

ARCH="$HERE/arch"
PKGVER=$(sed -n 's/^pkgver=//p' "$ARCH/PKGBUILD" | head -1)
PKGREL=$(sed -n 's/^pkgrel=//p' "$ARCH/PKGBUILD" | head -1)
PKGNAME=$(sed -n 's/^pkgname=//p' "$ARCH/PKGBUILD" | head -1)

DEST="$ROOT/release/$PKGVER"
PKGFILE="$ROOT/dist/${PKGNAME}-${PKGVER}-${PKGREL}-x86_64.pkg.tar.zst"
SRCTAR="$ROOT/dist/${PKGNAME}-${PKGVER}.tar"

# 1. release/<ver>/ is promoted, immutable history - never overwritten.
if [ -e "$DEST" ]; then
	err "$DEST already exists, and release history is not overwritten"
	exit 1
fi

# 2. .SRCINFO must actually match the PKGBUILD being promoted.
GENERATED_SRCINFO="$(cd "$ARCH" && makepkg --printsrcinfo)"
if ! diff -q <(printf '%s\n' "$GENERATED_SRCINFO") "$ARCH/.SRCINFO" >/dev/null 2>&1; then
	err "makepkg --printsrcinfo differs from $ARCH/.SRCINFO; run make srcinfo first"
	exit 1
fi

# 3. the built package for this exact version must already exist (it is not
# copied; its checksum goes into STATUS.txt).
if [ ! -e "$PKGFILE" ]; then
	err "$PKGFILE does not exist; build it first with make arch-pkg"
	exit 1
fi

# 3b. ...from the tarball the PKGBUILD pins, not from some other build.
PINNED=$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" "$ARCH/PKGBUILD")
if [ ! -e "$SRCTAR" ] || [ "$(sha256sum "$SRCTAR" | cut -d' ' -f1)" != "$PINNED" ]; then
	err "$SRCTAR is missing or does not match the PKGBUILD's sha256sums; run make arch-pkg"
	exit 1
fi

install -dm755 "$DEST"
cp "$ARCH/PKGBUILD" "$DEST/PKGBUILD"
cp "$ARCH/.SRCINFO" "$DEST/.SRCINFO"
cp "$ARCH/macbook91-cs4208.install" "$DEST/macbook91-cs4208.install"
cp "$SRCTAR" "$DEST/$(basename "$SRCTAR")"
cp "$HERE/upstream.lock" "$DEST/upstream.lock"

PKGSUM=$(sha256sum "$PKGFILE" | cut -d' ' -f1)

cat > "$DEST/STATUS.txt" <<EOF
$PKGNAME $PKGVER-$PKGREL — TODO: WITHDRAWN / CANDIDATE / etc.

TODO: fill in before this release is considered documented. See prior
release/*/STATUS.txt for the level of detail expected: what changed, why,
what was measured, what is not yet verified, and the test suite counts.

Release assets: the files listed in SHA256SUMS and SHA256SUMS itself, which
are the text files of this directory and the source tarball. No built package
is part of this release.

Maintainer's local build of the package, for reference only. It is not
published. The package records the build date and the build environment, so a
package you build yourself will not have this checksum; the reproducible
artifact is the source tarball in SHA256SUMS.
$PKGSUM  $(basename "$PKGFILE")
EOF

seal "$DEST"

# 3c. the private gate. A failed gate removes the directory this run created,
# so a rerun is possible; nothing else was touched.
if ! private_gate; then
	rm -rf "${DEST:?}"
	err "the private gate failed, so $DEST was removed again"
	exit 1
fi

# 4. retention. STRUCTURE.md's rule is "retain the prior release until its
# replacement is durably saved; older ones are removed", and
# until now nothing enforced it - release/ had grown to twenty directories
# once already, and was pruned by hand. That is the same kind of remembered
# step that left thirteen releases without a .SRCINFO, so it is done here.
#
# Only directories strictly older than the two newest are removed, only after
# the new one is fully written and sealed, and every removal is named.
prune_old_releases() {
	local keep=2 n=0 v
	local vers=()
	for v in "$ROOT"/release/*/; do
		[ -d "$v" ] || continue
		vers+=("$(basename "$v")")
	done
	[ "${#vers[@]}" -gt 0 ] || return 0
	while read -r v; do
		[ -n "$v" ] || continue
		n=$((n + 1))
		if [ "$n" -le "$keep" ]; then
			continue
		fi
		rm -rf "${ROOT:?}/release/$v"
		echo "pruned release/$v (kept the $keep newest)"
	done < <(printf '%s\n' "${vers[@]}" | sort -V -r)
}
prune_old_releases

echo "promoted $PKGNAME $PKGVER-$PKGREL to $DEST"
echo "fill in $DEST/STATUS.txt, then re-seal the checksums it is part of:"
echo "    $HERE/promote-release.sh --seal $PKGVER"
