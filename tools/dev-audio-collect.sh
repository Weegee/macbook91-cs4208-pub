#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# dev-audio-collect.sh — read-only diagnostic collector for MacBook9,1 (A1534)
# CS4208 audio work.
#
# Collects only the machine facts this project needs. It never writes outside
# its own output directory, never loads/unloads modules, never changes mixer,
# PipeWire or power settings, and never records audio.
#
# Usage: dev-audio-collect.sh [-o OUTDIR] [--privileged]
#
#   -o OUTDIR      parent directory for the timestamped baseline
#                  (default: baselines/ under $XDG_STATE_HOME/macbook91-cs4208,
#                  else ~/.local/state/macbook91-cs4208; under sudo, that of
#                  the user who ran sudo)
#   --privileged   additionally run the small set of root-only probes.
#                  Without it, every root-only item is recorded as SKIPPED
#                  and the collector still completes.
#
set -uo pipefail

PRIVILEGED=0
OUTPARENT=""

while [ $# -gt 0 ]; do
	case "$1" in
		-o) [ $# -ge 2 ] || { printf -- '-o needs a directory\n' >&2; exit 2; }
		    OUTPARENT=$2; shift 2 ;;
		--privileged) PRIVILEGED=1; shift ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
	esac
done

repo_root() {
	git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null \
		|| printf '%s' "$(cd "$(dirname "$0")/.." && pwd)"
}

ROOT="$(repo_root)"
# Under sudo (--privileged) the invoking user's state directory, as
# macbook91-runner does: root's own would hide the baseline from that user
# and from the recovery archive.
SUDO_OWNER=""
CHOWN_ROOT=""
if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" = 0 ]; then
	SUDO_OWNER=$SUDO_USER
fi
if [ -z "$OUTPARENT" ]; then
	if [ -n "$SUDO_OWNER" ]; then
		CHOWN_ROOT="/home/$SUDO_OWNER/.local/state/macbook91-cs4208"
		OUTPARENT="$CHOWN_ROOT/baselines"
	else
		OUTPARENT="${XDG_STATE_HOME:-$HOME/.local/state}/macbook91-cs4208/baselines"
	fi
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$OUTPARENT/$STAMP"
mkdir -p "$OUT" || { printf 'cannot create %s\n' "$OUT" >&2; exit 1; }

# --- helpers ---------------------------------------------------------------

# cap(): bound any single capture so a runaway file cannot fill the disk.
cap() { head -c 2000000; }

# sec FILE DESC CMD... : run CMD, store stdout+stderr under OUT/FILE.
sec() {
	local file="$1" desc="$2"; shift 2
	{
		printf '### %s\n' "$desc"
		printf '### command: %s\n\n' "$*"
		"$@" 2>&1 | cap
		printf '\n### exit: %s\n' "${PIPESTATUS[0]}"
	} > "$OUT/$file"
}

# copy FILE SRC : copy a readable proc/sys file, or record why not.
copy() {
	local file="$1" src="$2"
	if [ -r "$src" ]; then
		{ printf '### source: %s\n\n' "$src"; cap < "$src"; } > "$OUT/$file"
	else
		printf '### source: %s\n### UNREADABLE (permission or absent)\n' \
			"$src" > "$OUT/$file"
	fi
}

skipped() { printf '### SKIPPED: %s\n' "$1" > "$OUT/$2"; }

have() { command -v "$1" >/dev/null 2>&1; }

# --- 1. identity and machine ----------------------------------------------

{
	printf 'collector-version: 1\n'
	printf 'collected-utc: %s\n' "$STAMP"
	printf 'hostname: %s\n' "$(hostname)"
	printf 'privileged-run: %s\n' "$PRIVILEGED"
	printf 'repo-root: %s\n' "$ROOT"
	printf 'git-head: %s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"
	printf 'git-branch: %s\n' "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo none)"
} > "$OUT/00-meta.txt"

{
	printf '### DMI identity (/sys/class/dmi/id)\n\n'
	for f in sys_vendor product_name product_version board_vendor board_name \
	         bios_vendor bios_version chassis_type; do
		printf '%-16s %s\n' "$f:" "$(cat "/sys/class/dmi/id/$f" 2>/dev/null || echo '(unreadable)')"
	done
} > "$OUT/01-dmi.txt"

