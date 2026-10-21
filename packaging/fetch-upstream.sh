#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Assemble the upstream-derived half of src/cs420x-a1534 from primary sources.
#
# This repository does not carry kernel code. It carries the patches that
# describe what this project changes, and this script reconstructs the rest:
#
#   fetched   sound/hda/codecs/cirrus/cs420x.c  and the five private HDA
#             headers, from git.kernel.org, at one tag per kernel series.
#             With no option the tags are the newest ones upstream.lock
#             records for each series; they are never guessed from whatever
#             headers the building machine happens to have installed.
#   derived   <series>/cs420x.c     = upstream/<series>/cs420x.c
#                                     + local-changes.patch
#             vendored/a1534_sequence.h
#                                   = vendored/ORIGINAL-a1534_sequence.h
#                                     + vendored/a1534_sequence.patch
#
# Several kernel series are shipped side by side (kheaders/<series>/ and so on),
# because the private headers differ between series and the module is built
# against the series of the kernel DKMS is building for.
#
# The second derivation touches the network not at all: the A1534 bring-up
# sequence is a permanent part of this repository and of the package, and is
# never downloaded from anywhere. The kernel fetch is the only download in the
# whole build, and it exists because the private headers under sound/hda/ are
# shipped by no package: linux-cachyos-headers installs Kconfig files there
# and nothing else.
#
# It runs at *package* build time (packaging/make-package.sh), never at DKMS
# build time. A DKMS rebuild happens during a kernel upgrade, where a network
# fetch would be fragile and surprising; the tree staged into /usr/src is
# complete, so kernel-update rebuilds stay entirely offline.
#
# Every fetched and every derived file is checked against packaging/upstream.lock
# before it is allowed into the tree. A known file whose hash changed is a hard
# failure with no override.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$ROOT/src/cs420x-a1534"
LOCK="$HERE/upstream.lock"
CACHE="$HERE/.upstream-cache"
DEST="$SRC"

BASE_URL='https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain'

# The complete fetch list. Nothing outside it is ever downloaded.
#   <path inside the module tree, without the series>:<path inside the kernel tree>
# The series goes between the directory and the file name when the file is
# installed: upstream/cs420x.c becomes upstream/<series>/cs420x.c.
FETCH=(
	'upstream/cs420x.c:sound/hda/codecs/cirrus/cs420x.c'
	'kheaders/hda_local.h:sound/hda/common/hda_local.h'
	'kheaders/hda_auto_parser.h:sound/hda/common/hda_auto_parser.h'
	'kheaders/hda_jack.h:sound/hda/common/hda_jack.h'
	'kheaders/hda_beep.h:sound/hda/common/hda_beep.h'
	'kheaders/generic.h:sound/hda/codecs/generic.h'
)

OPT_TAGS=()
OPT_KVER=''
OPT_ALL=0
OPT_OFFLINE=0
OPT_ACCEPT_NEW=0
OPT_PRINT_TAG=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

usage() {
	cat <<'USAGE'
usage: fetch-upstream.sh [options]

  (no option)      assemble the newest tag upstream.lock records for every
                   kernel series it knows
  --all            the same, explicitly
  --tag vX.Y[.Z]   assemble this tag; repeat for several series. Only the
                   named series are assembled, and any other is removed
  --kver RELEASE   resolve the tag from this kernel release (e.g. 7.2.6-1-cachyos)
  --dest DIR       assemble into DIR instead of src/cs420x-a1534
  --cache DIR      cache directory (default packaging/.upstream-cache)
  --offline        use the cache only; never touch the network
  --accept-new     record a hash for a (tag, file) pair the lockfile does not
                   know yet. Never overrides a pair it already knows.
  --print-tag      print the resolved tags, one per line, and exit
  -h, --help       this text

KDIR, when set to a kernel build directory and no tag option is given,
resolves the tag from that kernel's utsrelease.h.
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
		--tag) OPT_TAGS+=("${2:?--tag needs a value}"); shift 2 ;;
		--all) OPT_ALL=1; shift ;;
		--kver) OPT_KVER="${2:?--kver needs a value}"; shift 2 ;;
		--dest) DEST="${2:?--dest needs a value}"; shift 2 ;;
		--cache) CACHE="${2:?--cache needs a value}"; shift 2 ;;
		--offline) OPT_OFFLINE=1; shift ;;
		--accept-new) OPT_ACCEPT_NEW=1; shift ;;
		--print-tag) OPT_PRINT_TAG=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; die "unknown argument: $1" ;;
	esac