sec 02-uname.txt          'running kernel'                 uname -srvmo
copy 03-proc-version.txt  /proc/version
copy 04-cmdline.txt       /proc/cmdline

# --- 2. kernels, headers, build toolchain ---------------------------------

if have pacman; then
	sec 10-pkgs-kernel.txt 'installed kernel/header/toolchain packages' \
		bash -c "pacman -Q 2>/dev/null | grep -Ei '^(linux|gcc|clang|llvm|lld|dkms|base-devel)' "
	sec 11-pkgs-audio.txt 'installed audio stack packages' \
		bash -c "pacman -Q 2>/dev/null | grep -Ei 'pipewire|wireplumber|alsa|pulse|sof-firmware'"
else
	skipped 'pacman not present' 10-pkgs-kernel.txt
	skipped 'pacman not present' 11-pkgs-audio.txt
fi

KREL="$(uname -r)"
KBUILD="/lib/modules/$KREL/build"
{
	printf '### kernel build tree for %s\n\n' "$KREL"
	printf 'build path:        %s\n' "$KBUILD"
	printf 'build resolves to: %s\n' "$(readlink -f "$KBUILD" 2>/dev/null || echo '(missing)')"
	printf 'build present:     %s\n' "$([ -d "$KBUILD" ] && echo yes || echo NO)"
	printf '\n--- generated/utsrelease.h ---\n'
	cat "$KBUILD/include/generated/utsrelease.h" 2>/dev/null || echo '(absent)'
	printf '\n--- Module.symvers ---\n'
	if [ -r "$KBUILD/Module.symvers" ]; then
		printf 'present, %s bytes, %s symbols\n' \
			"$(stat -c %s "$KBUILD/Module.symvers")" \
			"$(wc -l < "$KBUILD/Module.symvers")"
	else
		printf 'ABSENT or unreadable\n'
	fi
	printf '\n--- compiler family recorded in .config ---\n'
	grep -E '^(CONFIG_CC_IS_CLANG|CONFIG_CC_IS_GCC|CONFIG_CC_VERSION_TEXT|CONFIG_CLANG_VERSION|CONFIG_GCC_VERSION|CONFIG_LD_IS_LLD|CONFIG_LD_IS_BFD|CONFIG_LTO(_[A-Z_]+)?|CONFIG_CFI[A-Z_]*|CONFIG_MODVERSIONS|CONFIG_MODULE_SIG[A-Z_]*|CONFIG_STACKPROTECTOR[A-Z_]*)=' \
		"$KBUILD/.config" 2>/dev/null || echo '(.config unreadable)'
	printf '\n--- ALSA/HDA related .config ---\n'
	grep -E '^(CONFIG_SND_HDA[A-Z_]*|CONFIG_SND_DEBUG[A-Z_]*)=|^# CONFIG_SND_DEBUG' \
		"$KBUILD/.config" 2>/dev/null || echo '(.config unreadable)'
} > "$OUT/12-kernel-build-tree.txt"

{
	printf '### host toolchain actually installed\n\n'
	for t in gcc clang ld.lld ld make dkms; do
		printf -- '--- %s ---\n' "$t"
		if have "$t"; then "$t" --version 2>&1 | head -2; else echo '(absent)'; fi
	done
} > "$OUT/13-toolchain.txt"

if have dkms; then
	sec 14-dkms-status.txt 'DKMS status' dkms status
else
	skipped 'dkms not installed' 14-dkms-status.txt
fi

# --- 3. modules ------------------------------------------------------------

sec 20-lsmod-snd.txt 'loaded sound modules' \
	bash -c "lsmod | awk 'NR==1 || /snd|hda|soundcore/'"

{
	printf '### modinfo for HDA codec modules\n'
	printf '### NOTE: modinfo describes the file on disk; a module loaded\n'
	printf '### before a package update may differ. See 22-loaded-module-identity.txt.\n\n'
	for m in snd_hda_intel snd_hda_codec snd_hda_codec_cs420x snd_hda_codec_generic; do
		printf -- '--- %s ---\n' "$m"
		modinfo "$m" 2>&1 | grep -Ev '^(signature|	)' | cap
		printf '\n'
	done
} > "$OUT/21-modinfo.txt"

{
	printf '### identity of the modules currently LOADED (from sysfs)\n\n'
	for m in snd_hda_codec_cs420x snd_hda_intel snd_hda_codec; do
		printf -- '--- %s ---\n' "$m"
		if [ -d "/sys/module/$m" ]; then
			for k in version srcversion coresize initstate refcnt taint; do
				printf '%-12s %s\n' "$k:" \
					"$(cat "/sys/module/$m/$k" 2>/dev/null || echo '(n/a)')"
			done
			if [ -d "/sys/module/$m/parameters" ]; then
				printf 'parameters:\n'
				for p in "/sys/module/$m/parameters/"*; do
					[ -r "$p" ] || continue
					printf '  %-24s %s\n' "$(basename "$p")" "$(cat "$p" 2>/dev/null)"
				done
			fi
		else
			printf '(not loaded)\n'
		fi
		printf '\n'
	done
} > "$OUT/22-loaded-module-identity.txt"

# --- 4. PCI / HDA topology -------------------------------------------------

if have lspci; then
	sec 30-lspci-audio.txt 'PCI audio controllers, numeric + kernel driver' \
		bash -c "lspci -nnvvk 2>/dev/null | awk '/Audio device|Multimedia audio/,/^$/'"
else
	skipped 'lspci not installed (pciutils)' 30-lspci-audio.txt
fi

{
	printf '### HDA controller PCI identity from sysfs\n\n'
	for d in /sys/bus/pci/drivers/snd_hda_intel/0000:*; do
		[ -d "$d" ] || continue
		printf -- '--- %s ---\n' "$(basename "$d")"
		for k in vendor device subsystem_vendor subsystem_device class revision; do
			printf '%-18s %s\n' "$k:" "$(cat "$d/$k" 2>/dev/null || echo '(n/a)')"
		done
		printf '%-18s %s\n' 'power/control:' "$(cat "$d/power/control" 2>/dev/null || echo '(n/a)')"
		printf '\n'
	done
} > "$OUT/31-hda-controller-ids.txt"

copy 32-asound-cards.txt /proc/asound/cards
copy 33-asound-modules.txt /proc/asound/modules

# Full codec dumps: the single most important piece of hardware evidence.
n=0
for c in /proc/asound/card*/codec#*; do
	[ -r "$c" ] || continue
	copy "34-codec-dump-$n.txt" "$c"
	n=$((n+1))
done
[ "$n" -gt 0 ] || skipped 'no readable /proc/asound/card*/codec#* nodes' 34-codec-dump-0.txt

{
	printf '### codec identity summary\n\n'
	for c in /proc/asound/card*/codec#*; do
		[ -r "$c" ] || continue
		printf -- '--- %s ---\n' "$c"
		grep -E '^(Codec|Address|Vendor Id|Subsystem Id|Revision Id):' "$c"
		printf '\n'
	done
} > "$OUT/35-codec-identity.txt"

# ELD presence per HDMI pin (HDMI preserved-path evidence).
{
	printf '### HDMI/DP ELD state\n\n'
	found=0
	for e in /proc/asound/card*/eld#*; do
		[ -r "$e" ] || continue
		found=1
		printf -- '--- %s ---\n' "$e"
		head -20 "$e"
		printf '\n'
	done
	[ "$found" = 1 ] || printf '(no eld# nodes present)\n'
} > "$OUT/36-hdmi-eld.txt"

# --- 5. ALSA PCM and mixer -------------------------------------------------

if have aplay; then
	sec 40-aplay-l.txt 'ALSA playback devices' aplay -l
	sec 41-arecord-l.txt 'ALSA capture devices' arecord -l
else
	skipped 'alsa-utils not installed' 40-aplay-l.txt
	skipped 'alsa-utils not installed' 41-arecord-l.txt
fi

{
	printf '### PCM nodes and their capabilities (read-only)\n\n'
	for p in /proc/asound/card*/pcm*; do
		[ -d "$p" ] || continue
		printf -- '--- %s ---\n' "$p"
		[ -r "$p/info" ] && cat "$p/info"
		for s in "$p"/sub*; do
			[ -d "$s" ] || continue
			printf '  [%s] hw_params: %s\n' "$(basename "$s")" \
				"$(cat "$s/hw_params" 2>/dev/null | tr '\n' ' ')"
		done
		printf '\n'
	done
} > "$OUT/42-pcm-nodes.txt"

if have amixer; then
	for ci in $(awk '/^ *[0-9]+ \[/{print $1}' /proc/asound/cards 2>/dev/null); do
		sec "43-amixer-contents-card$ci.txt" "full mixer contents, card $ci" \
			amixer -c "$ci" contents
		sec "44-amixer-scontents-card$ci.txt" "simple mixer contents, card $ci" \
			amixer -c "$ci" scontents
	done