done

# ---------------------------------------------------------------- resolving

# X.Y.Z-N-flavour -> vX.Y.Z, and vX.Y.0 -> vX.Y, because kernel.org tags the
# first release of a series without the trailing .0.
tag_from_release() {
	local rel="$1" v
	v="$(printf '%s\n' "$rel" | sed -n 's/^\([0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?\).*$/\1/p')"
	[ -n "$v" ] || return 1
	v="${v%.0}"
	printf 'v%s\n' "$v"
}

uts_release() {  # <kernel build dir> -> UTS_RELEASE, or nothing
	local h="$1/include/generated/utsrelease.h"
	[ -r "$h" ] || return 1
	sed -n 's/.*UTS_RELEASE[[:space:]]*"\([^"]*\)".*/\1/p' "$h" | head -1
}

series_of_tag() {  # vX.Y[.Z] -> X.Y
	printf '%s\n' "$1" | sed -n 's/^v\([0-9]\+\.[0-9]\+\)\(\..*\)\?$/\1/p'
}

# The newest tag the lockfile records for every series it knows, one per line,
# oldest series first. "Newest" is a version sort, so v7.2 < v7.2.6 < v7.2.11.
lock_newest_tags() {
	awk '$1 ~ /^v[0-9]+\.[0-9]+/ { print $1 }' "$LOCK" | sort -uV | awk '
		{ s = $0; sub(/^v/, "", s); n = split(s, a, "."); k = a[1] "." a[2]; t[k] = $0; if (!(k in seen)) { seen[k] = 1; ord[++c] = k } }
		END { for (i = 1; i <= c; i++) print t[ord[i]] }
	' | sort -V
}

resolve_tags() {  # prints one tag per line
	local rel='' t

	if [ "${#OPT_TAGS[@]}" -gt 0 ]; then
		printf '%s\n' "${OPT_TAGS[@]}"
		return 0
	fi

	if [ -n "$OPT_KVER" ]; then
		rel="$(uts_release "/usr/lib/modules/$OPT_KVER/build" || true)"
		[ -n "$rel" ] || rel="$OPT_KVER"
	elif [ "$OPT_ALL" != 1 ] && [ -n "${KDIR:-}" ] && [ -r "$KDIR/include/generated/utsrelease.h" ]; then
		rel="$(uts_release "$KDIR")"
	else
		[ -r "$LOCK" ] || die "no lockfile at $LOCK"
		t="$(lock_newest_tags)"
		[ -n "$t" ] || die "$LOCK records no kernel tag"
		printf '%s\n' "$t"
		return 0
	fi

	tag_from_release "$rel" || die "cannot derive a kernel.org tag from '$rel'"
}

TAGS=()
while IFS= read -r t; do
	[ -n "$t" ] && TAGS+=("$t")
done < <(resolve_tags)
[ "${#TAGS[@]}" -gt 0 ] || die "no kernel tag to assemble"

SERIES_LIST=()
declare -A SERIES_TAG=()
for t in "${TAGS[@]}"; do
	s="$(series_of_tag "$t")"
	[ -n "$s" ] || die "cannot derive a kernel series from tag '$t'"
	if [ -n "${SERIES_TAG[$s]:-}" ]; then
		[ "${SERIES_TAG[$s]}" = "$t" ] && continue
		die "two tags for series $s: ${SERIES_TAG[$s]} and $t. One series carries one tag."
	fi
	SERIES_TAG[$s]="$t"
	SERIES_LIST+=("$s")
done
mapfile -t SERIES_LIST < <(printf '%s\n' "${SERIES_LIST[@]}" | sort -V)

if [ "$OPT_PRINT_TAG" = 1 ]; then
	for s in "${SERIES_LIST[@]}"; do printf '%s\n' "${SERIES_TAG[$s]}"; done
	exit 0
fi

# ---------------------------------------------------------------- lockfile

[ -r "$LOCK" ] || die "no lockfile at $LOCK"

lock_hash() {  # <tag> <path> -> recorded hash, or nothing
	awk -v t="$1" -v p="$2" '
		/^[[:space:]]*#/ { next }
		$1 == t && $3 == p { print $2; exit }
	' "$LOCK"
}

# Check one file against the lockfile. Three outcomes, and only one of them
# can ever be waved through:
#   recorded and equal      -> fine
#   recorded and different  -> hard failure, no override
#   not recorded            -> refuse, unless --accept-new says to record it
verify_against_lock() {  # <tag> <path> <file on disk>
	local tag="$1" path="$2" file="$3" have want
	have="$(sha256sum "$file" | cut -d' ' -f1)"
	want="$(lock_hash "$tag" "$path")"

	if [ -n "$want" ]; then
		if [ "$have" != "$want" ]; then
			note "  lockfile: $tag $path"
			note "  expected: $want"
			note "  got:      $have"
			die "$path at $tag does not match packaging/upstream.lock.

This is not a version bump; it is the same tag producing different bytes.
Do not override it. Find out why before building anything."
		fi
		return 0
	fi

	if [ "$OPT_ACCEPT_NEW" != 1 ]; then
		die "packaging/upstream.lock has no entry for '$tag $path'.

Its hash is $have.
If that is the file you mean to build against, re-run with --accept-new to
record it, then commit the lockfile change so the hash is reviewed like any
other change."
	fi

	printf '%-10s %s  %s\n' "$tag" "$have" "$path" >> "$LOCK"
	note "  recorded new lockfile entry: $tag $path"
}

# ---------------------------------------------------------------- fetching

note "kernel tags:  ${TAGS[*]}"
note "series:       ${SERIES_LIST[*]}"
note "cache:        $CACHE"
note "destination:  $DEST"

for s in "${SERIES_LIST[@]}"; do
	TAG="${SERIES_TAG[$s]}"
	TAGCACHE="$CACHE/$TAG"
	mkdir -p "$TAGCACHE/upstream" "$TAGCACHE/kheaders"

	for entry in "${FETCH[@]}"; do
		rel="${entry%%:*}"
		kpath="${entry#*:}"
		out="$TAGCACHE/$rel"

		if [ ! -s "$out" ]; then
			[ "$OPT_OFFLINE" = 1 ] && die "--offline, but $out is not in the cache"
			note "fetch $kpath ($TAG)"
			tmp="$out.part"
			curl -fsSL --retry 3 --retry-delay 2 --max-time 120 \
				-o "$tmp" "$BASE_URL/$kpath?h=$TAG" \
				|| { rm -f "$tmp"; die "fetch failed: $kpath at $TAG.

If $TAG is not a released stable tag, this is expected; pass a --tag that is."; }
			[ -s "$tmp" ] || { rm -f "$tmp"; die "fetch returned an empty $kpath"; }
			mv "$tmp" "$out"
		fi

		verify_against_lock "$TAG" "$rel" "$out"
	done
done

# ---------------------------------------------------------------- assembly

mkdir -p "$DEST/upstream" "$DEST/kheaders" "$DEST/vendored"

# Whatever an earlier assembly left for a series that is not part of this one
# goes, so that the manifests below describe the tree exactly. Only the
# per-series directories of generated files are touched.
for d in "$DEST"/upstream/*/ "$DEST"/kheaders/*/ "$DEST"/[0-9]*.[0-9]*/; do
	[ -d "$d" ] || continue
	b="$(basename "$d")"
	case "$b" in *[!0-9.]*) continue ;; esac
	[ -n "${SERIES_TAG[$b]:-}" ] || rm -rf "$d"