else
	skipped 'alsa-utils not installed' 43-amixer-contents-card0.txt
fi

# --- 6. PipeWire / WirePlumber --------------------------------------------

if have pipewire; then
	sec 50-pipewire-version.txt 'PipeWire version' pipewire --version
else
	skipped 'pipewire not installed' 50-pipewire-version.txt
fi
if have wireplumber; then
	sec 51-wireplumber-version.txt 'WirePlumber version' wireplumber --version
else
	skipped 'wireplumber not installed' 51-wireplumber-version.txt
fi
if have wpctl; then
	sec 52-wpctl-status.txt 'WirePlumber graph and defaults' wpctl status
	sec 53-wpctl-defaults.txt 'configured default nodes' \
		bash -c 'wpctl settings --user 2>/dev/null || wpctl status 2>&1 | sed -n "/Settings/,\$p"'
else
	skipped 'wpctl not available (no session or wireplumber absent)' 52-wpctl-status.txt
fi
if have pw-dump; then
	# Node/device/route objects only; this is graph topology, not user content.
	sec 54-pw-alsa-objects.txt 'PipeWire ALSA node/device objects' \
		bash -c "pw-dump 2>/dev/null | jq -c '[.[] | select(.type==\"PipeWire:Interface:Node\" or .type==\"PipeWire:Interface:Device\") | {id, type, info: {props: (.info.props // {} | with_entries(select(.key|test(\"^(node|device|media|alsa|api|factory|object|card|priority)\\\\.\"))))}}]' 2>/dev/null || pw-dump"
else
	skipped 'pw-dump not available' 54-pw-alsa-objects.txt
fi

# --- 7. jack state, power, suspend ----------------------------------------

{
	printf '### jack / input-switch state exposed by ALSA\n\n'
	for j in /proc/asound/card*/codec#*; do
		[ -r "$j" ] || continue
		printf -- '--- pin-ctls and jack pins from %s ---\n' "$j"
		awk '/^Node 0x/{n=$0} /Pin Default|Pin-ctls|Unsolicited/{print n": "$0}' "$j" \
			| grep -Ei 'jack|Pin-ctls|Unsolicited' | head -60
		printf '\n'
	done
	printf -- '--- kernel jack input devices ---\n'
	grep -iE 'Name=.*(Headphone|Mic|HDMI|Line)' /proc/bus/input/devices 2>/dev/null \
		|| printf '(none listed)\n'
} > "$OUT/60-jack-state.txt"

{
	printf '### HDA power management state\n\n'
	printf -- '--- power_save module parameters ---\n'
	for p in /sys/module/snd_hda_intel/parameters/power_save \
	         /sys/module/snd_hda_intel/parameters/power_save_controller \
	         /sys/module/snd_hda_codec/parameters/*; do
		[ -r "$p" ] || continue
		printf '%-60s %s\n' "$p" "$(cat "$p" 2>/dev/null)"
	done
	printf '\n--- runtime PM of the HDA device ---\n'
	for d in /sys/bus/pci/drivers/snd_hda_intel/0000:*/power; do
		[ -d "$d" ] || continue
		for k in control runtime_status runtime_suspended_time; do
			printf '%-24s %s\n' "$k:" "$(cat "$d/$k" 2>/dev/null || echo '(n/a)')"
		done
	done
} > "$OUT/61-hda-power.txt"

{
	printf '### system suspend configuration\n\n'
	printf 'mem_sleep:      %s\n' "$(cat /sys/power/mem_sleep 2>/dev/null || echo '(n/a)')"
	printf 'state:          %s\n' "$(cat /sys/power/state 2>/dev/null || echo '(n/a)')"
	printf 'disk:           %s\n' "$(cat /sys/power/disk 2>/dev/null || echo '(n/a)')"
	printf '\n--- suspend statistics ---\n'
	for k in success fail last_failed_dev last_failed_step; do
		printf '%-20s %s\n' "$k:" "$(cat "/sys/power/suspend_stats/$k" 2>/dev/null || echo '(n/a)')"
	done
} > "$OUT/62-suspend.txt"

# --- 8. kernel log, scoped to audio ---------------------------------------

# Only audio-relevant lines from the current boot. Never a full journal.
if have journalctl; then
	sec 70-kernel-audio-log.txt 'current-boot kernel audio lines' \
		bash -c "journalctl -b -k --no-pager -o short-precise 2>/dev/null \
		         | grep -Ei 'snd[_-]|hda|hdaudio|cs420|cs4208|cirrus|azalia|pipewire|wireplumber' \
		         | tail -400"
else
	sec 70-kernel-audio-log.txt 'dmesg audio lines' \
		bash -c "dmesg 2>/dev/null | grep -Ei 'snd[_-]|hda|cs420|cirrus' | tail -400"
fi

# --- 9. configuration that can alter audio behaviour ----------------------

{
	printf '### packages/files that could override HDA, ALSA or PipeWire behaviour\n\n'
	for d in /etc/modprobe.d /usr/lib/modprobe.d; do
		printf -- '--- %s (snd/hda related) ---\n' "$d"
		grep -rilE 'snd|hda' "$d" 2>/dev/null | while read -r f; do
			printf '  == %s ==\n' "$f"
			grep -E 'snd|hda' "$f" 2>/dev/null | sed 's/^/     /'
		done || true
		printf '\n'
	done
	for d in /etc/pipewire /usr/share/pipewire /etc/wireplumber /usr/share/wireplumber; do
		printf -- '--- %s (file list only) ---\n' "$d"
		[ -d "$d" ] && find "$d" -type f | sort | head -60 || printf '(absent)\n'
		printf '\n'
	done
	printf -- '--- ALSA state restore units ---\n'
	systemctl list-unit-files --no-pager 2>/dev/null \
		| grep -Ei 'alsa|sound|pipewire|wireplumber' || printf '(none)\n'
} > "$OUT/80-audio-config-ownership.txt"

if have pacman; then
	sec 81-file-ownership.txt 'pacman ownership of key audio files' \
		bash -c "pacman -Qo /usr/bin/pipewire /usr/bin/wireplumber \
		         /lib/modules/$(uname -r)/kernel/sound/hda/codecs/cirrus/snd-hda-codec-cs420x.ko.zst \
		         2>&1"
else
	skipped 'pacman not present' 81-file-ownership.txt
fi

# --- 10. root-only probes --------------------------------------------------

PRIV_NOTE="$OUT/90-privileged.txt"
if [ "$PRIVILEGED" = 1 ] && [ "$(id -u)" = 0 ]; then
	{
		printf '### privileged probes (read-only)\n\n'
		printf -- '--- hda-verb / codec register readback ---\n'
		if have hda-verb; then hda-verb --help 2>&1 | head -3; else echo '(alsa-tools not installed)'; fi
		printf '\n--- dmidecode system ---\n'
		if have dmidecode; then dmidecode -t system 2>&1 | cap; else echo '(dmidecode absent)'; fi
	} > "$PRIV_NOTE"
else
	{
		printf '### SKIPPED: privileged probes not run\n'
		printf '###   --privileged given: %s\n' "$PRIVILEGED"
		printf '###   effective uid:      %s\n' "$(id -u)"
		printf '###\n'
		printf '### Nothing in this collector is known to REQUIRE root: every item\n'
		printf '### above was obtained unprivileged. This file exists so that a\n'
		printf '### later privileged need is recorded explicitly rather than assumed.\n'
	} > "$PRIV_NOTE"
fi

# --- 11. provenance --------------------------------------------------------

( cd "$OUT" && sha256sum ./*.txt | sort -k2 > SHA256SUMS )
sha256sum "$0" > "$OUT/COLLECTOR.sha256"

{
	printf 'baseline: %s\n' "$STAMP"
	printf 'files:    %s\n' "$(find "$OUT" -maxdepth 1 -name '*.txt' | wc -l)"
	printf 'bytes:    %s\n' "$(du -sb "$OUT" | cut -f1)"
} > "$OUT/ZZ-summary.txt"

# As macbook91-runner does: the state directory, so that the directories
# mkdir -p created as root belong to that user too; an explicit -o only
# the new baseline.
if [ -n "$SUDO_OWNER" ]; then
	chown -R "$SUDO_OWNER" "${CHOWN_ROOT:-$OUT}" 2>/dev/null || true
fi
printf 'baseline written to: %s\n' "$OUT"
printf 'files: %s\n' "$(find "$OUT" -maxdepth 1 -type f | wc -l)"