done
# The flat layout of releases before the multi-series one.
rm -f "$DEST/cs420x.c" "$DEST/upstream/cs420x.c" "$DEST"/kheaders/*.h

# The bring-up sequence comes from the tracked original, offline, always.
if [ "$DEST" != "$SRC" ]; then
	install -m 0644 "$SRC/vendored/ORIGINAL-a1534_sequence.h" \
		"$DEST/vendored/ORIGINAL-a1534_sequence.h"
fi

# --fuzz=0 on purpose. A patch that only *nearly* applies would produce a
# driver that differs from the one that was tested on hardware, silently.
# Failing here is the point.
apply_patch() {  # <patch> <input> <output> <remedy>
	local patchfile="$1" input="$2" output="$3" remedy="$4" tmp
	tmp="$(mktemp)"
	if ! patch --forward --fuzz=0 --reject-file=- -s -o "$tmp" "$input" \
			< "$patchfile" >/dev/null 2>&1; then
		rm -f "$tmp"
		die "$(basename "$patchfile") does not apply cleanly to $input.

$remedy"
	fi
	install -m 0644 "$tmp" "$output"
	rm -f "$tmp"
}

for s in "${SERIES_LIST[@]}"; do
	TAG="${SERIES_TAG[$s]}"
	TAGCACHE="$CACHE/$TAG"
	mkdir -p "$DEST/upstream/$s" "$DEST/kheaders/$s" "$DEST/$s"

	for entry in "${FETCH[@]}"; do
		rel="${entry%%:*}"
		install -m 0644 "$TAGCACHE/$rel" "$DEST/${rel%/*}/$s/${rel##*/}"
	done

	apply_patch "$SRC/local-changes.patch" \
		"$DEST/upstream/$s/cs420x.c" "$DEST/$s/cs420x.c" \
		"Upstream moved under this project's feet. Refresh local-changes.patch
against $TAG by hand, re-read LOCAL-CHANGES.md, and re-test on hardware.
Do not relax --fuzz to get past this."

	verify_against_lock "$TAG" 'cs420x.c' "$DEST/$s/cs420x.c"
done

apply_patch "$SRC/vendored/a1534_sequence.patch" \
	"$DEST/vendored/ORIGINAL-a1534_sequence.h" "$DEST/vendored/a1534_sequence.h" \
	"This patch has no kernel dependency, so it failing means the tracked
original or the patch itself was modified. Check git status."

verify_against_lock 'derived' 'vendored/a1534_sequence.h' "$DEST/vendored/a1534_sequence.h"

# ---------------------------------------------------------------- manifests

# The shipped series, oldest first, one per line. The Makefile's check: target
# reads this to decide whether a kernel is one this tree can be built for.
printf '%s\n' "${SERIES_LIST[@]}" > "$DEST/kheaders/KERNEL-SERIES"

# These are what the Makefile's check: target verifies at build time, in the
# packaged copy, where this script is not present.
manifest=()
for s in "${SERIES_LIST[@]}"; do
	manifest+=("upstream/$s/cs420x.c")
	for h in generic hda_auto_parser hda_beep hda_jack hda_local; do
		manifest+=("kheaders/$s/$h.h")
	done
done
manifest+=(kheaders/KERNEL-SERIES)
( cd "$DEST" && sha256sum "${manifest[@]}" > UPSTREAM.sha256 )

( cd "$DEST/vendored" && sha256sum \
	ORIGINAL-a1534_sequence.h a1534_sequence.h > PROVENANCE.sha256 )

# What UPSTREAM.sha256 cannot say: which kernel tag these bytes are from, and
# that they were checked against a lockfile before they were let in. An
# installed /usr/src tree carries no copy of this repository, so without this
# file there is nothing in it that answers "which kernel is this built from".
#
# It carries no assembly time: this file is part of
# the source tarball the PKGBUILD pins (packaging/mkdist.py), and a wall-clock
# date would give every assembly of the same bytes a different checksum. The
# tags are what identifies them.
{
	printf '# Assembled by packaging/fetch-upstream.sh.\n'
	printf '# Every line below was verified against packaging/upstream.lock\n'
	printf '# before the file it names was allowed into this tree.\n'
	for s in "${SERIES_LIST[@]}"; do
		printf 'tag %s\n' "${SERIES_TAG[$s]}"
		grep -E "^${SERIES_TAG[$s]//./\\.}[[:space:]]" "$LOCK"
	done
	grep -E '^derived[[:space:]]' "$LOCK"
} > "$DEST/UPSTREAM.lock"

note "assembled ${TAGS[*]} into $DEST"
