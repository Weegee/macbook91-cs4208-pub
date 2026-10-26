#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Hermetic regression tests for macbook91-cs4208.
#
# Everything here runs without root, without loading a module and without
# playing sound. Anything that genuinely needs hardware is reported BLOCKED
# rather than silently skipped, so the summary never overstates coverage.
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src/cs420x-a1534"
PKG="$ROOT/packaging"
# Since 20261020.03 one tree carries a derived cs420x.c per kernel series
# (<series>/cs420x.c, upstream/<series>/cs420x.c, kheaders/<series>/). The
# source-level checks below read the 7.2 one, the series the hardware results
# were obtained on; the per-series checks in section 4f cover every series.
SERIES72=7.2
CSRC="$SRC/$SERIES72/cs420x.c"
USRC="$SRC/upstream/$SERIES72/cs420x.c"
# The PKGBUILD, .SRCINFO and the install scriptlet live in
# packaging/arch/, package() is the root Makefile's install target, and built
# packages land in dist/.
ARCHPKG="$PKG/arch"
DIST="$ROOT/dist"
PKGNAME=macbook91-cs4208-dkms
VERSION=$(cat "$ROOT/VERSION")
TOOLS="$ROOT/tools"

# The kernel half of src/cs420x-a1534/ is not tracked. It is
# reconstructed by packaging/fetch-upstream.sh from this project's own patches
# plus files fetched at a resolved kernel tag, so a fresh clone has no
# cs420x.c, no kheaders/ and no vendored/a1534_sequence.h. The tests that read
# those files would then fail for a reason that is not a defect in anything
# they test.
#
# So: try once to assemble from the local cache, without touching the network -
# this suite is hermetic and stays hermetic. If that is not possible, every
# dependent test is reported BLOCKED, by its own name, with the command that
# fixes it. None of them is silently skipped, and none is counted as a pass.
ASSEMBLE_HINT='upstream-derived sources not assembled - run: packaging/fetch-upstream.sh'
ASSEMBLED=1
LOCK_TAGS=$("$PKG/fetch-upstream.sh" --all --print-tag 2>/dev/null || true)
LOCK_SERIES=$(sed -n 's/^v\([0-9]*\.[0-9]*\).*/\1/p' <<<"$LOCK_TAGS")
[ -n "$LOCK_SERIES" ] || ASSEMBLED=0
for s in $LOCK_SERIES; do
	if [ ! -r "$SRC/$s/cs420x.c" ]; then
		"$PKG/fetch-upstream.sh" --offline >/dev/null 2>&1 || ASSEMBLED=0
		break
	fi
done

PASS=0; FAIL=0; BLOCKED=0
ok()      { printf '  PASS     %s\n' "$1"; PASS=$((PASS+1)); }
no()      { printf '  FAIL     %s\n     -> %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
# A here-string, not `printf | grep -q`: under pipefail that pipeline returns 141
# when grep -q matches before printf has written everything, which happens as
# soon as the text exceeds the pipe's capacity. A pipe can shrink to two pages
# under pipe-user-pages-soft pressure, which made the 9.6 KB systemd-sleep check
# in 7d fail once in three full runs (2026-10-15).
contains_str() { grep -q -- "$2" <<<"$1"; }
# grep C source ignoring comment lines. Checks that match their own explanatory
# comment have produced several false failures in this suite; use this instead.
#
# Deliberately not a pipeline. Under `set -o pipefail`, `grep -v file | grep -q`
# returns 141 whenever grep -q matches early enough to SIGPIPE the upstream
# grep - so a SUCCESSFUL match is reported as a failure, and only for matches
# near the top of a large file. That is the same trap this project already
# removed from the verifier, left behind here.
grep_code() {
	local body
	body=$(grep -vE '^[[:space:]]*(\*|/\*|//)' "$2") || true
	grep -qE "$1" <<<"$body"
}
blocked() { printf '  BLOCKED  %s\n     -> %s\n' "$1" "${2:-}"; BLOCKED=$((BLOCKED+1)); }
# Report, by name, tests that cannot run because the upstream-derived sources
# are not assembled. A missing generated file is not a failure of the thing
# under test, and it is not a reason to say nothing either.
gen_blocked() { local n; for n in "$@"; do blocked "$n" "$ASSEMBLE_HINT"; done; }

t() { # t NAME CMD... : pass when CMD exits 0
	local name="$1"; shift
	local out
	if out=$("$@" 2>&1); then ok "$name"; else no "$name" "${out:-exit $?}"; fi
}

echo "== 0. Suite helpers =="

# contains_str must not depend on pipe capacity: an early match in text far
# larger than any pipe buffer has to read as present.
BIGSTR="x
$(yes aaaaaaaaaaaaaaa | head -n 30000)"
if contains_str "$BIGSTR" '^x$'; then
	ok "contains_str finds an early match in text larger than a pipe"
else
	no "contains_str finds an early match in text larger than a pipe" \
	   "a present string reads as absent (SIGPIPE under pipefail)"
fi
if contains_str "$BIGSTR" '^y$'; then
	no "contains_str reports an absent string as absent" "matched nothing that is there"
else
	ok "contains_str reports an absent string as absent"
fi
unset BIGSTR

echo "== 1. Target-device matching =="

if cc -Wall -Wextra -Werror -o "$ROOT/tests/test_a1534_match" \
        "$ROOT/tests/test_a1534_match.c" 2>/dev/null; then
	if "$ROOT/tests/test_a1534_match" >/dev/null 2>&1; then
		ok "a1534_match unit tests (incl. PCI 8086:7270 + codec 106b:6500 + DMI MacBook9,1 -> A1534)"
	else
		no "a1534_match unit tests" "$("$ROOT/tests/test_a1534_match" 2>&1 | tail -5)"
	fi
else
	no "a1534_match unit tests" "compile failed"
fi

# The gate must not be reachable from the PCI subsystem id.
if grep -q 'pci' "$SRC/a1534_match.h"; then
	no "gate ignores the PCI subsystem id" "a1534_match.h mentions pci"
else
	ok "gate ignores the PCI subsystem id"
fi

echo
echo "== 2. No mainline drift =="

if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "0x10de entries keep SND_PCI_QUIRK semantics" \
	            'mainline quirk entry retained: 0x7800, "MacPro 6,1"' \
	            'mainline quirk entry retained: 0x7f00, "iMac 16,1"' \
	            "GPIO state still set via snd_hda_codec_set_gpio (replayed on resume)" \
	            "no mutation of module-global driver ops"
else
	# The four 0x10de entries are NVIDIA PCI subsystem ids; converting them to
	# codec-SSID matching breaks MacBookPro 5,3/5,5/7,1 and MacBookAir 3,1(2).
	if grep -q 'HDA_CODEC_QUIRK(0x10de' "$CSRC"; then
		no "0x10de entries keep SND_PCI_QUIRK semantics" "found HDA_CODEC_QUIRK(0x10de...)"
	else
		ok "0x10de entries keep SND_PCI_QUIRK semantics"
	fi

	for entry in '0x7800, "MacPro 6,1"' '0x7f00, "iMac 16,1"'; do
		if grep -qF "$entry" "$CSRC"; then
			ok "mainline quirk entry retained: $entry"
		else
			no "mainline quirk entry retained: $entry" "missing from cs4208_mac_fixup_tbl"
		fi
	done

	# The PM-aware GPIO helper must not be replaced by raw verb writes.
	if grep -q 'snd_hda_codec_set_gpio' "$CSRC"; then
		ok "GPIO state still set via snd_hda_codec_set_gpio (replayed on resume)"
	else
		no "GPIO state still set via snd_hda_codec_set_gpio" "helper is gone"
	fi

	# Driver-global ops must never be reassigned from a per-codec probe.
	# Match an actual assignment, not the comment that explains why we avoid one.
	if grep -qE 'hda_codec_to_driver\([^)]*\)->ops[[:space:]]*=' "$CSRC"; then
		no "no mutation of module-global driver ops" "cs420x.c assigns hda_codec_to_driver(codec)->ops"
	else
		ok "no mutation of module-global driver ops"
	fi
fi

# A private kernel struct must not be copied into the module.
if grep -rq 'struct hda_cvt_setup {' "$SRC/a1534_pcm.h" 2>/dev/null; then
	no "no copy of private struct hda_cvt_setup" "found in a1534_pcm.h"
else
	ok "no copy of private struct hda_cvt_setup"
fi

if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "A1534 paths are gated on spec->is_a1534"
else
	# Every A1534 code path must be gated.
	if grep -q 'spec->is_a1534' "$CSRC" && grep -q 'cs4208_is_a1534' "$CSRC"; then
		ok "A1534 paths are gated on spec->is_a1534"
	else
		no "A1534 paths are gated on spec->is_a1534" "gate not wired"
	fi
fi

echo
echo "== 3. Speaker path correctness =="

# The PCM must bind to converter 0x0a, not 0x04 (which the bring-up powers off).
if grep -q '#define A1534_SPEAKER_DAC[[:space:]]*0x0a' "$SRC/a1534_pcm.h"; then
	ok "speaker PCM binds converter 0x0a"
else
	no "speaker PCM binds converter 0x0a" "A1534_SPEAKER_DAC is not 0x0a"
fi
if grep -qE '\.nid = A1534_SPEAKER_DAC' "$SRC/a1534_pcm.h"; then
	ok "playback stream nid is the speaker converter"
else
	no "playback stream nid is the speaker converter" "hda_pcm_stream.nid not set to A1534_SPEAKER_DAC"
fi

# Four channels, not eight: the extra TDM slot mapping is unproven.
if grep -qE '\.channels_max = 4' "$SRC/a1534_pcm.h"; then
	ok "channels_max is 4, not the unproven 8"
else
	no "channels_max is 4, not the unproven 8" "unexpected channels_max"
fi

# The speaker path must run at four channels: a stereo PCM lets PipeWire
# settle on "Analog Stereo" and the TDM amplifier slots stay silent, which is
# what kept the speakers quiet in an early build.
if grep -qE '\.channels_min = 4' "$SRC/a1534_pcm.h" && \
   grep -qE '\.channels_max = 4' "$SRC/a1534_pcm.h"; then
	ok "speaker PCM is fixed at 4 channels"
else
	no "speaker PCM is fixed at 4 channels" "a stereo PCM cannot feed the four TDM amplifier slots"
fi

# Headphones share the stream, so only the channel nibble may be rewritten -
# rate and depth must stay exactly as negotiated.
if grep -q 'a1534_format_for' "$SRC/a1534_pcm.h" && \
   grep -qE 'format & ~0xfu\) \| 1u' "$SRC/a1534_pcm.h"; then
	ok "headphone format rewrites only the channel count"
else
	no "headphone format rewrites only the channel count" "a1534_format_for() missing or altered"
fi

# 44.1 kHz only: measured on the test machine, 48 kHz is audibly distorted because the
# TAS5758L amplifiers are clocked from the codec and only track the rate the
# bring-up programs (format 0x4013).
if grep -qE '\.rates = SNDRV_PCM_RATE_44100,?$' "$SRC/a1534_pcm.h"; then
	ok "speaker PCM is restricted to 44.1 kHz"
else
	no "speaker PCM is restricted to 44.1 kHz" \
	   "48 kHz is distorted on this hardware and PipeWire defaults to it"
fi

# Stereo must reach both speaker pairs, and with a verbatim copy rather than a
# synthesised pseudo-surround.
if grep -q 'channelmix.upmix-method = simple' "$SRC/contrib/wireplumber/51-macbook91-cs4208.conf"; then
	ok "stereo is upmixed to both speaker pairs with the simple method"
else
	no "stereo is upmixed to both speaker pairs with the simple method" \
	   "without it stereo content reaches only two of the four amplifiers"
fi

# Resume must not depend on PM event codes: deep sleep resets this codec and
# an earlier build's power_state check skipped the replay exactly when it was needed.
# Match code, not the comment that explains why we avoid it: C comment lines
# start with whitespace then '*' or '/*'. (This is the fourth time a check of
# mine matched its own explanatory comment - hence the shared helper below.)
if grep -vE '^[[:space:]]*(\*|/\*|//)' "$SRC/a1534_pcm.h" | grep -q 'power_state.event'; then
	no "resume replay does not key off power_state.event" \
	   "power_state is reset to PMSG_ON by the core and is not a reliable signal"
else
	ok "resume replay does not key off power_state.event"
fi
if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "bring-up validity is cleared on suspend and replayed on resume" \
	            "driver hooks .suspend to invalidate the bring-up"
else
	if grep -q 'bringup_valid' "$SRC/a1534_pcm.h" && grep -q 'bringup_valid = 0' "$CSRC"; then
		ok "bring-up validity is cleared on suspend and replayed on resume"
	else
		no "bring-up validity is cleared on suspend and replayed on resume" \
		   "the A1534 configuration would stay lost after a deep sleep"
	fi
	if grep -qE '\.suspend = cs_suspend' "$CSRC"; then
		ok "driver hooks .suspend to invalidate the bring-up"
	else
		no "driver hooks .suspend to invalidate the bring-up" "no suspend hook registered"
	fi
fi

# NOTE: two checks here previously asserted that the resume path must issue an
# HDA Function Reset before replaying the bring-up. They encoded an early
# hypothesis, which hardware measurement then disproved - the reset takes
# effect and changes nothing, and a full re-probe does not help either. They
# were removed because the design they tested was wrong, not to make an
# implementation pass; the replacement checks above assert the behaviour that
# the measurements actually support.
# The tone generator must not spew a traceback when aplay exits early.
if grep -q 'BrokenPipeError' "$TOOLS/macbook91-audio-verify"; then
	ok "tone generator handles a reader that exits early"
else
	no "tone generator handles a reader that exits early" \
	   "prints a Python traceback in the middle of a listening test"
fi

# A deep suspend loses configuration the driver cannot reproduce. Proven by
# measurement, so the resume path must not burn ~1700 verbs pretending
# otherwise, and must say what happened.
if grep_code 'config_lost_reported' "$SRC/a1534_pcm.h"; then
	ok "resume reports lost configuration once instead of replaying futilely"
else
	no "resume reports lost configuration once instead of replaying futilely" \
	   "a full re-probe was measured not to restore it"
fi
if grep_code 'AC_VERB_SET_CODEC_RESET' "$SRC/a1534_pcm.h"; then
	no "the ineffective codec reset was removed" \
	   "measured not to help, and a reset on resume is a needless risk"
else
	ok "the ineffective codec reset was removed"
fi
# The verifier must name this state rather than reporting bare silence.
if grep -q 'speaker configuration present' "$TOOLS/macbook91-audio-verify"; then
	ok "verifier names the lost-configuration state"
else
	no "verifier names the lost-configuration state" \
	   "it would surface as an unexplained 'no sound'"
fi
# The limitation must be documented where a user will find it.
#
# This checks the substance, not a heading string. It used to grep for the
# exact title "Known limitation: deep suspend", which broke when a release
# retitled the section to say a recovery is now attempted. The requirement
# was never the title: it is that the README has a deep-suspend section and
# tells the user audio returns on reboot.
if grep -qi 'deep suspend' "$SRC/README.md" && grep -qi 'reboot' "$SRC/README.md"; then
	ok "deep-suspend limitation is documented in the README"
else
	no "deep-suspend limitation is documented in the README" "users need to know audio returns on reboot"
fi

# The negotiated format must be used, never the trace's hardcoded one.
if grep -q 'st->format' "$SRC/a1534_pcm.h" && ! grep -qE 'setup_stream\(codec, [^,]+, [^,]+, 0, 0x40' "$SRC/a1534_pcm.h"; then
	ok "streams use the negotiated format, not a hardcoded 0x4013/0x4011"
else
	no "streams use the negotiated format" "hardcoded format found"
fi

# Jack changes must be serialised against prepare/cleanup.
if grep -q 'mutex_lock(&st->lock)' "$SRC/a1534_pcm.h"; then
	ok "jack changes serialised against prepare/cleanup"
else
	no "jack changes serialised against prepare/cleanup" "no locking found"
fi

# Locking rule that prevents the codec wedge of the first test build.
if python3 "$ROOT/tests/test_lock_discipline.py" >/dev/null 2>&1; then
	ok "no PM-triggering call runs under st->lock (deadlock guard)"
else
	no "no PM-triggering call runs under st->lock" \
	   "$(python3 "$ROOT/tests/test_lock_discipline.py" 2>&1 | head -4)"
fi

# The checker itself, against mutated copies: a PM call on the fall-through
# path of an early unlock, and a scoped guard it cannot follow.
LOCKMUT=$(mktemp -d)
python3 -B - "$SRC/a1534_pcm.h" "$LOCKMUT" <<'LOCKMUT_PY'
import sys
src = open(sys.argv[1]).read()
anchor = "\t\tgoto out;\n\t}\n\tst->hp = hp;\n"
if src.count(anchor) == 1:
    open(sys.argv[2] + "/early.h", "w").write(
        src.replace(anchor, anchor + "\tsnd_hda_jack_detect(codec, A1534_HP_PIN);\n"))
    open(sys.argv[2] + "/guard.h", "w").write(
        src.replace(anchor, anchor + "\tguard(mutex)(&st->lock);\n"))
    open(sys.argv[2] + "/nested.h", "w").write(
        src.replace(anchor, anchor + "\tmutex_lock(&codec->bus->prepare_mutex);\n"
                    "\tmutex_unlock(&codec->bus->prepare_mutex);\n"))
resync = ("\tmutex_lock(&codec->bus->prepare_mutex);\n\ta1534_capture_resync(codec);\n"
          "\tmutex_unlock(&codec->bus->prepare_mutex);\n")
if src.count(resync) == 1:
    open(sys.argv[2] + "/unlocked.h", "w").write(
        src.replace(resync, "\ta1534_capture_resync(codec);\n"))
LOCKMUT_PY
if [ ! -s "$LOCKMUT/early.h" ]; then
	no "the lock check sees a PM call after an early unlock" "mutation anchor not found once in a1534_pcm.h"
elif python3 -B "$ROOT/tests/test_lock_discipline.py" "$LOCKMUT/early.h" >/dev/null 2>&1; then
	no "the lock check sees a PM call after an early unlock" "it passed a mutated copy"
else
	ok "the lock check sees a PM call after an early unlock"
fi
if [ -s "$LOCKMUT/guard.h" ] &&
   ! python3 -B "$ROOT/tests/test_lock_discipline.py" "$LOCKMUT/guard.h" >/dev/null 2>&1; then
	ok "the lock check refuses guard()-style locking it cannot follow"
else
	no "the lock check refuses guard()-style locking it cannot follow" "it passed a copy using guard(mutex)"
fi
if [ ! -s "$LOCKMUT/nested.h" ]; then
	no "the lock check refuses prepare_mutex under st->lock" "mutation anchor not found once in a1534_pcm.h"
elif python3 -B "$ROOT/tests/test_lock_discipline.py" "$LOCKMUT/nested.h" >/dev/null 2>&1; then
	no "the lock check refuses prepare_mutex under st->lock" "it passed a copy taking prepare_mutex inside st->lock"
else
	ok "the lock check refuses prepare_mutex under st->lock"
fi
if [ ! -s "$LOCKMUT/unlocked.h" ]; then
	no "the lock check refuses a capture resync without prepare_mutex" "resync block not found once in a1534_pcm.h"
elif python3 -B "$ROOT/tests/test_lock_discipline.py" "$LOCKMUT/unlocked.h" >/dev/null 2>&1; then
	no "the lock check refuses a capture resync without prepare_mutex" "it passed a copy calling the resync unlocked"
else
	ok "the lock check refuses a capture resync without prepare_mutex"
fi
rm -rf "$LOCKMUT"

# A headphone plug replays headphones_a1534(), whose AFG D3 cycles reset the
# running capture's converter stream tag (docs/INCIDENT-20261019.md). The core
# writes a converter only when its cached tag or format differ, so the driver
# has to re-program it itself: after the replay, and on every capture prepare.
RESYNC_BODY=$(awk '/^static void a1534_capture_resync\(/,/^}/' "$SRC/a1534_pcm.h")
if grep -qF -- 'lockdep_assert_held(&codec->bus->prepare_mutex);' <<<"$RESYNC_BODY" &&
   grep -qF -- '__snd_hda_codec_cleanup_stream(codec, adc, 1);' <<<"$RESYNC_BODY" &&
   grep -qF -- 'snd_hda_codec_setup_stream(codec, adc, spec->gen.cur_adc_stream_tag, 0,' <<<"$RESYNC_BODY"; then
	ok "capture resync forgets the cached converter state before setting it up again"
else
	no "capture resync forgets the cached converter state before setting it up again" \
	   "a1534_capture_resync() needs the prepare_mutex assertion, a do_now cleanup and a setup of cur_adc"
fi
JACK_BODY=$(awk '/^static void a1534_hp_jack_callback\(/,/^}/' "$SRC/a1534_pcm.h")
L_REPLAY=$(grep -nF 'headphones_a1534(codec);' <<<"$JACK_BODY" | head -1 | cut -d: -f1)
L_PLOCK=$(grep -nF 'mutex_lock(&codec->bus->prepare_mutex);' <<<"$JACK_BODY" | head -1 | cut -d: -f1)
L_RESYNC=$(grep -nF 'a1534_capture_resync(codec);' <<<"$JACK_BODY" | head -1 | cut -d: -f1)
L_PUNLOCK=$(grep -nF 'mutex_unlock(&codec->bus->prepare_mutex);' <<<"$JACK_BODY" | head -1 | cut -d: -f1)
L_OUT=$(grep -n '^out:' <<<"$JACK_BODY" | head -1 | cut -d: -f1)
if [ -n "$L_REPLAY" ] && [ -n "$L_PLOCK" ] && [ -n "$L_RESYNC" ] && [ -n "$L_PUNLOCK" ] &&
   [ -n "$L_OUT" ] && [ "$L_REPLAY" -lt "$L_PLOCK" ] && [ "$L_PLOCK" -lt "$L_RESYNC" ] &&
   [ "$L_RESYNC" -lt "$L_PUNLOCK" ] && [ "$L_PUNLOCK" -lt "$L_OUT" ]; then
	ok "the headphone jack callback resyncs the capture converter after the replay"
else
	no "the headphone jack callback resyncs the capture converter after the replay" \
	   "replay ${L_REPLAY:-none}, lock ${L_PLOCK:-none}, resync ${L_RESYNC:-none}, unlock ${L_PUNLOCK:-none}, out ${L_OUT:-none}"
fi
HOOK_BODY=$(awk '/^static void a1534_capture_hook\(/,/^}/' "$SRC/a1534_pcm.h")
PCMS_BODY=$(awk '/^static int a1534_build_pcms\(/,/^}/' "$SRC/a1534_pcm.h")
if grep -qF -- 'HDA_GEN_PCM_ACT_PREPARE' <<<"$HOOK_BODY" &&
   grep -qF -- 'a1534_capture_resync(codec);' <<<"$HOOK_BODY" &&
   grep -qF -- 'spec->gen.pcm_capture_hook = a1534_capture_hook;' <<<"$PCMS_BODY"; then
	ok "every capture prepare re-programs the capture converter"
else
	no "every capture prepare re-programs the capture converter" \
	   "a1534_build_pcms() must install a1534_capture_hook, which resyncs on HDA_GEN_PCM_ACT_PREPARE"
fi
unset RESYNC_BODY JACK_BODY HOOK_BODY PCMS_BODY L_REPLAY L_PLOCK L_RESYNC L_PUNLOCK L_OUT

if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "firmware snapshot gated on the intact marker"
else
	# The firmware snapshot is only meaningful while the firmware state is still
	# intact. Capturing the post-suspend reset state would let the resume path
	# "restore" the very values that produce silence.
	if grep_code 'a1534_pin1d_cfg\(codec\) == A1534_PIN1D_CFG_BRINGUP' "$CSRC"; then
		ok "firmware snapshot gated on the intact marker"
	else
		no "firmware snapshot gated on the intact marker" \
		   "a1534_snapshot_take() would capture a reset codec"
	fi
fi

# The restore must never run against an unpopulated snapshot.
if grep_code 'spec->a1534_snap\.valid' "$SRC/a1534_pcm.h"; then
	ok "restore requires a populated snapshot"
else
	no "restore requires a populated snapshot" "restore is not gated on .valid"
fi

# The restore is a recovery path, not a boot path: it may only run once the
# marker says the firmware state is already gone.
if grep_code 'if \(cfg != A1534_PIN1D_CFG_BRINGUP\)' "$SRC/a1534_pcm.h"; then
	ok "restore runs only in the already-broken state"
else
	no "restore runs only in the already-broken state" \
	   "the cold-boot path must not be touched"
fi

# The restore must never compare against a live read on the resume path. The
# regmap answers GET_PROC_COEF from cache while the codec is still cache-only
# during resume, which is what made an earlier build write garbage. Write the probe-time
# snapshot unconditionally instead.
RESTORE_BODY=$(awk '/^static int a1534_snapshot_restore/,/^}/' "$SRC/a1534_snapshot.h")
if [ -z "$RESTORE_BODY" ]; then
	no "restore does not read back on the resume path" \
	   "a1534_snapshot_restore() not found in a1534_snapshot.h; this check would pass on nothing"
elif printf '%s\n' "$RESTORE_BODY" | grep -vE '^[[:space:]]*(\*|/\*|//)' |
     grep -qE 'cs_vendor_coef_get|snd_hda_codec_read'; then
	no "restore does not read back on the resume path" \
	   "a resume-time coefficient read is answered from a stale cache"
else
	ok "restore does not read back on the resume path"
fi

# The amplifiers sit on a 64-bit-clock TDM frame - four slots of sixteen bits -
# so the speaker PCM must offer 16-bit only. Leaving formats unset let
# set_pcm_default_values() advertise S32_LE from the converter's 24-bit
# capability, and PipeWire picked it after a resume: converter 0x0a went
# 0x4013 -> 0x4033 and the speakers went silent.
if grep_code 'formats = SNDRV_PCM_FMTBIT_S16_LE' "$SRC/a1534_pcm.h" &&
   grep_code 'maxbps = 16' "$SRC/a1534_pcm.h"; then
	ok "speaker PCM is 16-bit only (TDM frame is 4 x 16 bits)"
else
	no "speaker PCM is 16-bit only (TDM frame is 4 x 16 bits)" \
	   "a 24-bit sample does not fit SRMultiple = 64"
fi

# Apple's AppleHDAWidgetCS4208::performPowerRailRestore() re-issues exactly
# three verbs on node 0x24 after a power-rail loss. They are vendor-private,
# the HDA regmap does not know they exist, and nothing in Linux has ever saved
# them. The snapshot must carry all three.
if grep_code '0x708' "$SRC/a1534_snapshot.h" && grep_code '0x7f0' "$SRC/a1534_snapshot.h" &&
   grep_code '0x7f1' "$SRC/a1534_snapshot.h"; then
	ok "snapshot carries the verbs Apple restores after a rail loss"
else
	no "snapshot carries the verbs Apple restores after a rail loss" \
	   "see docs/AMPLIFIER-PROTOCOL.md and performPowerRailRestore"
fi

# The full read-only dump settled this: in the WORKING state pins 0x15/0x16 and
# 0x1a-0x1c really do read 0x400000f0 while the microphone works. Restoring the
# captured configuration defaults reproduces the working state; it was the
# saved ALSA mixer state, not these writes, that muted capture.
if grep_code 'AC_VERB_SET_CONFIG_DEFAULT_BYTES_0' "$SRC/a1534_snapshot.h"; then
	ok "snapshot restores the captured pin configuration defaults"
else
	no "snapshot restores the captured pin configuration defaults" \
	   "all 19 pins differ across S3; the working state is the captured one"
fi

# Writing to amplifiers over a bus that is not answering must not be the default.
if grep_code 'static bool a1534_amp;' "$SRC/a1534_i2c.h" &&
   grep_code 'if \(!a1534_amp\)' "$SRC/a1534_i2c.h"; then
	ok "amplifier bring-up is opt-in while the transport is unproven"
else
	no "amplifier bring-up is opt-in while the transport is unproven" \
	   "0 of 4 amplifiers verified on the test machine; it must not run by default"
fi

# The amplifier bring-up values are recovered from AppleHDA, not invented.
# Guard the transport constants and the register table against edits: a wrong
# value here is written straight into four amplifiers.
if grep_code 'A1534_COEF_I2C_ADDR\s+0x14' "$SRC/a1534_i2c.h" &&
   grep_code 'A1534_COEF_I2C_DATA\s+0x15' "$SRC/a1534_i2c.h" &&
   grep_code 'A1534_COEF_I2C_CTRL\s+0x16' "$SRC/a1534_i2c.h" &&
   grep_code 'A1534_COEF_I2C_STATUS\s+0x17' "$SRC/a1534_i2c.h"; then
	ok "CS4208 I2C coefficient map matches AppleHDA"
else
	no "CS4208 I2C coefficient map matches AppleHDA" \
	   "see docs/AMPLIFIER-PROTOCOL.md §2"
fi
if [ "$(grep -cE '^[[:space:]]*\{ 0x[0-9a-f]{2}, 0x[0-9a-f]{2},' "$SRC/a1534_i2c.h")" = 8 ] &&
   grep_code '0x03, 0x80, true' "$SRC/a1534_i2c.h" &&
   grep_code '0x08, 0x10, false, false' "$SRC/a1534_i2c.h"; then
	ok "TAS5758L register table is the 8 entries AppleHDA writes"
else
	no "TAS5758L register table is the 8 entries AppleHDA writes" \
	   "see docs/AMPLIFIER-PROTOCOL.md §3"
fi
# The four amplifier addresses and slots come from AppleHDA layouts 121/127/129.
if grep_code '0x6c, 0' "$SRC/a1534_i2c.h" && grep_code '0x6d, 1' "$SRC/a1534_i2c.h" &&
   grep_code '0x6e, 0' "$SRC/a1534_i2c.h" && grep_code '0x6f, 1' "$SRC/a1534_i2c.h"; then
	ok "amplifier addresses and TDM slots match AppleHDA layouts"
else
	no "amplifier addresses and TDM slots match AppleHDA layouts" \
	   "see docs/AMPLIFIER-PROTOCOL.md §4"
fi

if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "A1534 GPIO mask overrides the mainline gpio0 fixup"
else
	# The amplifier supply GPIOs must survive cs4208_fixup_gpio0() narrowing the
	# mask to bit 0, which is what silenced the speakers in the first test build.
	if grep -q 'spec->gpio_mask = A1534_GPIO_MASK' "$CSRC"; then
		ok "A1534 GPIO mask overrides the mainline gpio0 fixup"
	else
		no "A1534 GPIO mask overrides the mainline gpio0 fixup" \
		   "cs_init() would write mask 0x01 and disable the amplifier DFETs"
	fi
fi

echo
echo "== 4. Source provenance =="

if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "vendored kernel sources match UPSTREAM.sha256" \
	            "vendored A1534 sequence matches PROVENANCE.sha256" \
	            "local-changes.patch matches the real delta" \
	            "a1534_sequence.patch matches the real delta" \
	            "vendored trace verb count unchanged"
else
	t "vendored kernel sources match UPSTREAM.sha256" \
	  bash -c "cd '$SRC' && sha256sum -c UPSTREAM.sha256"
	t "vendored A1534 sequence matches PROVENANCE.sha256" \
	  bash -c "cd '$SRC/vendored' && sha256sum -c PROVENANCE.sha256"

	# The recorded patch must actually describe the delta.
	patch_body() { grep -v '^\(---\|+++\) ' "$1"; }
	if diff -q <(diff -u "$USRC" "$CSRC" | grep -v '^\(---\|+++\) ') \
	           <(patch_body "$SRC/local-changes.patch") >/dev/null 2>&1; then
		ok "local-changes.patch matches the real delta"
	else
		no "local-changes.patch matches the real delta" "regenerate it"
	fi
	if diff -q <(diff -u "$SRC/vendored/ORIGINAL-a1534_sequence.h" "$SRC/vendored/a1534_sequence.h" | grep -v '^\(---\|+++\) ') \
	           <(patch_body "$SRC/vendored/a1534_sequence.patch") >/dev/null 2>&1; then
		ok "a1534_sequence.patch matches the real delta"
	else
		no "a1534_sequence.patch matches the real delta" "regenerate it"
	fi

	# No verb may have been altered in the vendored trace.
	ORIG_VERBS=$(grep -c 'snd_hda_codec_write\|snd_hda_codec_read_check' "$SRC/vendored/ORIGINAL-a1534_sequence.h")
	NOW_VERBS=$(grep -c 'snd_hda_codec_write\|snd_hda_codec_read_check' "$SRC/vendored/a1534_sequence.h")
	if [ "$ORIG_VERBS" = "$NOW_VERBS" ]; then
		ok "vendored trace verb count unchanged ($NOW_VERBS)"
	else
		no "vendored trace verb count unchanged" "was $ORIG_VERBS, now $NOW_VERBS"
	fi
fi

# Finding 7 (Ultrareview): LOCAL-CHANGES.md claimed "51 added, 2 removed lines"
# while local-changes.patch measured 270 added and 3 removed. The counts were
# hand-maintained, never regenerated after the PCM layer and the ops
# dispatchers landed, and nothing recomputed them - so they drifted quietly for
# as long as nobody counted.
#
# Recompute from the patch and compare. Both files are tracked, so unlike the
# reproduction test above this one is not gated on the assembled tree: it runs
# in a fresh clone.
PATCH_ADDED=$(grep '^+' "$SRC/local-changes.patch" | grep -vc '^+++' || true)
PATCH_REMOVED=$(grep '^-' "$SRC/local-changes.patch" | grep -vc '^---' || true)
# The claim is prose and may be wrapped across lines, so match it with the
# newlines folded out rather than line by line.
PATCH_CLAIMED=$(tr '\n' ' ' < "$SRC/LOCAL-CHANGES.md" |
	grep -oE '\([0-9]+ added, [0-9]+ removed lines\)' | head -1)
PATCH_MEASURED="($PATCH_ADDED added, $PATCH_REMOVED removed lines)"
if [ -z "$PATCH_CLAIMED" ]; then
	no "LOCAL-CHANGES.md states the patch's real line counts" \
	   "LOCAL-CHANGES.md no longer states a count in the form (N added, N removed lines)"
elif [ "$PATCH_CLAIMED" = "$PATCH_MEASURED" ]; then
	ok "LOCAL-CHANGES.md states the patch's real line counts $PATCH_MEASURED"
else
	no "LOCAL-CHANGES.md states the patch's real line counts" \
	   "LOCAL-CHANGES.md says $PATCH_CLAIMED, local-changes.patch measures $PATCH_MEASURED"
fi

echo "== 4b. Release promotion completeness =="

# F-14: .SRCINFO was missing from thirteen
# consecutive early releases because nothing ever checked for it. Every promoted
# release directory must carry all seven expected files and its own SHA256SUMS
# must verify - this is what makes that omission impossible to repeat.
#
# The source tarball is cs420x-a1534.tar.zst in early releases and the
# reproducible NAME-VERSION.tar since; promoted releases are not rewritten, so
# the expectation follows the directory.
for rd in "$ROOT"/release/*/; do
	rv=$(basename "$rd")
	if [ -e "$rd/cs420x-a1534.tar.zst" ]; then
		RELEASE_SRC=cs420x-a1534.tar.zst
	else
		RELEASE_SRC="$PKGNAME-$rv.tar"
	fi
	RELEASE_EXPECTED="PKGBUILD .SRCINFO SHA256SUMS STATUS.txt $RELEASE_SRC macbook91-cs4208.install upstream.lock"
	MISSING=""
	for f in $RELEASE_EXPECTED; do
		[ -e "$rd/$f" ] || MISSING="$MISSING $f"
	done
	if [ -n "$MISSING" ]; then
		no "release/$rv carries all expected files" "missing:$MISSING"
	else
		ok "release/$rv carries all expected files"
	fi
	# What matters is that a FRESH CLONE can verify this directory, so both
	# checks below are framed in terms of the tracked files - not what
	# happens to be on the builder's disk.
	#
	# Two early releases were sealed while SHA256SUMS still named the built
	# .pkg.tar.zst, which is gitignored. `sha256sum -c` therefore passed only
	# where the package had been built and failed everywhere else. Those two
	# directories are published artifacts and are not rewritten; the rows for
	# files a clone does not have are skipped instead. promote-release.sh
	# writes no such row.
	# git is the accurate answer, but this suite also runs from a plain
	# export of the release candidate, which is not a checkout. There the
	# expected list IS the tracked list - that is what §4b asserts two
	# checks earlier - so fall back to it rather than reporting "no tracked
	# row" for a tree that is perfectly fine.
	TRACKED=$(git -C "$ROOT" ls-files -- "release/$rv" 2>/dev/null \
		| xargs -r -n1 basename | tr '\n' ' ')
	if [ -z "${TRACKED// /}" ]; then
		TRACKED=$(printf '%s ' $RELEASE_EXPECTED)
	fi
	SUMS_SUBSET=$(mktemp)
	while read -r sum f; do
		case " $TRACKED " in *" $f "*) printf '%s  %s\n' "$sum" "$f" ;; esac
	done < "$rd/SHA256SUMS" > "$SUMS_SUBSET"
	if [ ! -s "$SUMS_SUBSET" ]; then
		no "release/$rv SHA256SUMS verifies against the tracked files" "no tracked row"
	elif (cd "$rd" && sha256sum -c "$SUMS_SUBSET" >/dev/null 2>&1); then
		ok "release/$rv SHA256SUMS verifies against the tracked files"
	else
		no "release/$rv SHA256SUMS verifies against the tracked files" \
		   "$(cd "$rd" && sha256sum -c "$SUMS_SUBSET" 2>&1 | grep -v ': OK$' | head -3)"
	fi
	rm -f "$SUMS_SUBSET"

	# V-05: an early release carried STATUS.txt on disk with no row for it in
	# SHA256SUMS - the check above only verifies the rows that exist, so it
	# cannot see one that is missing entirely.
	UNLISTED=""
	for f in $TRACKED; do
		[ "$f" = SHA256SUMS ] && continue
		grep -q -- "  $f\$" "$rd/SHA256SUMS" 2>/dev/null || UNLISTED="$UNLISTED $f"
	done
	if [ -n "$UNLISTED" ]; then
		no "release/$rv SHA256SUMS lists every tracked file" "unlisted:$UNLISTED"
	else
		ok "release/$rv SHA256SUMS lists every tracked file"
	fi

	# The files of this directory are what a release publishes. Anything else
	# on the disk of the machine that built it - above all the built package,
	# whose .BUILDINFO records the builder's directories and its installed
	# packages - must stay out of it. promote-release.sh copies no package.
	STRAY=""
	while IFS= read -r f; do
		case " $TRACKED $RELEASE_EXPECTED upstream.lock " in
			*" $f "*) ;;
			*) STRAY="$STRAY $f" ;;
		esac
	done < <(find "$rd" -mindepth 1 -maxdepth 1 -printf '%f\n')
	if [ -z "$STRAY" ]; then
		ok "release/$rv holds no file the repository does not track"
	else
		no "release/$rv holds no file the repository does not track" "stray:$STRAY"
	fi
done

# Retention. STRUCTURE.md keeps the current release and the one before it;
# older ones are removed. That rule was enforced by memory
# for twenty releases and then by hand once, which is precisely the pattern
# this suite exists to end - promote-release.sh prunes now, and this is the
# check that says it happened.
RELEASE_TRACKED=$(git -C "$ROOT" ls-files -- release | cut -d/ -f2 | sort -u)
RELEASE_COUNT=$(printf '%s\n' "$RELEASE_TRACKED" | grep -c . || true)
if [ "$RELEASE_COUNT" -le 2 ]; then
	ok "release/ retains at most the current release and the one before it"
else
	no "release/ retains at most the current release and the one before it" \
	   "$RELEASE_COUNT tracked: $(printf '%s' "$RELEASE_TRACKED" | tr '\n' ' ')"
fi

# V-03. In early releases the PKGBUILD's sha256sums were a formality:
# `tar -caf ... .zst` is not byte-reproducible, so make-package.sh regenerated
# them at every build and this section compared tarball *content* with the
# tracked source instead. packaging/mkdist.py writes the same bytes from the
# same inputs, so the checksum is pinned at release time and these checks say
# what that rests on.
PB="$ARCHPKG/PKGBUILD"
if [ "$(sed -n 's/^pkgver=//p' "$PB")" = "$VERSION" ]; then
	ok "PKGBUILD pkgver matches VERSION ($VERSION)"
else
	no "PKGBUILD pkgver matches VERSION" "pkgver=$(sed -n 's/^pkgver=//p' "$PB"), VERSION=$VERSION"
fi
# shellcheck disable=SC2016 # literal PKGBUILD text
if grep -qxF 'source=("$pkgname-$pkgver.tar")' "$PB" \
   && grep -qF 'make PREFIX=/usr DESTDIR="$pkgdir" install' "$PB"; then
	ok "PKGBUILD builds from the source tarball with make install"
else
	no "PKGBUILD builds from the source tarball with make install" \
	   "source= or package() no longer follows the pinned-tarball layout"
fi
# $startdir is deprecated (PKGBUILD(5)) and reaches outside the tarball the
# checksum covers.
if grep -v '^[[:space:]]*#' "$PB" | grep -qF 'startdir'; then
	no "PKGBUILD does not reach outside its sources" "\$startdir is used"
else
	ok "PKGBUILD does not reach outside its sources"
fi

if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "the source tarball is byte-reproducible"
else
	REPRO=$(mktemp -d)
	if python3 "$PKG/mkdist.py" --allow-dirty --out "$REPRO/a" >/dev/null 2>&1 \
	   && python3 "$PKG/mkdist.py" --allow-dirty --out "$REPRO/b" >/dev/null 2>&1 \
	   && cmp -s "$REPRO/a/$PKGNAME-$VERSION.tar" "$REPRO/b/$PKGNAME-$VERSION.tar"; then
		ok "the source tarball is byte-reproducible"
	else
		no "the source tarball is byte-reproducible" \
		   "$(python3 "$PKG/mkdist.py" --allow-dirty --out "$REPRO/c" 2>&1 | tail -1)"
	fi
	rm -rf "$REPRO"
fi

# The pin can only be checked while it is current: in a clean tree where no
# tarball input (packaging/mkdist.py's list, and the lockfile, fetcher and
# mkdist.py, which decide the generated half) changed since the commit that last
# changed the PKGBUILD. Otherwise a stale pin is expected - the next release
# re-pins - and `make arch-pkg` refuses it anyway.
PIN=$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" "$PB")
PIN_COMMIT=$(git -C "$ROOT" log -1 --format=%H -- packaging/arch/PKGBUILD 2>/dev/null || true)
if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "the PKGBUILD pins the tarball of its own commit"
elif [ -z "$PIN_COMMIT" ] || [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ] \
     || ! git -C "$ROOT" diff --quiet "$PIN_COMMIT" HEAD -- \
          src/cs420x-a1534 tools/macbook91-audio-verify Makefile VERSION LICENSE \
          LICENSES/GPL-2.0-only.txt LICENSES/GPL-2.0-or-later.txt LICENSES/LGPL-2.1-or-later.txt \
          packaging/upstream.lock packaging/fetch-upstream.sh packaging/mkdist.py; then
	blocked "the PKGBUILD pins the tarball of its own commit" \
	        "only checkable in a clean tree whose tarball inputs are unchanged since the PKGBUILD's last commit"
else
	PINDIR=$(mktemp -d)
	if python3 "$PKG/mkdist.py" --out "$PINDIR" >/dev/null 2>&1 \
	   && [ "$(cut -d' ' -f1 "$PINDIR/$PKGNAME-$VERSION.tar.sha256")" = "$PIN" ]; then
		ok "the PKGBUILD pins the tarball of its own commit"
	else
		no "the PKGBUILD pins the tarball of its own commit" \
		   "pinned $PIN; run make dist, set sha256sums, make srcinfo, commit --amend"
	fi
	rm -rf "$PINDIR"
fi

echo "== 4c. Cleanup invariants =="

# Every tool the runner's own header says it replaces must say so itself, or
# the decision to keep them as evidence is not discoverable (F-28).
for t in macbook91-speaker-probe macbook91-suspend-probe macbook91-resume-experiment \
         macbook91-dfet-probe macbook91-i2c-clock-probe macbook91-i2c-probe \
         macbook91-suspend-triage; do
	if grep -q 'SUPERSEDED' "$TOOLS/$t" 2>/dev/null; then
		ok "$t carries a SUPERSEDED banner"
	else
		no "$t carries a SUPERSEDED banner" "missing or file not found"
	fi
done

# An executable without a shebang is run by the calling shell: Python read
# as shell code.
NOSHEBANG=""
for f in "$TOOLS"/*; do
	[ -f "$f" ] && [ -x "$f" ] || continue
	[ "$(head -c2 "$f")" = '#!' ] || NOSHEBANG="$NOSHEBANG ${f##*/}"
done
if [ -z "$NOSHEBANG" ]; then
	ok "every executable under tools/ starts with a shebang"
else
	no "every executable under tools/ starts with a shebang" "missing:$NOSHEBANG"
fi

# The collector's option loop must end on a missing -o value; a failed
# `shift 2` without set -e used to spin forever.
timeout 5 "$TOOLS/dev-audio-collect.sh" -o </dev/null >/dev/null 2>&1
COLLECT_RC=$?
if [ "$COLLECT_RC" = 2 ]; then
	ok "the collector rejects -o without a directory"
else
	no "the collector rejects -o without a directory" "exit $COLLECT_RC (124 means it hung)"
fi

# An agent-environment leftover (a fixed /tmp scratch path gated on
# CLAUDE_JOB_DIR) must not remain in a tool that runs as root (F-26).
# Excludes this test file itself: it names the leftover literally to search
# for it.
JOBDIR_HITS=$(git -C "$ROOT" ls-files -z -- src tools tests packaging ':!:tests/run-tests.sh' \
	| xargs -0 grep -l 'CLAUDE_JOB_DIR\|/tmp/\.kcdis' 2>/dev/null || true)
if [ -z "$JOBDIR_HITS" ]; then
	ok "no CLAUDE_JOB_DIR / /tmp/.kcdis leftover in src/, tools/, tests/ and packaging/"
else
	no "no CLAUDE_JOB_DIR / /tmp/.kcdis leftover in src/, tools/, tests/ and packaging/" "$JOBDIR_HITS"
fi

echo
echo "== 4d. No kernel code in the repository =="

# This is the repository's own claim, checked rather than asserted: src/cs420x-a1534/
# tracks this project's code, its patches and its documentation, and nothing
# the kernel wrote. Pinning the set exactly means re-adding a kernel file
# fails here - and so does dropping vendored/ORIGINAL-a1534_sequence.h, which
# is the permanent, never-fetched record the A1534 bring-up sequence is
# derived from.
TRACKED_SRC_EXPECTED='.gitignore
LOCAL-CHANGES.md
Makefile
README.md
UPSTREAM.txt
a1534_i2c.h
a1534_match.h
a1534_pcm.h
a1534_snapshot.h
contrib/acp/macbook91-cs4208.conf
contrib/acp/macbook91-output-speaker.conf
contrib/pacman/kernel-series
contrib/pacman/macbook91-cs4208-series.hook
contrib/wireplumber/51-macbook91-cs4208.conf
dkms.conf
local-changes.patch
vendored/ORIGINAL-a1534_sequence.h
vendored/ORIGINAL-a1534_sequence.h.license
vendored/PROVENANCE.md
vendored/a1534_sequence.patch'
TRACKED_SRC_ACTUAL=$(git -C "$ROOT" ls-files -- src/cs420x-a1534 \
	| sed 's|^src/cs420x-a1534/||' | LC_ALL=C sort)
if [ "$TRACKED_SRC_ACTUAL" = "$TRACKED_SRC_EXPECTED" ]; then
	ok "src/cs420x-a1534 tracks exactly the files this project wrote"
else
	no "src/cs420x-a1534 tracks exactly the files this project wrote" \
	   "$(diff <(printf '%s\n' "$TRACKED_SRC_EXPECTED") \
	           <(printf '%s\n' "$TRACKED_SRC_ACTUAL") | head -12)"
fi

# The fetch list is the whole trust boundary of the build: six files, one
# host. A seventh entry or a second host is a change to what this package
# takes on faith, and has to be noticed here rather than in a diff nobody
# read.
FETCH_COUNT=$(sed -n '/^FETCH=(/,/^)/p' "$PKG/fetch-upstream.sh" | grep -c "^	'")
if [ "$FETCH_COUNT" = 6 ]; then
	ok "fetch-upstream.sh names exactly six remote files"
else
	no "fetch-upstream.sh names exactly six remote files" "FETCH has $FETCH_COUNT entries"
fi
FOREIGN_URLS=$(grep -oE 'https?://[^ '"'"'")]+' "$PKG/fetch-upstream.sh" \
	| grep -v '^https://git\.kernel\.org/' | sort -u || true)
if [ -z "$FOREIGN_URLS" ]; then
	ok "fetch-upstream.sh names no host but git.kernel.org"
else
	no "fetch-upstream.sh names no host but git.kernel.org" "$(printf '%s' "$FOREIGN_URLS" | head -4)"
fi

# Reproducibility: the two derived files must come back out of the patches
# byte for byte, with no fuzz allowed. --fuzz=0 is the point - a patch that
# still applies "approximately" after upstream moved is exactly the silent
# breakage this design is meant to make loud.
if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "local-changes.patch reapplies at fuzz 0 and reproduces every series cs420x.c" \
	            "the derived A1534 sequence matches the hash in packaging/upstream.lock"
else
	REPRO=$(mktemp -d)
	# Every shipped series, not just the one the hardware results are from.
	for ser in $LOCK_SERIES; do
		if patch --forward --fuzz=0 --reject-file=- -s \
		         -o "$REPRO/cs420x-$ser.c" "$SRC/upstream/$ser/cs420x.c" "$SRC/local-changes.patch" >/dev/null 2>&1 \
		   && cmp -s "$REPRO/cs420x-$ser.c" "$SRC/$ser/cs420x.c"; then
			ok "local-changes.patch reapplies at fuzz 0 and reproduces $ser/cs420x.c"
		else
			no "local-changes.patch reapplies at fuzz 0 and reproduces $ser/cs420x.c" \
			   "upstream moved under the patch, or the assembled file was edited in place"
		fi
	done

	LOCK_DERIVED=$(awk '$1 == "derived" && $3 == "vendored/a1534_sequence.h" { print $2 }' \
		"$PKG/upstream.lock")
	if patch --forward --fuzz=0 --reject-file=- -s \
	         -o "$REPRO/a1534_sequence.h" "$SRC/vendored/ORIGINAL-a1534_sequence.h" \
	         "$SRC/vendored/a1534_sequence.patch" >/dev/null 2>&1; then
		REPRO_SUM=$(sha256sum "$REPRO/a1534_sequence.h" | cut -d' ' -f1)
	else
		REPRO_SUM="(patch failed)"
	fi
	if [ -n "$LOCK_DERIVED" ] && [ "$REPRO_SUM" = "$LOCK_DERIVED" ]; then
		ok "the derived A1534 sequence matches the hash in packaging/upstream.lock"
	else
		no "the derived A1534 sequence matches the hash in packaging/upstream.lock" \
		   "lock '${LOCK_DERIVED:-<no derived row>}', rebuilt '$REPRO_SUM'"
	fi
	rm -rf "$REPRO"
fi

# Version independence. The resolver has to read the kernel it is pointed at,
# not the one this machine happens to run, so it is asked about a kernel that
# does not exist here. Hermetic: --print-tag returns before the lockfile is
# read and before anything is fetched.
fake_headers() {  # fake_headers DIR RELEASE
	mkdir -p "$1/include/generated"
	printf '#define UTS_RELEASE "%s"\n' "$2" > "$1/include/generated/utsrelease.h"
	: > "$1/.config"
}
VERINDEP=$(mktemp -d)
fake_headers "$VERINDEP/a" "6.18.52-1-nonesuch"
fake_headers "$VERINDEP/b" "7.2.0-1-nonesuch"
GOT_A=$(KDIR="$VERINDEP/a" "$PKG/fetch-upstream.sh" --print-tag 2>/dev/null || true)
GOT_B=$(KDIR="$VERINDEP/b" "$PKG/fetch-upstream.sh" --print-tag 2>/dev/null || true)
if [ "$GOT_A" = "v6.18.52" ]; then
	ok "the kernel tag is resolved from the headers it is pointed at, not hardcoded"
else
	no "the kernel tag is resolved from the headers it is pointed at, not hardcoded" \
	   "utsrelease 6.18.52-1-nonesuch resolved to '${GOT_A:-<nothing>}', expected v6.18.52"
fi
if [ "$GOT_B" = "v7.2" ]; then
	ok "a .0 kernel release resolves to the series tag kernel.org actually uses"
else
	no "a .0 kernel release resolves to the series tag kernel.org actually uses" \
	   "utsrelease 7.2.0-1-nonesuch resolved to '${GOT_B:-<nothing>}', expected v7.2"
fi
rm -rf "$VERINDEP"

# 4f. One tree, several kernel series (20261020.03). Each shipped series has to
# be pinned in the lock, reproduce from its own upstream file, and be listed in
# kheaders/KERNEL-SERIES; the 7.2 source identity must not move.
echo
echo "== 4f. Kernel series =="
if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "every shipped series matches its lock rows"
else
	SER_BAD=""
	lockrow() {  # lockrow TAG FILE PATH: does the lock pin FILE's hash for TAG and PATH?
		awk -v t="$1" -v h="$(sha256sum "$2" | cut -d' ' -f1)" -v p="$3" \
		    '$1 == t && $2 == h && $3 == p { f = 1 } END { exit !f }' "$PKG/upstream.lock"
	}
	for ser in $LOCK_SERIES; do
		tag=$(grep "^v$ser\(\.[0-9]*\)\?\$" <<<"$LOCK_TAGS" || true)
		lockrow "$tag" "$SRC/upstream/$ser/cs420x.c" upstream/cs420x.c || SER_BAD="$SER_BAD $ser:upstream"
		lockrow "$tag" "$SRC/$ser/cs420x.c" cs420x.c || SER_BAD="$SER_BAD $ser:derived"
		for h in hda_local.h hda_auto_parser.h hda_jack.h hda_beep.h generic.h; do
			lockrow "$tag" "$SRC/kheaders/$ser/$h" "kheaders/$h" || SER_BAD="$SER_BAD $ser:$h"
		done
	done
	if [ -z "$SER_BAD" ] && [ -n "$LOCK_SERIES" ]; then
		ok "every shipped series matches its lock rows ($(echo $LOCK_SERIES))"
	else
		no "every shipped series matches its lock rows" "mismatch:$SER_BAD"
	fi

	SHIPPED_SET=$(sort "$SRC/kheaders/KERNEL-SERIES" | tr '\n' ' ')
	DIR_SET=$(for d in "$SRC"/kheaders/*/; do basename "$d"; done | sort | tr '\n' ' ')
	LOCKSET=$(echo "$LOCK_SERIES" | sort | tr '\n' ' ')
	if [ -n "$SHIPPED_SET" ] && [ "$SHIPPED_SET" = "$DIR_SET" ] && [ "$SHIPPED_SET" = "$LOCKSET" ]; then
		ok "kheaders/KERNEL-SERIES names exactly the assembled and locked series ($SHIPPED_SET)"
	else
		no "kheaders/KERNEL-SERIES names exactly the assembled and locked series" \
		   "KERNEL-SERIES '$SHIPPED_SET' kheaders '$DIR_SET' lock '$LOCKSET'"
	fi

	SRCID72=$(make -s -C "$SRC" BSERIES=7.2 srcid 2>/dev/null || true)
	# The pin moves only with an edit to one of the SRCID inputs. 79b16c8b296a3821
	# held through 20261020.03; the comment, attribution and licence-header edits
	# after it gave 3459bbf7be37223c with identical module code, which held
	# through 20261021.01; the A1534 fixup pin, the jack re-route and the
	# jack-callback check gave c6661a7c92c95904 (docs/PROJECT_STATE.md).
	if [ "$SRCID72" = c6661a7c92c95904 ]; then
		ok "the 7.2 source identity is the one recorded for this tree (c6661a7c92c95904)"
	else
		no "the 7.2 source identity is the one recorded for this tree" \
		   "got '${SRCID72:-<nothing>}', expected c6661a7c92c95904"
	fi

	# Linux 7.3 added PCI-SSID quirks for 8086:7270, which this machine shares,
	# selecting a pin table that marks the speaker pin unconnected. Every
	# series' derived probe must fix the A1534 path's fixup before the tables
	# are consulted: snd_hda_pick_fixup() returns at once when fixup_id is set.
	FIXUP_BAD=""
	for ser in $LOCK_SERIES; do
		awk '/codec->fixup_id = CS4208_GPIO0;/ { id = NR }
		     /codec->fixup_list = cs4208_fixups;/ && id == NR - 1 && !pin { pin = NR }
		     /snd_hda_pick_fixup\(codec, cs4208_models/ && !pick { pick = NR }
		     END { exit !(pin && pick && pin < pick) }' "$SRC/$ser/cs420x.c" \
			|| FIXUP_BAD="$FIXUP_BAD $ser"
	done
	if [ -z "$FIXUP_BAD" ] && [ -n "$LOCK_SERIES" ]; then
		ok "every series fixes the A1534 fixup before the quirk tables ($(echo $LOCK_SERIES))"
	else
		no "every series fixes the A1534 fixup before the quirk tables" "not in:$FIXUP_BAD"
	fi

	NEWEST=$(for ser in $LOCK_SERIES; do
		awk -v re="^v${ser//./\\.}(\\.[0-9]+)?\$" '$1 ~ re { print $1 }' "$PKG/upstream.lock" | sort -uV | tail -1
	done | sort -V | tr '\n' ' ')
	GOT_TAGS=$(echo "$LOCK_TAGS" | sort -V | tr '\n' ' ')
	if [ -n "$GOT_TAGS" ] && [ "$NEWEST" = "$GOT_TAGS" ]; then
		ok "with no flag the fetcher picks the newest lock tag of each series"
	else
		no "with no flag the fetcher picks the newest lock tag of each series" \
		   "fetcher '$GOT_TAGS', lock '$NEWEST'"
	fi
fi

# One list decides which kernel series get a module: kheaders/KERNEL-SERIES.
# dkms.conf is not edited by hand: the install target writes its
# BUILD_EXCLUSIVE_KERNEL through contrib/pacman/kernel-series, the script the
# pacman hook and the verifier ask too. Exercise that script on a fake list
# and a fake modules tree, and check that its regex and its own answer agree.
KS="$SRC/contrib/pacman/kernel-series"
if grep -qx 'BUILD_EXCLUSIVE_KERNEL="@KERNEL_SERIES_RE@"' "$SRC/dkms.conf"; then
	ok "dkms.conf leaves BUILD_EXCLUSIVE_KERNEL to the install target"
else
	no "dkms.conf leaves BUILD_EXCLUSIVE_KERNEL to the install target" \
	   "$(grep -n BUILD_EXCLUSIVE_KERNEL "$SRC/dkms.conf")"
fi
KSDIR=$(mktemp -d)
printf '6.18\n7.3\n' > "$KSDIR/KERNEL-SERIES"
for r in 6.18.55-2-cachyos-lts 7.3.0-4-cachyos 7.4.0-1-cachyos; do
	mkdir -p "$KSDIR/modules/$r"
	: > "$KSDIR/modules/$r/vmlinuz"
done
# A modules directory without a kernel image (left behind by a removed kernel).
mkdir -p "$KSDIR/modules/7.1.9-1-leftover"
ks() { bash "$KS" --series-file "$KSDIR/KERNEL-SERIES" "$@"; }
KS_RE=$(ks --dkms-regex)
if [ "$KS_RE" = '^(6\.18|7\.3)\.' ] && [ "$(ks --list)" = '6.18 7.3' ]; then
	ok "kernel-series turns the list into the dkms.conf regex ($KS_RE)"
else
	no "kernel-series turns the list into the dkms.conf regex" "got '$KS_RE' and '$(ks --list)'"
fi
KS_DISAGREE=""
for r in 6.18.55-2-cachyos-lts 7.3.0-4-cachyos 7.3.0-rc6-2-cachyos-rc 7.4.0-1-cachyos \
         7.30.1-1 6.180.1 7.3-rc1 17.3.1; do
	if grep -qE "$KS_RE" <<<"$r"; then a=y; else a=n; fi
	if ks --kernel "$r" >/dev/null; then b=y; else b=n; fi
	[ "$a" = "$b" ] || KS_DISAGREE="$KS_DISAGREE $r(regex $a, script $b)"
done
if [ -z "$KS_DISAGREE" ] && ks --kernel 7.3.0-4-cachyos >/dev/null \
   && ! ks --kernel 7.4.0-1-cachyos >/dev/null; then
	ok "DKMS and kernel-series agree on which kernels are supported"
else
	no "DKMS and kernel-series agree on which kernels are supported" "disagree:$KS_DISAGREE"
fi
KS_HOOK=$(ks --hook --modules-root "$KSDIR/modules")
KS_HOOK_RC=$?
if [ "$KS_HOOK_RC" = 0 ] && [ "$(grep -c '==> WARNING' <<<"$KS_HOOK")" = 1 ] \
   && contains_str "$KS_HOOK" 'kernel 7.4.0-1-cachyos (Linux 7.4) is not a kernel series' \
   && contains_str "$KS_HOOK" 'Boot the LTS kernel'; then
	ok "the pacman hook warns once per installed kernel of another series, and does not fail"
else
	no "the pacman hook warns once per installed kernel of another series, and does not fail" \
	   "rc $KS_HOOK_RC: $(head -3 <<<"$KS_HOOK")"
fi
bash "$KS" --list --series-file "$KSDIR/missing" >/dev/null 2>&1
KS_MISSING_RC=$?
if [ "$KS_MISSING_RC" = 2 ]; then
	ok "kernel-series fails with exit 2 when it cannot read the list"
else
	no "kernel-series fails with exit 2 when it cannot read the list" \
	   "exit $KS_MISSING_RC; a missing list must not read as an answer"
fi
rm -rf "$KSDIR"
KS_HOOKFILE="$SRC/contrib/pacman/macbook91-cs4208-series.hook"
if grep -qx 'When = PostTransaction' "$KS_HOOKFILE" \
   && grep -qx 'Target = usr/lib/modules/\*/vmlinuz' "$KS_HOOKFILE" \
   && grep -qx 'Exec = /usr/lib/macbook91-cs4208/kernel-series --hook' "$KS_HOOKFILE" \
   && ! grep -q 'AbortOnFail' "$KS_HOOKFILE"; then
	ok "the series hook runs after the transaction, on kernel installs, and cannot abort it"
else
	no "the series hook runs after the transaction, on kernel installs, and cannot abort it" \
	   "$KS_HOOKFILE"
fi

# The package requires no named kernel; this is what keeps it that way. No
# file under src/, packaging/ or tests/ may tell a reader which kernel this
# tree is for. docs/ and release/ are excluded deliberately - they are history,
# and history is allowed to record what it was written against.
#
# Two narrow exclusions. A '#' comment line may recount what used to be true:
# make-package.sh describes the $srcdir defect by naming the file it left
# behind, and upstream.lock records that an earlier release's bytes were
# vendored under a different tag. And a citation of the local reference tree is an evidence path,
# not a requirement - it says where something was read, which is the one place
# a version genuinely belongs. Three citation forms are recognised: "in linux
# 7.2.4)" and ", linux 7.2.4)" closing a parenthesised citation, and "(linux
# 7.2.4 codec.c:2909" naming the file and line that was read.
KVER_HITS=$(git -C "$ROOT" grep -In '7\.2\.4' -- src packaging tests \
	| grep -v '^[^:]*:[0-9]*:[[:space:]]*#' \
	| grep -vE '[[:space:]]in linux 7\.2\.4\)|, linux 7\.2\.4\)|\(linux 7\.2\.4 [a-z_]+\.[ch]:[0-9]+' || true)
if [ -z "$KVER_HITS" ]; then
	ok "nothing under src/, packaging/ or tests/ states a required kernel version"
else
	no "nothing under src/, packaging/ or tests/ states a required kernel version" \
	   "$(printf '%s' "$KVER_HITS" | head -5)"
fi

echo
echo "== 4e. License identifiers =="

# README.md's "Provenance and licensing" maps every path to a license, and the
# map holds only while the files say the same. Code built into the kernel
# module, or with its headers, is GPL-2.0-or-later: GPL-3.0 cannot go into a
# GPL-2.0-only kernel. So is what builds the module or assembles its sources,
# because GPLv2 section 3 counts the scripts that control compiling and
# installing it as part of its source. Everything else this project wrote is
# GPL-3.0-or-later. Either is named on an SPDX line within a file's first
# three lines. Not checked for one: what cannot carry a comment (Markdown,
# JSON, text, patches, VERSION, the generated .SRCINFO), the vendored trace,
# which keeps the license recorded in vendored/PROVENANCE.md, the files that
# exist only in the maintainer's checkout (listed by bracketed names so that
# this file does not contain them), and release/, which is history.
# The ACP profiles keep the LGPL-2.1-or-later of the files they derive from
# and say so in their own words. The two recovery tools derive from OpenCorePkg
# and keep its BSD-3-Clause.
LICENSE_CHECK=$(mktemp)
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	blocked "every own file names the license README.md maps it to, and LICENSE and LICENSES/ hold the texts" \
	        "not a git checkout"
elif python3 - "$ROOT" > "$LICENSE_CHECK" 2>&1 <<'PY'
import fnmatch, os, re, subprocess, sys
root = sys.argv[1]
files = subprocess.run(["git", "-C", root, "ls-files", "-z"], check=True,
                       capture_output=True).stdout.decode().split("\0")
exempt = ("release/*", "*.md", "*.json", "*.txt", "*.patch", "LICENSE", "VERSION",
          "packaging/arch/.SRCINFO", "[.]claude/helpers/*", "private/*",
          "src/cs420x-a1534/vendored/ORIGINAL-a1534_sequence.h",
          "src/cs420x-a1534/vendored/ORIGINAL-a1534_sequence.h.license")
bsd3 = ("tools/macbook91-fetch-macos-recovery", "tools/macbook91-verify-recovery-image")
gpl2 = ("src/cs420x-a1534/a1534_*.h", "tests/*.c", "src/cs420x-a1534/Makefile",
        "src/cs420x-a1534/dkms.conf", "packaging/fetch-upstream.sh",
        "packaging/upstream.lock")
problems = []
for f in filter(None, files):
	path = os.path.join(root, f)
	if fnmatch.fnmatch(f, "src/cs420x-a1534/contrib/acp/*"):
		if "Licensed LGPL-2.1-or-later" not in open(path, encoding="utf-8").read():
			problems.append(f + ": no LGPL-2.1-or-later statement")
		continue
	if any(fnmatch.fnmatch(f, p) for p in exempt):
		continue
	want = "GPL-2.0-or-later" if any(fnmatch.fnmatch(f, p) for p in gpl2) else "GPL-3.0-or-later"
	if f in bsd3:
		want = "BSD-3-Clause"
	with open(path, encoding="utf-8", errors="replace") as fh:
		head = "".join(fh.readline() for _ in range(3))
	got = re.findall(r"SPDX-License-Identifier: ([\w.+-]+)", head)
	if got != [want]:
		problems.append("%s: %s, want %s" % (f, ", ".join(got) or "no SPDX line", want))
texts = {
	"LICENSE": "Version 3, 29 June 2007",
	"LICENSES/GPL-3.0-or-later.txt": "Version 3, 29 June 2007",
	"LICENSES/BSD-3-Clause.txt": "Redistributions of source code must retain the above copyright notice",
	"LICENSES/GPL-2.0-only.txt": "Version 2, June 1991",
	"LICENSES/GPL-2.0-or-later.txt": "Version 2, June 1991",
	"LICENSES/LGPL-2.1-or-later.txt": "Version 2.1, February 1999",
}
for f, marker in texts.items():
	try:
		if marker not in open(os.path.join(root, f), encoding="utf-8").read():
			problems.append(f + ": not that license's text")
	except OSError:
		problems.append(f + ": missing")
try:
	if open(os.path.join(root, "LICENSE"), "rb").read() != open(os.path.join(root, "LICENSES/GPL-3.0-or-later.txt"), "rb").read():
		problems.append("LICENSES/GPL-3.0-or-later.txt: not a copy of LICENSE")
except OSError:
	pass
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
then
	ok "every own file names the license README.md maps it to, and LICENSE and LICENSES/ hold the texts"
else
	no "every own file names the license README.md maps it to, and LICENSE and LICENSES/ hold the texts" \
	   "$(head -5 "$LICENSE_CHECK")"
fi
rm -f "$LICENSE_CHECK"

echo
echo "== 5. Build gates =="

KDIR="/lib/modules/$(uname -r)/build"
# Every gate below compiles, or refuses to compile, the assembled tree. With
# no assembled tree the Makefile refuses for that reason alone, which would
# make the fail-closed gates "pass" without testing anything - so the whole
# block is blocked, the way it already is when no kernel headers exist.
if [ "$ASSEMBLED" = 0 ]; then
	blocked "build gates" "$ASSEMBLE_HINT"
elif [ -r "$KDIR/.config" ]; then
	t "make check passes against the running kernel" make -C "$SRC" KDIR="$KDIR" check
	t "module builds against the running kernel" make -C "$SRC" KDIR="$KDIR" PKGVER=test -j2

	KO="$SRC/snd-hda-codec-cs420x.ko"
	if [ -f "$KO" ]; then
		VM=$(modinfo -F vermagic "$KO" 2>/dev/null | awk '{print $1}')
		if [ "$VM" = "$(uname -r)" ]; then
			ok "vermagic matches running kernel ($VM)"
		else
			no "vermagic matches running kernel" "module says $VM, running $(uname -r)"
		fi
		if [ -n "$(modinfo -F version "$KO" 2>/dev/null)" ]; then
			ok "module carries a source identity ($(modinfo -F version "$KO"))"
		else
			no "module carries a source identity" "no MODULE_VERSION"
		fi
		# The module must shadow the in-tree name so rollback is just removal.
		if [ "$(modinfo -F name "$KO")" = "snd_hda_codec_cs420x" ]; then
			ok "module shadows the in-tree codec name"
		else
			no "module shadows the in-tree codec name" "$(modinfo -F name "$KO")"
		fi
	fi

	# The vendored private HDA headers are per kernel series. Building
	# against a series this tree does not ship could silently mismatch
	# internal structs - the hazard this project rejected as audit finding
	# F13 - so a kernel outside kheaders/KERNEL-SERIES must be refused. 9.9
	# stands for "some future series".
	FAKE=$(mktemp -d)
	mkdir -p "$FAKE/include/generated"
	printf '#define UTS_RELEASE "9.9.1-1-nonesuch"\n' > "$FAKE/include/generated/utsrelease.h"
	# Copy the compiler family of the real kernel, clang or gcc: a fake .config
	# that declares neither makes `check` fail for that reason, so on a
	# gcc-built kernel (the LTS) the refusal case would pass for the wrong
	# reason.
	grep -E '^CONFIG_CC_IS_(CLANG|GCC)=y' "$KDIR/.config" > "$FAKE/.config"
	touch "$FAKE/Module.symvers"
	if make -C "$SRC" KDIR="$FAKE" check >/dev/null 2>&1; then
		no "build refuses a mismatched kernel series" "it accepted a 9.9 kernel this tree does not ship"
	else
		ok "build refuses a mismatched kernel series"
	fi
	# There is no way round the refusal: a kernel of another series gets no
	# module, never the newest shipped series built against its headers. The
	# variable that used to allow that must have no effect and no mention.
	if make -C "$SRC" KDIR="$FAKE" A1534_ALLOW_SERIES_MISMATCH=1 check >/dev/null 2>&1 \
	   || grep -q 'ALLOW_SERIES_MISMATCH' "$SRC/Makefile"; then
		no "the series refusal has no override" \
		   "A1534_ALLOW_SERIES_MISMATCH=1 still builds, or is still named in the Makefile"
	else
		ok "the series refusal has no override"
	fi
	rm -rf "$FAKE"

	# The compiler-family gate must refuse the wrong family, not warn.
	if grep -qx 'CONFIG_CC_IS_CLANG=y' "$KDIR/.config"; then
		if make -C "$SRC" KDIR="$KDIR" LLVM= CC=gcc HOSTCC=gcc -j1 >/dev/null 2>&1; then
			no "GCC build of a clang kernel fails" "it unexpectedly succeeded"
		else
			ok "GCC build of a clang kernel fails (fail-closed)"
		fi
		make -C "$SRC" KDIR="$KDIR" clean >/dev/null 2>&1
	else
		# The mirror case cannot be run: a gcc kernel's flags are not
		# clang-only, so a clang build of it is not refused. README.md and
		# docs/test-status.json record one test count, so it must not depend
		# on the compiler family of the running kernel (the 6.18 LTS is
		# gcc-built, the 7.2 kernel clang-built); run the neighbouring gate
		# instead: a .config that declares neither family is refused.
		NOFAM=$(mktemp -d)
		mkdir -p "$NOFAM/include/generated"
		printf '#define UTS_RELEASE "7.2.99-1-nonesuch"\n' > "$NOFAM/include/generated/utsrelease.h"
		: > "$NOFAM/.config"
		touch "$NOFAM/Module.symvers"
		if NOFAM_OUT=$(make -C "$SRC" KDIR="$NOFAM" check 2>&1); then
			no "check refuses a kernel .config that declares neither compiler family" "it accepted one"
		elif printf '%s\n' "$NOFAM_OUT" | grep -q 'declares neither CONFIG_CC_IS_CLANG nor CONFIG_CC_IS_GCC'; then
			ok "check refuses a kernel .config that declares neither compiler family"
		else
			no "check refuses a kernel .config that declares neither compiler family" \
			   "refused for another reason: $(printf '%s\n' "$NOFAM_OUT" | tail -1)"
		fi
		rm -rf "$NOFAM"
	fi
else
	blocked "build gates" "no kernel build tree at $KDIR"
fi

echo
echo "== 6. Packaging =="

t "shellcheck: collector"  shellcheck -S warning "$TOOLS/dev-audio-collect.sh"
t "shellcheck: verifier"   shellcheck -S warning "$TOOLS/macbook91-audio-verify"
t "shellcheck: this runner" shellcheck -S warning "$0"
t "bash syntax: verifier"  bash -n "$TOOLS/macbook91-audio-verify"

# The packaged README's Rollback section denied, in so many words, that the
# package installs "PipeWire or WirePlumber policy" - while package() was
# installing a WirePlumber drop-in, two ACP files and the verifier. Nobody
# noticed because nothing compared the two.
#
# Derive the expectation from what installs the files rather than restating it
# here: every install -D destination outside /usr/src must be named in the
# README's Rollback section. That is the root Makefile's install
# target, which writes $(DESTDIR)$(PREFIX)/...; match on the final path
# component, so a destination built from $(NAME) cannot break the check, and
# both files are tracked so this runs in a fresh clone.
README_ROLLBACK=$(awk '/^## Rollback$/{f=1;next} /^## /{f=0} f' "$SRC/README.md")
INSTALL_LINES=$(grep -cE '^[[:space:]]*install -D' "$ROOT/Makefile")
# Destinations sit on the continuation line, so fold backslash continuations
# before matching.
INSTALL_DESTS=$(sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*//;ta}' "$ROOT/Makefile" |
	grep -E '^[[:space:]]*install -D' |
	grep -oE '"\$\(DESTDIR\)\$\(PREFIX\)/[^"]+"' | tr -d '"' |
	sed 's#^\$(DESTDIR)\$(PREFIX)#/usr#' | sort -u)
INSTALL_DEST_COUNT=$(printf '%s\n' "$INSTALL_DESTS" | grep -c . || true)
if [ -z "$README_ROLLBACK" ]; then
	no "the README names every file the package installs outside /usr/src" \
	   "README.md has no '## Rollback' section to check"
elif [ "$INSTALL_DEST_COUNT" != "$INSTALL_LINES" ] || [ "$INSTALL_LINES" = 0 ]; then
	no "the README names every file the package installs outside /usr/src" \
	   "parsed $INSTALL_DEST_COUNT destination(s) from $INSTALL_LINES install -D line(s) - the check itself is stale"
else
	ROLLBACK_MISSING=""
	while read -r dest; do
		[ -n "$dest" ] || continue
		case "$dest" in /usr/src/*) continue ;; esac
		if ! printf '%s' "$README_ROLLBACK" | grep -qF -- "${dest##*/}"; then
			ROLLBACK_MISSING="$ROLLBACK_MISSING $dest"
		fi
	done <<<"$INSTALL_DESTS"
	if [ -z "$ROLLBACK_MISSING" ]; then
		ok "the README names every file the package installs outside /usr/src"
	else
		no "the README names every file the package installs outside /usr/src" \
		   "not mentioned in the Rollback section:$ROLLBACK_MISSING"
	fi
fi

# The LTS headers are the package's one kernel dependency; kernels of other
# distributions and the clang toolchain are not named at all (the headers of
# the clang-built CachyOS kernel depend on clang, lld and llvm themselves).
# The depends array is set in package(), not at the top: makepkg checks
# top-level depends before it builds, and a host without the CachyOS
# repositories cannot install the LTS headers. .SRCINFO, which the check
# below keeps current, is what makepkg reads: no depends in the pkgbase
# section, the LTS headers in the package's own.
ARCH_SRCINFO="$ARCHPKG/.SRCINFO"
if awk '/^pkgname = /{p=1} !p && /^\tdepends = /{bad=1} END{exit bad}' "$ARCH_SRCINFO" \
   && awk '/^pkgname = /{p=1} p && $0 == "\tdepends = linux-cachyos-lts-headers"{f=1} END{exit !f}' "$ARCH_SRCINFO" \
   && ! grep -qE "'(linux-headers|linux-lts-headers|clang|lld|llvm)[:']" "$ARCHPKG/PKGBUILD" \
   && ! grep -q '_toolchain_note' "$ARCHPKG/macbook91-cs4208.install"; then
	ok "the package depends on the LTS headers and names no kernel it does not support"
else
	no "the package depends on the LTS headers and names no kernel it does not support" \
	   "$(grep -n 'depends = ' "$ARCH_SRCINFO")"
fi

if command -v makepkg >/dev/null; then
	t ".SRCINFO is current" bash -c \
	  "cd '$ARCHPKG' && diff -q <(makepkg --printsrcinfo) .SRCINFO"
	# makepkg --verifysource against the pinned checksum is the pin check in
	# section 4b; a built dist/ tarball of an unreleased tree is expected
	# not to match it.
else
	blocked "packaging" "makepkg not available"
fi

P=$(ls -1t "$DIST/$PKGNAME-$VERSION"-*.pkg.tar.zst 2>/dev/null | head -1)
PKG_AUDITED=0
if [ -n "$P" ]; then
	PKG_AUDITED=1
	if command -v namcap >/dev/null; then
		if [ "$(namcap "$P" | grep -c ' E: ')" = 0 ]; then
			ok "namcap: no errors"
		else
			no "namcap: no errors" "$(namcap "$P" | grep ' E: ')"
		fi
	else
		blocked "namcap: no errors" "namcap not installed"
	fi
	if tar -taf "$P" | grep -qE '\.(o|ko|mod|cmd)$|\.git'; then
		no "package carries no build artifacts or VCS files" "$(tar -taf "$P" | grep -E '\.(o|ko|mod|cmd)$|\.git' | head -3)"
	else
		ok "package carries no build artifacts or VCS files"
	fi
	# Rollback design: DKMS must install into /updates so removal restores stock.
	# Resolve the versioned source path from the package rather than
	# hardcoding it, so a version bump cannot silently skip these checks.
	DKMS_PATH=$(tar -taf "$P" | grep -m1 'usr/src/macbook91-cs4208-[^/]*/dkms.conf$')
	if [ -z "$DKMS_PATH" ]; then
		no "package ships dkms.conf" "not found in the package"
	else
		DKMS_CONF=$(tar -xaOf "$P" "$DKMS_PATH" 2>/dev/null)
		if contains_str "$DKMS_CONF" 'DEST_MODULE_LOCATION\[0\]="/updates"'; then
			ok "rollback design: module installs into /updates"
		else
			no "rollback design: module installs into /updates" "dkms.conf does not say so"
		fi
		if contains_str "$DKMS_CONF" 'PACKAGE_NAME="macbook91-cs4208"'; then
			ok "DKMS module identity did not follow the package rename"
		else
			no "DKMS module identity did not follow the package rename" \
			   "dkms.conf must keep PACKAGE_NAME=macbook91-cs4208; changing it orphans every installed module"
		fi
		# What DKMS builds for is written at install time from the package's
		# own series list, by the script the hook and the verifier use.
		KS_PKG_LIST=$(tar -xaOf "$P" "${DKMS_PATH%dkms.conf}kheaders/KERNEL-SERIES" 2>/dev/null)
		KS_PKG_RE=$(sed -n 's/^BUILD_EXCLUSIVE_KERNEL="\(.*\)"$/\1/p' <<<"$DKMS_CONF")
		KS_WANT_RE=$(bash "$SRC/contrib/pacman/kernel-series" --dkms-regex \
		             --series-file <(printf '%s\n' "$KS_PKG_LIST") 2>/dev/null)
		if [ -n "$KS_PKG_LIST" ] && [ -n "$KS_PKG_RE" ] && [ "$KS_PKG_RE" = "$KS_WANT_RE" ]; then
			ok "packaged dkms.conf builds exactly the packaged series ($KS_PKG_RE)"
		else
			no "packaged dkms.conf builds exactly the packaged series" \
			   "dkms.conf '$KS_PKG_RE', from KERNEL-SERIES '$KS_WANT_RE'"
		fi
		PKG_FILES=$(tar -tvaf "$P")
		KS_PKG_FILE=$(sed -n 's/^SERIES_FILE=//p' <<<"$(tar -xaOf "$P" usr/lib/macbook91-cs4208/kernel-series 2>/dev/null)")
		if [ -n "$KS_PKG_FILE" ] && [ "/$DKMS_PATH" = "${KS_PKG_FILE%kheaders/KERNEL-SERIES}dkms.conf" ] \
		   && grep -qE '^-rwxr-xr-x .* usr/lib/macbook91-cs4208/kernel-series$' <<<"$PKG_FILES" \
		   && grep -qE ' usr/share/libalpm/hooks/71-macbook91-cs4208-series\.hook$' <<<"$PKG_FILES"; then
			ok "packaged hook and kernel-series read the packaged series list ($KS_PKG_FILE)"
		else
			no "packaged hook and kernel-series read the packaged series list" \
			   "SERIES_FILE '$KS_PKG_FILE', dkms.conf at '/$DKMS_PATH'"
		fi
	fi

	# The pacman package was renamed to macbook91-cs4208-dkms, which
	# deliberately left every runtime path on the unsuffixed name, because
	# the shipped WirePlumber rule names the profile set by ABSOLUTE path.
	# A later edit that "finishes" the rename by sweeping $pkgname through
	# package() would move /usr/share/macbook91-cs4208/acp out from under
	# that rule, and the symptom - no port, no sink, Dummy Output - is the
	# one the headphone-profile fix exists to fix. Only the doc directory may carry the suffix.
	STRAY=$(tar -taf "$P" | grep 'macbook91-cs4208-dkms' | grep -v '^usr/share/doc/' || true)
	if [ -z "$STRAY" ]; then
		ok "no runtime path carries the -dkms package suffix"
	else
		no "no runtime path carries the -dkms package suffix" \
		   "$(printf '%s' "$STRAY" | head -3)"
	fi
else
	blocked "package content audit" "no built package found"
fi

# The rename is only safe because pacman is told the new package replaces the
# old one. Without all three the upgrade is a fresh install beside a package
# that still owns the same files, which is a file-conflict abort.
for field in 'provides=("$_pkgname=$pkgver")' 'conflicts=("$_pkgname")' 'replaces=("$_pkgname")'; do
	if grep -qF -- "$field" "$ARCHPKG/PKGBUILD"; then
		ok "PKGBUILD declares ${field%%=*} for the early package name"
	else
		no "PKGBUILD declares ${field%%=*} for the early package name" \
		   "upgrading from macbook91-cs4208 needs it"
	fi
done

# Safety: this speaker path has no hardware volume control, so the package
# must ship software volume, and the verifier must never emit a loud tone.
if grep -q 'api.alsa.soft-mixer = true' "$SRC/contrib/wireplumber/51-macbook91-cs4208.conf" 2>/dev/null; then
	ok "package ships software volume for the card"
else
	no "package ships software volume for the card" \
	   "without it the volume slider does nothing and output is full scale"
fi
# The WirePlumber drop-in must define monitor.alsa.rules exactly once. A
# second definition (or "+=") replaces the first, silently dropping the
# soft-mixer rule - that is how an early build shipped without working volume.
WPCONF="$SRC/contrib/wireplumber/51-macbook91-cs4208.conf"

# The driver does headphone routing in hardware, so the session manager must
# not switch profile or port on a jack event: the PCM offers only a 4-channel
# configuration, the only profile that fits is analog-surround-40, and that
# profile has no headphone port - so a jack insert collapsed the sink to Dummy
# Output.
if grep -qE '^[[:space:]]*api\.acp\.auto-profile = false' "$WPCONF" &&
   grep -qE '^[[:space:]]*api\.acp\.auto-port = false' "$WPCONF"; then
	ok "session manager does not switch profile or port on jack events"
else
	no "session manager does not switch profile or port on jack events" \
	   "a jack insert collapses the sink to Dummy Output"
fi

# The profile set. auto-profile/auto-port above stop the session manager
# *switching* away; they do nothing about the profile becoming unavailable in
# the first place, which is what actually happened: the stock ACP path for
# analog-output-speaker carries "[Jack Headphone] state.plugged = no", this
# card has no second analog output port to fall back to, so a plugged jack took
# the port, the profile and the sink with it and the desktop showed Dummy
# Output. Reproduced on the test machine 2026-09-15 after a resume with the headphones
# never leaving the socket.
ACPDIR="$SRC/contrib/acp"
ACPSET="$ACPDIR/macbook91-cs4208.conf"
ACPPATH="$ACPDIR/macbook91-output-speaker.conf"

if [ -f "$ACPSET" ] && [ -f "$ACPPATH" ]; then
	ok "package carries its own ACP profile set and output path"
else
	no "package carries its own ACP profile set and output path" \
	   "missing $ACPSET or $ACPPATH"
fi

# The regression itself: the shipped output path must not make availability
# depend on any headphone or line-out jack.
if [ -f "$ACPPATH" ] && grep -qE '^\[Jack (Dock |Front |Rear |Line Out )*(Headphone|Line Out)' "$ACPPATH"; then
	no "shipped output path is not gated on the headphone jack" \
	   "a [Jack Headphone]/[Jack Line Out] stanza makes the card's only analog output port unavailable while headphones are plugged, which leaves no sink at all"
else
	ok "shipped output path is not gated on the headphone jack"
fi

# Cross-file agreement, in both directions. Three files name these paths and a
# rename in one of them is silent at build time and fatal at run time.
WP_SET_REF=$(sed -n 's/^[[:space:]]*device\.profile-set = "\([^"]*\)".*/\1/p' "$WPCONF" | head -1)
if [ -n "$WP_SET_REF" ]; then
	ok "wireplumber drop-in selects a profile set ($WP_SET_REF)"
else
	no "wireplumber drop-in selects a profile set" \
	   "without device.profile-set the card falls back to the stock set, whose only analog output port goes unavailable on a plugged jack"
fi
PATH_REF=$(sed -n 's/^[[:space:]]*paths-output = \(\/[^ ]*\).*/\1/p' "$ACPSET" 2>/dev/null | head -1)
if [ -n "$PATH_REF" ]; then
	ok "profile set names its output path absolutely ($PATH_REF)"
else
	no "profile set names its output path absolutely" \
	   "a bare name is resolved under the stock paths directory, where this file is not installed"
fi
for ref in "$WP_SET_REF" "$PATH_REF"; do
	[ -n "$ref" ] || continue
	# The Makefile's install target, which is package(), writes
	# these as $(DESTDIR)$(PREFIX)/share/macbook91-cs4208/... - the literal
	# data path, which deliberately stayed macbook91-cs4208 when the package
	# became macbook91-cs4208-dkms.
	ref_mk="\$(DESTDIR)\$(PREFIX)${ref#/usr}"
	if grep -qF -- "\"$ref_mk\"" "$ROOT/Makefile"; then
		ok "the package installs $ref"
	else
		no "the package installs $ref" \
		   "the file is referenced at run time but never packaged"
	fi
done

# The analog mapping must describe the one configuration the PCM accepts.
if [ -f "$ACPSET" ] && grep -qE '^channel-map = front-left,front-right,rear-left,rear-right' "$ACPSET"; then
	ok "profile set's analog mapping is four-channel"
else
	no "profile set's analog mapping is four-channel" \
	   "the internal PCM accepts only S16_LE/44100/4ch; any other mapping yields a sink that fails on first use"
fi

# A kernel the package does not support runs the stock codec, whose PCM opens
# in stereo; the four-channel mapping fails there and, without a stereo
# output, the card offered only a microphone. analog-stereo is therefore an
# output too, ranked below analog-surround-40.
ACP_STEREO=$(awk '/^\[Mapping analog-stereo\]/{f=1;next} /^\[/{f=0} f' "$ACPSET" 2>/dev/null)
ACP_S40_PRIO=$(awk '/^\[Mapping analog-surround-40\]/{f=1;next} /^\[/{f=0} f && /^priority = /{print $3}' "$ACPSET" 2>/dev/null)
ACP_ST_PRIO=$(sed -n 's/^priority = //p' <<<"$ACP_STEREO")
if contains_str "$ACP_STEREO" '^paths-output = .*analog-output-headphones' \
   && ! contains_str "$ACP_STEREO" '^direction = ' \
   && [ -n "$ACP_ST_PRIO" ] && [ -n "$ACP_S40_PRIO" ] && [ "$ACP_ST_PRIO" -lt "$ACP_S40_PRIO" ]; then
	ok "the stereo mapping is an output for the stock codec, ranked below the four-channel one"
else
	no "the stereo mapping is an output for the stock codec, ranked below the four-channel one" \
	   "analog-stereo priority '${ACP_ST_PRIO}', analog-surround-40 '${ACP_S40_PRIO}'"
fi

# The shipped path ends in an .include of a file owned by alsa-card-profiles.
# It must be absolute - a relative include resolves against the including
# file's directory, and this file is not installed next to the stock paths -
# and the verifier must say so plainly if that file ever goes away, because
# the symptom (no port, no sink) is identical to the bug this all fixes.
INC=$(sed -n 's/^\.include[[:space:]]*//p' "$ACPPATH" 2>/dev/null | head -1)
case "$INC" in
	/*) ok "shipped output path includes an absolute path ($INC)" ;;
	"") no "shipped output path includes an absolute path" "no .include found" ;;
	*)  no "shipped output path includes an absolute path" \
	       "'$INC' resolves against this file's own directory, which is not where the stock paths live" ;;
esac
if grep -q "ACP path's include is present" "$TOOLS/macbook91-audio-verify"; then
	ok "verifier reports a missing include by name"
else
	no "verifier reports a missing include by name" \
	   "the symptom is identical to the bug this fixes, from a different cause"
fi

# The verifier must gate on all of this, or the failure is silent again.
if grep -q 'ACP profile set selected' "$TOOLS/macbook91-audio-verify" &&
   grep -q 'analog profile survives a plugged jack' "$TOOLS/macbook91-audio-verify"; then
	ok "verifier gates on the profile set and on a plugged jack"
else
	no "verifier gates on the profile set and on a plugged jack" \
	   "this failure mode reached the maintainer once already"
fi

if [ "$(grep -cE '^[[:space:]]*monitor\.alsa\.rules' "$WPCONF")" = 1 ]; then
	ok "wireplumber drop-in defines monitor.alsa.rules exactly once"
else
	no "wireplumber drop-in defines monitor.alsa.rules exactly once" \
	   "a later definition replaces the earlier one and the soft-mixer rule is lost"
fi
if grep -qE '^[^#]*\+=' "$WPCONF"; then
	no "wireplumber drop-in does not use +=" "WirePlumber replaces rather than appends"
else
	ok "wireplumber drop-in does not use +="
fi
if python3 -c "
import sys,pathlib
t=pathlib.Path('$WPCONF').read_text()
b=t[t.index('monitor.alsa.rules'):]
sys.exit(0 if b.count('[')==b.count(']') and b.count('{')==b.count('}') else 1)"; then
	ok "wireplumber drop-in brackets balanced"
else
	no "wireplumber drop-in brackets balanced" "malformed SPA-JSON"
fi
# The verifier must itself check that software volume is active.
if grep -q 'software volume active on the card' "$TOOLS/macbook91-audio-verify"; then
	ok "verifier gates on software volume being active"
else
	no "verifier gates on software volume being active" "a silent failure here is a safety issue"
fi

if grep -qE '^[^#]*\bspeaker-test\b' "$TOOLS/macbook91-audio-verify"; then
	no "verifier does not invoke speaker-test for the tone" \
	   "speaker-test is near full scale and this path has no hardware attenuation"
else
	ok "verifier does not invoke speaker-test for the tone"
fi
TONE_AMP=$(sed -n 's/.*\bamp = .*, \([0-9.]*\)$/\1/p' "$TOOLS/macbook91-audio-verify" | head -1)
if [ -n "$TONE_AMP" ] && awk -v a="$TONE_AMP" 'BEGIN{exit !(a>0 && a<=0.25)}'; then
	ok "verifier test tone is well below full scale (amplitude $TONE_AMP)"
else
	no "verifier test tone is well below full scale" \
	   "amplitude '${TONE_AMP:-not found}' is missing or above 0.25 of full scale"
fi

# Headphones get a separate, lower check tone: at most 5% of
# full scale, passed explicitly at the headphone call site.
HP_AMP=$(sed -n 's/^HP_TONE_AMP=\([0-9.]*\)$/\1/p' "$TOOLS/macbook91-audio-verify" | head -1)
if [ -n "$HP_AMP" ] && awk -v a="$HP_AMP" 'BEGIN{exit !(a>0 && a<=0.05)}' &&
   grep -q 'play_quiet_tone "\$HP_TONE_AMP"' "$TOOLS/macbook91-audio-verify"; then
	ok "verifier's headphone tone stays at or below 5% of full scale (amplitude $HP_AMP)"
else
	no "verifier's headphone tone stays at or below 5% of full scale" \
	   "HP_TONE_AMP '${HP_AMP:-not found}' missing, above 0.05, or not used for the headphone tone"
fi

# The hotplug check must observe the unplug before the speaker-level tone
# plays; a fixed sleep there once stood in for the observation.
OFF_POLL=$(grep -n '"\$(jack_state)" = off' "$TOOLS/macbook91-audio-verify" | head -1 | cut -d: -f1)
SPK_ASK=$(grep -n 'Did the tone come from the internal speakers again' "$TOOLS/macbook91-audio-verify" | head -1 | cut -d: -f1)
if [ -n "$OFF_POLL" ] && [ -n "$SPK_ASK" ] && [ "$OFF_POLL" -lt "$SPK_ASK" ] &&
   ! grep -q 'Did the audio move to the headphones' "$TOOLS/macbook91-audio-verify"; then
	ok "verifier observes the headphone unplug before playing on the speakers"
else
	no "verifier observes the headphone unplug before playing on the speakers" \
	   "off-poll line ${OFF_POLL:-none}, speaker question line ${SPK_ASK:-none}"
fi

# A jack that already reads plugged passes the plug poll at once. The verifier
# waits for an empty jack first and keeps a capture to /dev/null running across
# the plug and the unplug (docs/INCIDENT-20261019.md); the exit trap stops it.
VF="$TOOLS/macbook91-audio-verify"
EMPTY_WAIT=$(grep -n 'wait_jack_state off 30' "$VF" | head -1 | cut -d: -f1)
PLUG_PROMPT=$(grep -n 'Plug the headphones in now' "$VF" | head -1 | cut -d: -f1)
if [ -n "$EMPTY_WAIT" ] && [ -n "$PLUG_PROMPT" ] && [ "$EMPTY_WAIT" -lt "$PLUG_PROMPT" ]; then
	ok "verifier waits for an empty jack before asking for the plug"
else
	no "verifier waits for an empty jack before asking for the plug" \
	   "empty-jack wait line ${EMPTY_WAIT:-none}, plug prompt line ${PLUG_PROMPT:-none}"
fi
if grep -q 'bg_capture_check "capture survives the headphone plug"' "$VF" &&
   grep -q 'bg_capture_check "capture survives the headphone unplug"' "$VF"; then
	ok "verifier checks a running capture across the headphone plug and unplug"
else
	no "verifier checks a running capture across the headphone plug and unplug" \
	   "bg_capture_check calls for the plug and the unplug not found"
fi
BG_BODY=$(awk '/^start_bg_capture\(\)/,/^}/' "$VF")
BG_LINE=$(grep 'arecord ' <<<"$BG_BODY" || true)
if [ -n "$BG_LINE" ] && contains_str "$BG_LINE" '/dev/null' && contains_str "$BG_LINE" ' -d [0-9]'; then
	ok "the verifier's background capture records nothing and ends by itself"
else
	no "the verifier's background capture records nothing and ends by itself" \
	   "start_bg_capture must capture to /dev/null with a -d limit: ${BG_LINE:-no arecord line}"
fi
if grep -q "^trap '.*kill \"\$BG_CAP_PID\".*rm -rf \"\$RUNTMP\"' EXIT$" "$VF"; then
	ok "the exit trap stops the verifier's background capture"
else
	no "the exit trap stops the verifier's background capture" "the EXIT trap does not kill \$BG_CAP_PID"
fi
unset VF EMPTY_WAIT PLUG_PROMPT BG_BODY BG_LINE

# The triage harness must never ask "did you hear it" after a playback that
# failed. The first version discarded aplay's stderr and exit code, so a
# device-busy failure was reported as "silent" - a confident wrong answer from
# an unverified measurement path, which is this project's most expensive
# recurring mistake.
TRIAGE="$TOOLS/macbook91-suspend-triage"
if [ -x "$TRIAGE" ]; then
	if grep -q 'BLOCKED - playback failed' "$TRIAGE" &&
	   grep -q 'return \$rc' "$TRIAGE"; then
		ok "triage asks about the tone only when playback succeeded"
	else
		no "triage asks about the tone only when playback succeeded" \
		   "a failed aplay would be reported as silence"
	fi
	if grep -q 'systemctl --user mask' "$TRIAGE"; then
		ok "triage masks PipeWire rather than only stopping it"
	else
		no "triage masks PipeWire rather than only stopping it" \
		   "socket activation restarts it and the module cannot be unloaded"
	fi
	# A triage run left PipeWire masked and the machine with no audio server:
	# free_audio was called as H=$(free_audio), so PW_MASKED was set in a
	# subshell, lost, and the exit trap declined to unmask.
	if grep -qE '^\s*(H=)?\$\(free_audio\)' "$TRIAGE"; then
		no "free_audio is not called in a subshell" \
		   "PW_MASKED would be lost and PipeWire left masked"
	else
		ok "free_audio is not called in a subshell"
	fi
	if awk '/^restore_audio\(\)/,/^}/' "$TRIAGE" | grep -q 'PW_MASKED. = yes'; then
		no "restore_audio unmasks unconditionally" \
		   "a wrong flag must not be able to leave the system without audio"
	else
		ok "restore_audio unmasks unconditionally"
	fi
	if grep -q 'trap restore_audio EXIT INT TERM' "$TRIAGE"; then
		ok "restore runs on interrupt as well as normal exit"
	else
		no "restore runs on interrupt as well as normal exit" \
		   "Ctrl-C would leave PipeWire masked"
	fi
	if grep -q 'WARNING: PipeWire did not come back' "$TRIAGE"; then
		ok "triage verifies PipeWire actually restarted"
	else
		no "triage verifies PipeWire actually restarted" \
		   "a silent restore failure leaves the user with no audio and no message"
	fi
	if grep -q 'A1534 path is NOT active' "$TRIAGE"; then
		ok "triage refuses to measure when the A1534 path is inactive"
	else
		no "triage refuses to measure when the A1534 path is inactive" \
		   "a generic 2-channel PCM makes every 4-channel tone fail and read as silence"
	fi
	if grep -q 'BASE = 2' "$TRIAGE"; then
		ok "triage stops when baseline playback itself failed"
	else
		no "triage stops when baseline playback itself failed" \
		   "later steps cannot mean anything once playback is broken"
	fi
	if grep -q 'A1534_CODEC_VENDOR_ID' "$SRC/a1534_match.h"; then
		ok "gate survives subsystem-id loss (DMI still pins the machine)"
	else
		no "gate survives subsystem-id loss" \
		   "a re-probe drops the SSID and the driver degrades to generic silently"
	fi
	if [ "$ASSEMBLED" = 0 ]; then
		gen_blocked "a declined gate is logged, never silent"
	else
		if grep -q 'not the A1534 path' "$CSRC"; then
			ok "a declined gate is logged, never silent"
		else
			no "a declined gate is logged, never silent" \
			   "a silent fallback to generic cost an entire debugging session"
		fi
	fi
	if grep -q 'BLOCKED - module in use' "$TRIAGE"; then
		ok "triage reports a failed module reload as BLOCKED"
	else
		no "triage reports a failed module reload as BLOCKED" \
		   "an unload that never happened must not read as a negative result"
	fi
fi

echo
echo "== 7. Verifier honesty =="

# The verifier must not report success while a mandatory gate fails. On a
# system still running the stock codec it must exit non-zero.
# Whether this test ran decides which totals a run can have: see the two count
# checks at the end, which are BLOCKED when it ran.
STOCK_CODEC_TEST_RAN=0
if [ -e /sys/module/snd_hda_codec_cs420x/version ]; then
	blocked "verifier fails on the stock codec" "the replacement module is already loaded"
else
	STOCK_CODEC_TEST_RAN=1
	# The diagnostic archive now lands in its own mktemp -d directory rather
	# than a predictable TMPDIR path (F-08); confine this test run's TMPDIR
	# so the archive it produces can be cleaned up afterward, and its
	# XDG_STATE_HOME, where the verifier keeps that archive, so the run adds
	# nothing to the user's own state directory.
	VERIFY_TMPDIR=$(mktemp -d)
	if TMPDIR="$VERIFY_TMPDIR" XDG_STATE_HOME="$VERIFY_TMPDIR/state" \
	   "$TOOLS/macbook91-audio-verify" --no-sound </dev/null >/dev/null 2>&1; then
		no "verifier fails on the stock codec" "it returned success with the stock module loaded"
	else
		ok "verifier fails on the stock codec"
	fi
	rm -rf "$VERIFY_TMPDIR"
fi

# The running kernel's series is the pacman hook's own question, asked
# through the same script, never a second list.
if grep -q '^KERNEL_SERIES=/usr/lib/\$PKG/kernel-series$' "$TOOLS/macbook91-audio-verify" \
   && grep -qF '"$KERNEL_SERIES" --kernel "$KVER"' "$TOOLS/macbook91-audio-verify" \
   && ! grep -q 'emit PASS "running kernel"' "$TOOLS/macbook91-audio-verify"; then
	ok "the verifier FAILs a kernel series the package does not support, through kernel-series"
else
	no "the verifier FAILs a kernel series the package does not support, through kernel-series" \
	   "tools/macbook91-audio-verify must ask /usr/lib/macbook91-cs4208/kernel-series --kernel"
fi

# A mainline pin table on the A1534 path is a FAIL of its own, read from the
# codec's driver_pin_configs; and the archive keeps only this card's block of
# `pactl list cards`, which otherwise names every Bluetooth device address.
if grep -q 'driver_pin_configs' "$TOOLS/macbook91-audio-verify" \
   && grep -q 'emit FAIL "no mainline pin overrides"' "$TOOLS/macbook91-audio-verify"; then
	ok "the verifier FAILs a mainline pin override on the A1534 path"
else
	no "the verifier FAILs a mainline pin override on the A1534 path" "check missing"
fi
if ! grep -qE 'pactl list cards +>' "$TOOLS/macbook91-audio-verify" \
   && grep -qF 'index($0, c)' "$TOOLS/macbook91-audio-verify" \
   && grep -qF 'alsa.card = ' "$TOOLS/macbook91-audio-verify"; then
	ok "the diagnostic archive keeps only this card's pactl block"
else
	no "the diagnostic archive keeps only this card's pactl block" "31-cards.txt is unfiltered"
fi

# It must refuse to play a tone when software gates have already failed.
if grep -q 'software gates failed; not playing a tone' "$TOOLS/macbook91-audio-verify"; then
	ok "verifier refuses to play a tone after a failed software gate"
else
	no "verifier refuses to play a tone after a failed software gate" "guard missing"
fi

# Regression guard for the two bugs that produced false FAILs on the first
# real hardware run (both in the verifier, not the driver):
#
#  A) `set -o pipefail` plus `producer | grep -q PATTERN`: grep -q exits at the
#     first match and SIGPIPEs the producer, so the pipeline reports 141 and a
#     successful match reads as a failure.
#  B) awk matching "^Node " n where n already began with "Node ", producing the
#     impossible pattern "^Node Node 0x1d ".
if grep -qE '^set .*-o pipefail|^set -[a-z]*o pipefail' "$TOOLS/macbook91-audio-verify"; then
	no "verifier does not enable pipefail" "grep -q in a pipeline would then read as failure"
else
	ok "verifier does not enable pipefail"
fi
if grep -nE '^\s*(if|elif)\s.*\|\s*grep -q' "$TOOLS/macbook91-audio-verify" >/dev/null; then
	no "no conditional tests a pipeline's exit status" \
	   "$(grep -nE '^\s*(if|elif)\s.*\|\s*grep -q' "$TOOLS/macbook91-audio-verify" | head -2)"
else
	ok "no conditional tests a pipeline's exit status"
fi
if grep -q '\$0 ~ "\^Node "n' "$TOOLS/macbook91-audio-verify"; then
	no "no doubled Node prefix in awk node matching" 'pattern is "^Node " n where n already has it'
else
	ok "no doubled Node prefix in awk node matching"
fi

# The A1534 proof must come from hardware state, which works without root,
# rather than only from the kernel log, which many users cannot read.
if grep -q 'speaker PCM bound to converter' "$TOOLS/macbook91-audio-verify"; then
	ok "A1534 proof uses hardware state, not only the kernel log"
else
	no "A1534 proof uses hardware state, not only the kernel log" "check missing"
fi

# It must never archive a recording.
if grep -q 'rm -f "$REC"' "$TOOLS/macbook91-audio-verify"; then
	ok "verifier deletes the microphone recording and never archives it"
else
	no "verifier deletes the microphone recording" "no cleanup found"
fi

# The accepted codec-SSID set must be exactly the set a1534_match() accepts -
# not a copy that can silently drift from it (F-04).
if grep -q 'CODEC_SSID_WANT=106b6500' "$TOOLS/macbook91-audio-verify" &&
   grep -q 'CODEC_SSID_DEGRADED=10134208' "$TOOLS/macbook91-audio-verify" &&
   grep_code '0x106b6500u' "$SRC/a1534_match.h" &&
   grep_code '0x10134208u' "$SRC/a1534_match.h"; then
	ok "verifier accepts exactly the SSID set a1534_match() accepts"
else
	no "verifier accepts exactly the SSID set a1534_match() accepts" \
	   "one side has a constant the other does not"
fi

# The headphone jack control must be looked up by name, not a hardcoded numid.
if grep -q 'numid=12' "$TOOLS/macbook91-audio-verify"; then
	no "no hardcoded jack control numid" "numid=12 literal remains"
else
	ok "no hardcoded jack control numid"
fi

# The microphone recording must be protected by a cleanup trap installed
# before the first recording (F-07), and Ctrl-C or TERM must end the run:
# a trap on INT that only cleans up lets bash continue with the next
# command, past the deleted scratch directory. Run the verifier's own trap
# lines in a child shell and interrupt it.
TRAP_LINE=$(grep -n "^trap '.*rm -rf \"\$RUNTMP\"' EXIT$" "$TOOLS/macbook91-audio-verify" | head -1 | cut -d: -f1)
FIRST_ARECORD_LINE=$(grep -n 'arecord -D "hw:' "$TOOLS/macbook91-audio-verify" | head -1 | cut -d: -f1)
TRAPS=$(grep "^trap '" "$TOOLS/macbook91-audio-verify")
TRAP_DIR=$(mktemp -d)
# A suite started as a background job inherits SIGINT as ignored, and a bash
# cannot trap or reset a signal that was ignored when it started, so the
# interrupt below would do nothing and the test would fail for a reason that
# has nothing to do with the verifier. Reset the signals through python3 and
# exec the child; without python3 the test is BLOCKED, not failed.
TRAP_CHILD=(bash -c "$TRAPS"$'\nkill -INT $$\necho continued-after-INT')
SIGIGN=$(awk '/^SigIgn:/ {print $2}' /proc/$$/status 2>/dev/null)
TRAP_CAN_RUN=1
if [ $(( 0x${SIGIGN:-0} & 2 )) -ne 0 ]; then
	if command -v python3 >/dev/null 2>&1; then
		TRAP_CHILD=(python3 -c 'import os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
os.execvp(sys.argv[1], sys.argv[1:])' "${TRAP_CHILD[@]}")
	else
		TRAP_CAN_RUN=0
	fi
fi
if [ "$TRAP_CAN_RUN" = 0 ]; then
	blocked "the recording cleanup trap precedes recording and ends the run on Ctrl-C" \
	        "SIGINT is ignored in this shell (started as a background job) and python3 is not available to reset it"
else
	TRAP_OUT=$(RUNTMP="$TRAP_DIR" "${TRAP_CHILD[@]}" 2>&1)
	TRAP_RC=$?
	case "$TRAP_OUT" in *continued-after-INT*) TRAP_CONT=1 ;; *) TRAP_CONT=0 ;; esac
	if [ -n "$TRAP_LINE" ] && [ -n "$FIRST_ARECORD_LINE" ] && [ "$TRAP_LINE" -lt "$FIRST_ARECORD_LINE" ] &&
	   [ "$TRAP_CONT" = 0 ] && [ "$TRAP_RC" -ne 0 ] && [ ! -e "$TRAP_DIR" ]; then
		ok "the recording cleanup trap precedes recording and ends the run on Ctrl-C"
	else
		no "the recording cleanup trap precedes recording and ends the run on Ctrl-C" \
		   "trap line ${TRAP_LINE:-none}, first arecord line ${FIRST_ARECORD_LINE:-none}, rc $TRAP_RC, continued $TRAP_CONT"
	fi
fi
rm -rf "$TRAP_DIR"

# The diagnostic archive directory must come from mktemp -d, not a
# predictable, pre-creatable TMPDIR path (F-08).
if grep -q '\${TMPDIR:-/tmp}/\${PKG}' "$TOOLS/macbook91-audio-verify"; then
	no "archive directory is unpredictable" "predictable TMPDIR/PKG concatenation remains"
elif grep -q 'ARCHIVE_STAGE=\$(mktemp -d)' "$TOOLS/macbook91-audio-verify"; then
	ok "archive directory is unpredictable"
else
	no "archive directory is unpredictable" "mktemp -d staging directory not found"
fi

echo

echo "== 7b. Transport audit and the central runner =="

# The one transcription defect the Apple disassembly found. Apple's i2cRead
# (0x9c2f1e) closes the transaction with set(0x16, 0x02) and one more status
# read; a1534_i2c_read() did not, so the kernel path and the userspace probes
# were running different protocols and their results were not comparable.
if awk '/^static unsigned int a1534_i2c_read/,/^}/' "$SRC/a1534_i2c.h" \
	| grep -q 'A1534_I2C_CTRL_STOP'; then
	ok "a1534_i2c_read() closes the transaction with STOP"
else
	no "a1534_i2c_read() closes the transaction with STOP" \
	   "Apple's i2cRead ends with coef 0x16 = 0x02; ours must too"
fi

# ... and the STOP must be followed by the status read, like every other step.
if awk '/^static unsigned int a1534_i2c_read/,/^}/' "$SRC/a1534_i2c.h" \
	| grep -A2 'A1534_I2C_CTRL_STOP' | grep -q 'a1534_i2c_sync'; then
	ok "the read's STOP is followed by a status read"
else
	no "the read's STOP is followed by a status read" "Apple reads 0x17 after the STOP too"
fi

# The comment that described enableI2C as a pulse was wrong and had been
# quoted onwards as a fact. The phrase may appear only as a quotation that is
# immediately corrected - never again as an assertion.
if grep -q 'Faithful to AppleHDA: enabling clears bit 3' "$SRC/a1534_i2c.h"; then
	no "the 'pulse' description is quoted only to correct it" \
	   "enableI2C toggles then sets; with bit 3 clear that is SET, SET"
elif grep -q 'description is wrong' "$SRC/a1534_i2c.h"; then
	ok "the 'pulse' description is quoted only to correct it"
else
	no "the 'pulse' description is quoted only to correct it" \
	   "the correction itself has gone missing from a1534_i2c.h"
fi

# The amplifier bring-up must stay off by default while the transport is
# unproven, and the reason recorded must be the real one.
if grep_code 'static bool a1534_amp;' "$SRC/a1534_i2c.h" &&
   grep -q 'never as a fix' "$SRC/a1534_i2c.h"; then
	ok "amplifier bring-up stays off, with the withdrawn claim recorded"
else
	no "amplifier bring-up stays off, with the withdrawn claim recorded" \
	   "a1534_amp must default off and the 'bus demonstrably not answering' claim must stay withdrawn"
fi

RUNNER="$TOOLS/macbook91-runner"
TRANSPORT="$TOOLS/macbook91-amp-transport"

t "macbook91-runner parses" bash -n "$RUNNER"
t "macbook91-amp-transport parses" python3 -c \
	"import ast,sys; ast.parse(open(sys.argv[1]).read())" "$TRANSPORT"

# The bug that left PipeWire masked across a reboot: free_audio ran in a
# command substitution, so the flag it set died in the subshell and the
# restore declined. Nothing that sets caller state may be called that way.
if grep -nE '\$\((save_unit_states|restore_units|read_identity|check_identity)' "$RUNNER" \
	| grep -v '^[0-9]*:[[:space:]]*#' | grep -q .; then
	no "no state-setting function runs in a subshell" \
	   "$(grep -nE '\$\((save_unit_states|restore_units|read_identity|check_identity)' "$RUNNER")"
else
	ok "no state-setting function runs in a subshell"
fi

# The restore must not be guarded by a flag that can be wrong. It walks the
# units it recorded; a unit that was already masked stays masked.
if awk '/^restore_units\(\)/,/^}/' "$RUNNER" | grep -q 'UNIT_WAS_MASKED\[\$u\]:-no.* = yes .* continue'; then
	ok "restore leaves an already-masked unit masked"
elif awk '/^restore_units\(\)/,/^}/' "$RUNNER" | grep -q 'UNIT_WAS_MASKED'; then
	ok "restore leaves an already-masked unit masked"
else
	no "restore leaves an already-masked unit masked" "restore_units ignores the saved prior state"
fi

if grep -q 'trap on_exit EXIT INT TERM' "$RUNNER"; then
	ok "restore runs on interrupt as well as on normal exit"
else
	no "restore runs on interrupt as well as on normal exit" "the trap must cover INT and TERM"
fi

if awk '/^restore_units\(\)/,/^}/' "$RUNNER" | grep -q 'still masked'; then
	ok "restore verifies itself and prints manual recovery when it fails"
else
	no "restore verifies itself and prints manual recovery when it fails" \
	   "a restore that does not check its own result is how this was missed before"
fi

# A mandatory test that is never reached must not disappear into silence.
if grep -q '^expect()' "$RUNNER" && grep -q 'INCOMPLETE' "$RUNNER"; then
	ok "an unreached mandatory test yields INCOMPLETE, not PASS"
else
	no "an unreached mandatory test yields INCOMPLETE, not PASS" \
	   "the runner must pre-declare mandatory tests as NOT_RUN"
fi

# Identity is re-verified after anything that could change it. The lesson
# of an early build: a re-probe silently degraded the SSID and every later measurement
# was taken on the generic path.
if grep -q 'check_identity post-probe' "$RUNNER"; then
	ok "identity is re-verified after the probe, not only before it"
else
	no "identity is re-verified after the probe, not only before it" \
	   "a destructive step can change the target the measurement depends on"
fi

# The card is located by codec name, never by a hardcoded number.
if awk '/^read_identity\(\)/,/^}/' "$RUNNER" | grep -q 'CS4208'; then
	ok "the card is located by its codec, not by a hardcoded number"
else
	no "the card is located by its codec, not by a hardcoded number" \
	   "card and PCI numbering must be resolved dynamically"
fi

# The probe must never write an amplifier register. An I2C read sends only the
# register NUMBER; a write sends a second data byte. There must be no second
# cset(C_DATA, ...) inside the read transaction.
if awk '/^def i2c_read/,/^def sweep/' "$TRANSPORT" | grep -c 'cset(C_DATA' | grep -qx 1; then
	ok "the transport probe writes no amplifier register"
else
	no "the transport probe writes no amplifier register" \
	   "a read transaction sends the register number once and nothing else"
fi

# It must restore the bridge enable byte-exact, not by Apple's bare toggle,
# which would leave the bridge open if it had been closed.
if grep -q "cset(C_ENABLE, original_enable)" "$TRANSPORT"; then
	ok "the transport probe restores the bridge byte-exact"
else
	no "the transport probe restores the bridge byte-exact" \
	   "a toggle is not a restore"
fi

# A control address is not optional, and one is not enough.
if grep -q 'CONTROLS = \[0x20, 0x50, 0x7E\]' "$TRANSPORT"; then
	ok "the sweep carries three negative controls, not one"
else
	no "the sweep carries three negative controls, not one" \
	   "one control cannot separate 'every address answers alike' from a coincidence"
fi

# The verdict must not be phrased as a statement about the hardware.
if grep -q 'cannot \(distinguish\|tell\)' "$TRANSPORT" &&
   grep -q 'INVALID READ PATH' "$TRANSPORT"; then
	ok "a failed sweep is reported as an invalid instrument, not as absent hardware"
else
	no "a failed sweep is reported as an invalid instrument, not as absent hardware" \
	   "this is the exact inference that had to be withdrawn"
fi

# selfcheck must run clean, unprivileged, touching nothing. Like every runner
# command it writes a run directory, so it gets a scratch home: the suite
# must not add a run to the user's own state directory each time it runs.
RUNNER_HOME=$(mktemp -d)
if out=$(MACBOOK91_STATE_DIR="$RUNNER_HOME" "$RUNNER" selfcheck 2>&1); then
	if contains_str "$out" "verdict: PASS"; then
		ok "macbook91-runner selfcheck passes unprivileged"
	else
		no "macbook91-runner selfcheck passes unprivileged" "$(printf '%s' "$out" | tail -3)"
	fi
else
	no "macbook91-runner selfcheck passes unprivileged" "$(printf '%s' "$out" | tail -5)"
fi
rm -rf "$RUNNER_HOME"

# The Apple audit must keep its offsets: a claim without one is not checkable.
for off in 0x9c2dda 0x9c328c 0x9c2f1e 0xa2e1b4 0xa48c42 0x9f61ba 0x9f6314; do
	if grep -q "$off" "$ROOT/docs/APPLE-I2C-AUDIT.md"; then
		ok "APPLE-I2C-AUDIT records offset $off"
	else
		no "APPLE-I2C-AUDIT records offset $off" "every claim must name where it came from"
	fi
done

# The withdrawn conclusion must stay withdrawn: the checkpoint may mention it
# only next to the withdrawal, never as the project's position.
if ! grep -q 'WITHDRAWN' "$ROOT/docs/CLAIMS-AUDIT.md"; then
	no "the 'not fixable' conclusion stays withdrawn" "CLAIMS-AUDIT.md no longer withdraws it"
elif ! grep -q 'not fixable' "$ROOT/docs/PROJECT_STATE.md"; then
	ok "the 'not fixable' conclusion stays withdrawn"
elif grep -B3 -A3 'not fixable' "$ROOT/docs/PROJECT_STATE.md" | grep -qi 'withdraw'; then
	ok "the 'not fixable' conclusion stays withdrawn"
else
	no "the 'not fixable' conclusion stays withdrawn" \
	   "PROJECT_STATE.md states it without withdrawing it"
fi

if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
g={x["id"]:x for x in d["gates"]}
b = d["blocker"]
# The one invariant: the blocker must never describe a fix as done unless a
# gate records the hardware run that says so. Three legal states, nothing in
# between:
#
#   the defect is still open                    -> "OPEN DEFECT"
#   a fix exists but has not been run           -> "not yet verified on hardware"
#   a fix exists and was run                    -> "confirmed on hardware", and
#                                                  the gate PASSes with the
#                                                  observation in its note
fix = g["fix.cvt_chan_count_programmed"]
if "OPEN DEFECT" in b:
    pass
elif fix["status"] == "PASS":
    assert "confirmed on hardware" in b.lower(), \
        "the blocker claims no open defect but never says the fix was confirmed on hardware"
    assert "CONFIRMED ON HARDWARE" in fix["note"].upper(), \
        "a PASS on the fix gate must record what was observed, not just the claim"
    # Long-suspend coverage may be PASS, but only against durations somebody
    # actually measured. This assertion used to forbid PASS outright, which
    # was right while nothing had been measured and became wrong the moment
    # something was: a test must check the evidence, not freeze the verdict.
    lsc = g["hw.long_suspend_coverage"]
    if lsc["status"] == "PASS":
        import re
        assert re.search(r"\d+\s*(h|min)\b", lsc["note"]), \
            "a PASS on long-suspend coverage must record the measured durations"
        assert "restored" in lsc["note"], \
            "a PASS on long-suspend coverage must record that the resume restore actually ran"
    else:
        assert "long" in b.lower(), \
            "the blocker must keep naming the outstanding long-suspend coverage"
else:
    assert "not yet verified on hardware" in b, \
        "a fix may not be announced in the blocker without saying it is unverified"
assert g["hw.amp_i2c_bringup"]["status"]=="BLOCKED", "amp bring-up must not be recorded as a closed FAIL"
assert "WITHDRAWN" in g["hw.amp_i2c_bringup"]["note"]
# transport.discriminates may be NOT_RUN or FAIL, but a FAIL must keep
# saying what it is a failure OF: the instrument, not the hardware.
td = g["transport.discriminates"]
assert td["status"] in ("NOT_RUN", "FAIL"), td["status"]
if td["status"] == "FAIL":
    assert "NOT about the amplifiers" in td["note"], \
        "a failed transport measurement must not be read as a finding about the amplifiers"
# env.deep_sleep_selected must agree with the live machine, not with a
# value frozen into the file. mem_sleep changes under us.
try:
    live = open("/sys/power/mem_sleep").read()
except OSError:
    live = None
if live is not None:
    want = "PASS" if "[deep]" in live else "FAIL"
    assert g["env.deep_sleep_selected"]["status"] == want, (
        "env.deep_sleep_selected says %s but mem_sleep is %r"
        % (g["env.deep_sleep_selected"]["status"], live.strip()))
' "$ROOT/docs/test-status.json" 2>/dev/null; then
	ok "test-status.json never reports an unverified fix as done"
else
	no "test-status.json never reports an unverified fix as done" \
	   "$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d["blocker"][:120])
' "$ROOT/docs/test-status.json" 2>&1)"
fi

STATE="$TOOLS/macbook91-codec-state"
t "macbook91-codec-state parses" python3 -c \
	"import ast,sys; ast.parse(open(sys.argv[1]).read())" "$STATE"

# A dump that cannot tell an error from a zero cannot support "unchanged".
if grep -q "'<error %s>' % e.errno" "$STATE" && grep -q "'<no-response>'" "$STATE"; then
	ok "state capture marks errors and no-response distinctly from zero"
else
	no "state capture marks errors and no-response distinctly from zero" \
	   "macbook91-codec-dump could not, and its 1209 'registers' inherited that"
fi

# Every field must be gated on the widget's own advertised capability.
if grep -q 'caps & W_POWER' "$STATE" && grep -q 'not (caps & bit)' "$STATE" &&
   grep -q 'caps & W_PROC' "$STATE" && grep -q 'caps & W_UNSOL' "$STATE" &&
   grep -q 'caps & W_CONN_LIST' "$STATE" && grep -q 'AC_PAR_NODE_COUNT' "$STATE"; then
	ok "state capture asks each widget only what its capabilities allow"
else
	no "state capture asks each widget only what its capabilities allow" \
	   "a fixed NID/verb list invents fields the hardware does not have"
fi

# The vendor id lives on the root node. Reading it from the AFG returns 0,
# which is how the first privileged run of the probe declared a CS4208 not to
# be a CS4208.
if grep -q 'c.param(ROOT, AC_PAR_VENDOR_ID)' "$STATE" &&
   grep -q 'c.verb(ROOT_NID, PARAMETERS, AC_PAR_VENDOR_ID)' "$TOOLS/macbook91-amp-transport"; then
	ok "the vendor id is read from the root node, not the function group"
else
	no "the vendor id is read from the root node, not the function group" \
	   "AC_PAR_VENDOR_ID on the AFG returns 0 and looks like a missing codec"
fi

# Evidence before verdict: a run that blocks at the identity gate must still
# have recorded the state it found.
if awk '/# --- capture the state BEFORE/,/# --- identity ---/' "$TOOLS/macbook91-amp-transport" \
	| grep -q "r\['as_found'\] = entry"; then
	ok "the probe records what it found before it decides anything"
else
	no "the probe records what it found before it decides anything" \
	   "two runs either side of a suspend were thrown away at the identity gate"
fi

# The coefficient index must be put back: reading a coefficient is a write.
if grep -q 'coef_index_at_entry' "$STATE" && grep -q 'coef_index_restored' "$STATE"; then
	ok "state capture restores the coefficient index it had to change"
else
	no "state capture restores the coefficient index it had to change" ""
fi

if grep -q 'does not call itself read-only while writing' "$STATE"; then
	ok "state capture does not claim to be read-only"
else
	no "state capture does not claim to be read-only" \
	   "macbook91-codec-dump claimed 'no writes of any kind' while issuing SET_COEF_INDEX 128 times"
fi

# The diff must separate a genuinely volatile field from a real change.
FX=$(mktemp -d)
python3 - "$FX" <<'FIXTURE'
import json, sys, copy
d = sys.argv[1]
base = {"vendor_id": "10134208", "subsystem_id_param_root": "106b6500", "afg_nid": 1,
        "gpio": {"data": "07", "mask": "37", "direction": "31"},
        "nodes": {"0x0a": {"stream_format": "4013"},
                  "0x1d": {"pin_sense_volatile": "00000000"},
                  "0x24": {"coefficients": ["00c4", "0000", "003a"]}}}
after = copy.deepcopy(base)
after["nodes"]["0x0a"]["stream_format"] = "4033"
after["nodes"]["0x1d"]["pin_sense_volatile"] = "80000000"
after["nodes"]["0x24"]["coefficients"][2] = "0000"
json.dump(base, open(d + "/a.json", "w"))
json.dump(after, open(d + "/b.json", "w"))
FIXTURE
out=$("$STATE" diff "$FX/a.json" "$FX/b.json" 2>&1) || true
if contains_str "$out" "3 differing fields (2 after dropping the volatile ones)" &&
   contains_str "$out" "coef\[0x02\]" &&
   contains_str "$out" "(volatile)"; then
	ok "state diff reports per-coefficient changes and labels volatile fields"
else
	no "state diff reports per-coefficient changes and labels volatile fields" "$out"
fi
if "$STATE" diff "$FX/a.json" "$FX/a.json" >/dev/null 2>&1; then
	ok "state diff of a capture against itself exits 0"
else
	no "state diff of a capture against itself exits 0" "identical captures must not report a change"
fi
rm -rf "$FX"

if "$STATE" capture /dev/null >/dev/null 2>&1; then
	no "state capture without root is BLOCKED, not a crash" "it should have refused"
else
	rc=$?
	if [ "$rc" = 2 ] || [ "$(id -u)" = 0 ]; then
		ok "state capture without root is BLOCKED, not a crash"
	else
		no "state capture without root is BLOCKED, not a crash" "exit $rc, expected 2"
	fi
fi


# Every HDA verb and parameter constant in the probing tools, checked against
# the running kernel's own header. GET_CONV was 0x0f01 - which is
# GET_CONNECT_SEL - so the "converter" field reported the connection select
# and a running stream looked identical to an idle one.
HDRS=/usr/lib/modules/$(uname -r)/build/include/sound/hda_verbs.h
if [ -r "$HDRS" ]; then
	out=$(python3 - "$HDRS" "$TOOLS/macbook91-codec-state" "$TOOLS/macbook91-amp-transport" <<'VERBS'
import re, sys
hdr = open(sys.argv[1]).read()
kern = {m.group(1): int(m.group(2), 0) for m in
        re.finditer(r'#define\s+(AC_(?:VERB|PAR)_\w+)\s+(0x[0-9a-fA-F]+|\d+)', hdr)}
bad = []
checked = 0
for path in sys.argv[2:]:
    src = open(path).read()
    for m in re.finditer(r'^([A-Z_0-9]+(?:,\s*[A-Z_0-9]+)*)\s*=\s*([^\n#]+)', src, re.M):
        names = [x.strip() for x in m.group(1).split(',')]
        vals = [v.strip() for v in m.group(2).split(',')]
        if len(names) != len(vals):
            continue
        for n, v in zip(names, vals):
            for prefix in ('AC_VERB_', 'AC_PAR_'):
                key = n if n.startswith(prefix) else prefix + n
                if key in kern:
                    break
            else:
                continue
            try:
                iv = int(v, 0)
            except ValueError:
                continue
            checked += 1
            if iv != kern[key]:
                bad.append('%s: %s = %#x but the kernel says %s = %#x'
                           % (path.split('/')[-1], n, iv, key, kern[key]))
print('checked %d constants' % checked)
for b in bad:
    print('MISMATCH ' + b)
sys.exit(1 if bad else 0)
VERBS
)
	if [ $? -eq 0 ]; then
		ok "every verb constant matches the running kernel's hda_verbs.h ($(printf '%s' "$out" | head -1))"
	else
		no "every verb constant matches the running kernel's hda_verbs.h" "$out"
	fi
else
	blocked "every verb constant matches the running kernel's hda_verbs.h" \
	        "no hda_verbs.h under /usr/lib/modules/$(uname -r)/build"
fi

# The HDA hwdep verb ioctl number, derived rather than copied.
if python3 -c '
import sys
# _IOWR(0x48, 0x11, struct hda_verb_ioctl) with a 8-byte struct
want = (3 << 30) | (8 << 16) | (0x48 << 8) | 0x11
src = open(sys.argv[1]).read()
import re
m = re.search(r"HDA_IOCTL_VERB_WRITE\s*=\s*(0x[0-9A-Fa-f]+)", src)
assert m, "constant not found"
got = int(m.group(1), 0)
assert got == want, "%#x != %#x" % (got, want)
' "$TOOLS/macbook91-amp-transport"; then
	ok "the hwdep verb ioctl number is _IOWR('H', 0x11, 8 bytes)"
else
	no "the hwdep verb ioctl number is _IOWR('H', 0x11, 8 bytes)" "it does not derive correctly"
fi

# GET_AMP_GAIN_MUTE's selector (bit 15 output, bit 13 left) must ride in the
# verb field: the hwdep ioctl passes only 8 parameter bits. Put in the
# parameter it is dropped and every read is input/right/index 0.
AMPV=$(python3 -B -c '
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("codec_state", sys.argv[1])
spec = importlib.util.spec_from_loader("codec_state", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
print(" ".join("%03x" % m.amp_verb(o, l) for o in (True, False) for l in (True, False)))
' "$TOOLS/macbook91-codec-state" 2>&1)
if [ "$AMPV" = "ba0 b80 b20 b00" ] && ! grep -q 'direction | (ch << 5)' "$TOOLS/macbook91-codec-state"; then
	ok "state capture addresses amplifier direction and channel in the verb field"
else
	no "state capture addresses amplifier direction and channel in the verb field" "amp_verb gave '$AMPV'"
fi

# Coefficient 0x00 is firmware configuration, not scratch. Only bit 3 may be
# written, and every other bit must be preserved.
if grep -q "0x00  bit 3 only, every other bit preserved" "$TOOLS/macbook91-amp-transport" &&
   ! awk '/def main/,0' "$TOOLS/macbook91-amp-transport" \
       | grep -qE 'cset\(C_ENABLE, *0x[0-9a-fA-F]+\)'; then
	ok "the probe never writes a literal value into coefficient 0x00"
else
	no "the probe never writes a literal value into coefficient 0x00" \
	   "0x00 reads 0x00c4 here; scrambling its unknown bits is a blind register write"
fi

# The control register may only ever see the values Apple's own driver writes.
if awk '/T1b: classify/,/T2: does the bridge/' "$TOOLS/macbook91-amp-transport" \
	| grep -q '(C_CTRL, (CTRL_START, CTRL_STOP))'; then
	ok "the control register is only written with Apple's own values"
else
	no "the control register is only written with Apple's own values" \
	   "0x55 into a control register sets unknown control bits"
fi

# The status register is never written at all.
if awk '/T1b: classify/,/T2: does the bridge/' "$TOOLS/macbook91-amp-transport" \
	| grep -q 'never written'; then
	ok "the status register is read, never written"
else
	no "the status register is read, never written" ""
fi


echo "== 7c. Converter channel count (the resume defect) =="

# Measured either side of one deep suspend, speakers audible before and silent
# after, 722 capability-validated fields: converter 0x0a's cvt_chan_count is
# the ONLY functional field in the codec that moves, 0x03 -> 0x00.
if grep_code 'AC_VERB_SET_CVT_CHAN_COUNT' "$SRC/a1534_pcm.h"; then
	ok "the speaker converter's channel count is programmed"
else
	no "the speaker converter's channel count is programmed" \
	   "0x03 -> 0x00 across a suspend is what silences the speakers"
fi

# The register holds channels - 1 (sound/hda/core/hdmi_chmap.c:199-210).
if grep_code 'chans - 1' "$SRC/a1534_pcm.h"; then
	ok "the channel count register is written as channels - 1"
else
	no "the channel count register is written as channels - 1" \
	   "hdmi_set_channel_count writes chs - 1; 0x03 means four channels"
fi

# From the negotiated format, never a constant: the PCM is pinned to four
# channels today, but a hardcoded 4 would be a lie the moment that changes.
if grep_code 'chans = \(format & 0xf\) \+ 1' "$SRC/a1534_pcm.h"; then
	ok "the channel count comes from the negotiated format"
else
	no "the channel count comes from the negotiated format" \
	   "it must not be hardcoded; the format word carries channels - 1 in bits 3:0"
fi

# Only on a converter that has the field. Headphone converter 0x02 reports no
# AC_WCAP_CHAN_CNT_EXT - which is exactly why headphones survived every resume
# while the speakers did not - and writing it there would be inventing a
# register the widget does not have.
if grep_code 'AC_WCAP_CHAN_CNT_EXT' "$SRC/a1534_pcm.h"; then
	ok "the channel count is only written where the widget advertises it"
else
	no "the channel count is only written where the widget advertises it" \
	   "converter 0x02 has no such field"
fi

# It must be set BEFORE the stream is set up, not after.
if awk '/^static void a1534_route_stream/,/^}/' "$SRC/a1534_pcm.h" \
	| grep -n 'a1534_set_chan_count\|snd_hda_codec_setup_stream' \
	| tr '\n' ' ' | grep -q 'a1534_set_chan_count.*snd_hda_codec_setup_stream'; then
	ok "the channel count is programmed before the stream is set up"
else
	no "the channel count is programmed before the stream is set up" \
	   "$(awk '/^static void a1534_route_stream/,/^}/' "$SRC/a1534_pcm.h" | grep -n 'chan_count\|setup_stream')"
fi

# And it is firmware state, so the snapshot must carry it too - a resume with
# no stream running must not leave the converter at one channel.
if grep_code 'AC_VERB_GET_CVT_CHAN_COUNT' "$SRC/a1534_snapshot.h" &&
   grep_code 'AC_VERB_SET_CVT_CHAN_COUNT' "$SRC/a1534_snapshot.h"; then
	ok "the snapshot captures and restores the converter channel count"
else
	no "the snapshot captures and restores the converter channel count" \
	   "it is firmware state, exactly like the pin configuration defaults"
fi

if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "struct a1534_snapshot carries the channel count"
else
	if grep -q 'cvt_chan_count' "$CSRC"; then
		ok "struct a1534_snapshot carries the channel count"
	else
		no "struct a1534_snapshot carries the channel count" ""
	fi
fi

# The claim must stay attached to its evidence.
for f in docs/CLAIMS-AUDIT.md docs/PROJECT_STATE.md; do
	if grep -q 'cvt_chan_count' "$ROOT/$f"; then
		ok "$f records the channel-count finding"
	else
		no "$f records the channel-count finding" "the one measured cause must be written down"
	fi
done


echo "== 7d. Spurious wakeup diagnosis =="

WAKE="$TOOLS/macbook91-wake-probe"
t "macbook91-wake-probe parses" python3 -c \
	"import ast,sys; ast.parse(open(sys.argv[1]).read())" "$WAKE"

# Resume must be detected by the clocks, not by parsing a log or trusting a
# screen to have gone black. BOOTTIME counts time spent suspended, MONOTONIC
# does not, so their gap is the suspend duration and nothing else.
if grep -q 'CLOCK_BOOTTIME' "$WAKE" && grep -q 'CLOCK_MONOTONIC' "$WAKE"; then
	ok "suspend duration is measured from BOOTTIME minus MONOTONIC"
else
	no "suspend duration is measured from BOOTTIME minus MONOTONIC" \
	   "a blanked screen is not evidence that a suspend happened"
fi

# A zero-length suspend must be reported as "no suspend", never as success.
if grep -q 'NONE - the machine never actually suspended' "$WAKE"; then
	ok "a suspend that never happened is reported as such"
else
	no "a suspend that never happened is reported as such" ""
fi

# /proc/acpi/wakeup is a toggle. Writing a name flips it, so the prior state
# of every name has to be read first and only differing ones written.
if grep -q 'is a TOGGLE' "$TOOLS/macbook91-runner" &&
   awk '/^acpi_wake_disarm\(\)/,/^}/' "$TOOLS/macbook91-runner" | grep -q 'ACPI_WAKE_PRIOR\[\$n\]=\$cur'; then
	ok "ACPI wake sources have their prior state recorded before being toggled"
else
	no "ACPI wake sources have their prior state recorded before being toggled" \
	   "writing the name flips it; without the prior state a restore is a guess"
fi

if awk '/^acpi_wake_disarm\(\)/,/^}/' "$TOOLS/macbook91-runner" | grep -q 'if \[ "\$cur" = enabled \]'; then
	ok "a wake source that is already disabled is not toggled on"
else
	no "a wake source that is already disabled is not toggled on" \
	   "an unconditional write would ENABLE it"
fi

if awk '/^acpi_wake_restore\(\)/,/^}/' "$TOOLS/macbook91-runner" | grep -q 'NOT back to how they were found'; then
	ok "the wake restore verifies itself and prints manual recovery"
else
	no "the wake restore verifies itself and prints manual recovery" ""
fi

if grep -q 'acpi_wake_restore || true' "$TOOLS/macbook91-runner"; then
	ok "wake sources are restored from the exit trap"
else
	no "wake sources are restored from the exit trap" "an interrupted run must not leave them off"
fi

# ... and from the normal exit, which clears the trap first.
if awk '/^trap - EXIT INT TERM$/{f=1} f' "$TOOLS/macbook91-runner" | grep -q '^acpi_wake_restore || true$'; then
	ok "wake sources are restored on the normal exit too"
else
	no "wake sources are restored on the normal exit too" \
	   "a completed wake --disarm run would leave its wake sources off"
fi

# expect() followed by result() must list a test once: results.json is
# written one key per listed name, and a duplicate key is invalid evidence.
RUNNER_ORDER=$(bash -c 'set -u; declare -A RESULT_STATUS=() RESULT_DETAIL=(); declare -a RESULT_ORDER=() MANDATORY=(); log(){ :; }; die(){ echo "die $*"; exit 3; }; eval "$(awk "/^result\(\)/,/^}/" "$1")"; eval "$(awk "/^expect\(\)/,/^}/" "$1")"; expect a b; result a PASS x; result b FAIL y; result c PASS z; echo "${RESULT_ORDER[*]}"' _ "$TOOLS/macbook91-runner" 2>&1)
if [ "$RUNNER_ORDER" = "a b c" ]; then
	ok "the runner lists each result once"
else
	no "the runner lists each result once" "expect a b; result a b c gave '$RUNNER_ORDER'"
fi

if grep -q -- '--disarm needs root' "$TOOLS/macbook91-runner"; then
	ok "--disarm refuses cleanly without root"
else
	no "--disarm refuses cleanly without root" ""
fi

# jackstream records a live microphone capture and must never leave it on
# disk, whether the run finishes or is interrupted (V-01). The cleanup must
# be reachable from on_exit, which the top-level EXIT/INT/TERM trap already
# covers.
if awk '/^stop_jackstream\(\)/,/^}/' "$TOOLS/macbook91-runner" | grep -q 'rm -f "\$JACKSTREAM_CAPFILE"'; then
	ok "jackstream removes its capture file on cleanup"
else
	no "jackstream removes its capture file on cleanup" \
	   "an unbounded microphone recording must not survive a run"
fi

if awk '/^on_exit\(\)/,/^}/' "$TOOLS/macbook91-runner" | grep -q 'stop_jackstream'; then
	ok "jackstream cleanup is reachable from the EXIT/INT/TERM trap"
else
	no "jackstream cleanup is reachable from the EXIT/INT/TERM trap" \
	   "Ctrl-C or SIGTERM during jackstream must not orphan its recording or its processes"
fi

# A background *pipeline* (`gen | aplay &`) only exposes $! for the last
# stage, so the generator side is untrackable and, once aplay dies, respawns
# forever on the broken pipe (V-02). jackstream must connect the two stages
# through a FIFO so each process has its own trackable PID.
if grep -qE 'while :; do quiet_tone_seconds.*\| *aplay' "$TOOLS/macbook91-runner"; then
	no "jackstream tone generator has a trackable PID" \
	   "the untrackable respawning pipeline is still present"
elif grep -q 'quiet_tone_forever 4 >"\$JACKSTREAM_FIFO"' "$TOOLS/macbook91-runner" &&
     grep -q 'mkfifo "\$JACKSTREAM_FIFO"' "$TOOLS/macbook91-runner"; then
	ok "jackstream tone generator has a trackable PID"
else
	no "jackstream tone generator has a trackable PID" \
	   "expected a single long-lived generator connected through a FIFO"
fi

if awk '/^stop_jackstream\(\)/,/^}/' "$TOOLS/macbook91-runner" | grep -q 'JACKSTREAM_TONE_PID' &&
   awk '/^stop_jackstream\(\)/,/^}/' "$TOOLS/macbook91-runner" | grep -q 'JACKSTREAM_PLAY_PID'; then
	ok "jackstream stops both the tone generator and playback, not just one side of the pipeline"
else
	no "jackstream stops both the tone generator and playback, not just one side of the pipeline" ""
fi

# A jack that already reads the wanted state passes the poll at once and
# measures nothing: the 2026-09-15 and 2026-10-06 runs read 'on' at the first
# poll. jackstream must see the opposite state first, restart the capture after
# each transition and count those restarts in regress.concurrent_capture, and
# tell builds apart by the source hash, which srcversion did not
# (docs/INCIDENT-20261019.md).
CT_BODY=$(awk '/^\tcheck_transition\(\) \{/,/^\t\}/' "$TOOLS/macbook91-runner")
CT_FROM=$(grep -nF '[ "$(hp_jack_state)" = "$from" ] && break' <<<"$CT_BODY" | head -1 | cut -d: -f1)
CT_PROMPT=$(grep -nF 'log "$prompt"' <<<"$CT_BODY" | head -1 | cut -d: -f1)
if [ -n "$CT_FROM" ] && [ -n "$CT_PROMPT" ] && [ "$CT_FROM" -lt "$CT_PROMPT" ]; then
	ok "jackstream sees the jack in the opposite state before each prompt"
else
	no "jackstream sees the jack in the opposite state before each prompt" \
	   "wait for the opposite state at line ${CT_FROM:-none}, prompt at line ${CT_PROMPT:-none} of check_transition"
fi
if grep -qF 'result "$name.capture_restart"' <<<"$CT_BODY" &&
   grep -qF 'jackstream.plug.capture_restart jackstream.unplug.capture_restart' "$TOOLS/macbook91-runner"; then
	ok "jackstream restarts the capture after each transition and counts it"
else
	no "jackstream restarts the capture after each transition and counts it" \
	   "need a \$name.capture_restart result and both restarts in the regress.concurrent_capture rollup"
fi
if grep -qF 'adc_stream_tags' <<<"$CT_BODY"; then
	ok "jackstream records the capture converters' stream tags"
else
	no "jackstream records the capture converters' stream tags" "adc_stream_tags is not used in check_transition"
fi
RI_BODY=$(awk '/^read_identity\(\)/,/^}/' "$TOOLS/macbook91-runner")
CI_BODY=$(awk '/^check_identity\(\)/,/^}/' "$TOOLS/macbook91-runner")
if grep -qF '/sys/module/snd_hda_codec_cs420x/version' <<<"$RI_BODY" &&
   grep -qF 'modinfo -F version' <<<"$RI_BODY" &&
   grep -qF '${LOADED_VER#*+}' <<<"$CI_BODY"; then
	ok "runner identity compares the module's source hash, not only srcversion"
else
	no "runner identity compares the module's source hash, not only srcversion" \
	   "srcversion stayed the same when only a1534_pcm.h changed"
fi
unset CT_BODY CT_FROM CT_PROMPT RI_BODY CI_BODY

# Fixture: a before/after pair with a four-second gap must read as a failure,
# and one with a long gap as a pass.
FX=$(mktemp -d)
python3 - "$FX" <<'FIXTURE'
import json, sys, copy
d = sys.argv[1]
base = {"utc": "x", "clocks": {"monotonic": 100.0, "boottime": 100.0},
        "gpe": {"gpe07": "10", "gpe66": "5"}, "devices": {}, "power": {}}
short = copy.deepcopy(base)
short["clocks"] = {"monotonic": 102.0, "boottime": 106.0}      # 4 s suspended
short["gpe"]["gpe66"] = "6"
long = copy.deepcopy(base)
long["clocks"] = {"monotonic": 102.0, "boottime": 1002.0}      # 900 s
none = copy.deepcopy(base)
none["clocks"] = {"monotonic": 102.0, "boottime": 102.0}       # never slept
for n, o in (("a", base), ("short", short), ("long", long), ("none", none)):
    json.dump(o, open("%s/%s.json" % (d, n), "w"))
FIXTURE
out=$("$WAKE" diff "$FX/a.json" "$FX/short.json" 2>&1)
if contains_str "$out" "came back after 4 s" && contains_str "$out" "gpe66" ; then
	ok "a four-second suspend is reported as something waking the machine"
else
	no "a four-second suspend is reported as something waking the machine" "$out"
fi
out=$("$WAKE" diff "$FX/a.json" "$FX/long.json" 2>&1)
if contains_str "$out" "Nothing woke it early"; then
	ok "a long suspend is reported as clean"
else
	no "a long suspend is reported as clean" "$out"
fi
out=$("$WAKE" diff "$FX/a.json" "$FX/none.json" 2>&1)
if contains_str "$out" "no suspend happened at all"; then
	ok "a suspend that did not happen is not reported as clean"
else
	no "a suspend that did not happen is not reported as clean" "$out"
fi
rm -rf "$FX"


# The GPE-to-device map is read straight out of the DSDT's AML, because iasl
# is not installed and the table is root-only. The encoding is checked against
# synthetic bytes so the parser is not first exercised on the real table.
if python3 - "$WAKE" <<'PRW'
import sys
src = open(sys.argv[1]).read()
src = src[:src.rindex("\nif __name__")]
g = {"__name__": "wp"}
exec(compile(src, "wp", "exec"), g)
parse, pkl = g["parse_prw"], g["_pkglength"]
assert pkl(bytes([0x05]), 0) == (5, 1), "short PkgLength"
assert pkl(bytes([0x41, 0x02]), 0) == (0x21, 2), "two-byte PkgLength"
def prw(gpe):
    return b"\x08_PRW\x12" + bytes([0x06, 2, 0x0A, gpe, 0x0A, 0x03])
aml = b"\x00" * 16 + prw(0x6F) + b"\xff" * 8 + prw(0x0D) \
      + b"\x08_PRW\x12\x06\x02\x00\x0A\x03"
got = [v for _, v in parse(aml)]
assert got == [0x6F, 0x0D, 0x00], got
PRW
then
	ok "the DSDT _PRW parser reads BytePrefix, ZeroOp and multi-byte PkgLength"
else
	no "the DSDT _PRW parser reads BytePrefix, ZeroOp and multi-byte PkgLength" \
	   "the AML encoding must be verified on synthetic bytes, not first on the real table"
fi

# The positional device match is a heuristic and must say so.
if grep -q 'That is a heuristic' "$WAKE" && grep -q 'NOT reliable' "$WAKE"; then
	ok "the GPE-to-device match is labelled a heuristic"
else
	no "the GPE-to-device match is labelled a heuristic" \
	   "_PRW order is not a parsed device scope; it must not be presented as one"
fi


# Sleep hooks were the blind spot that cost a round of measurement: a hook
# that rewrites /proc/acpi/wakeup in its pre stage changes the armed set
# between the snapshot and the suspend, so the snapshot describes a state the
# machine was never in. The probe must capture them.
if grep -q "s\['sleep_hooks'\]" "$WAKE" && grep -q 'systemd_runs_this' "$WAKE"; then
	ok "the wake probe captures the sleep-hook directories"
else
	no "the wake probe captures the sleep-hook directories" \
	   "a pre-hook can rewrite the armed set behind the measurement"
fi

# systemd runs ONLY /usr/lib/systemd/system-sleep/. A script in
# /etc/systemd/system-sleep/ never executes, and that must be said out loud
# rather than silently ignored.
if python3 - "$WAKE" <<'HOOKS'
import sys
src = open(sys.argv[1]).read()
src = src[:src.rindex("\nif __name__")]
g = {"__name__": "wp"}
exec(compile(src, "wp", "exec"), g)
warn = g["hook_warnings"]

# a hook in the directory systemd does NOT read must be reported as dead
s = {"sleep_hooks": {"/etc/systemd/system-sleep": {
        "systemd_runs_this": False,
        "entries": {"mine": {"executable": True, "touches_acpi_wakeup": True}}}}}
w = warn(s)
assert len(w) == 1 and "never runs" in w[0], w

# a hook that rewrites the armed set in the directory systemd DOES read must
# be reported as invalidating the listing
s = {"sleep_hooks": {"/usr/lib/systemd/system-sleep": {
        "systemd_runs_this": True,
        "entries": {"mine": {"executable": True, "touches_acpi_wakeup": True}}}}}
w = warn(s)
assert len(w) == 1 and "not the one listed" in w[0], w

# an ordinary hook that touches nothing must produce no noise
s = {"sleep_hooks": {"/usr/lib/systemd/system-sleep": {
        "systemd_runs_this": True,
        "entries": {"tlp": {"executable": True, "touches_acpi_wakeup": False}}}}}
assert warn(s) == [], warn(s)
HOOKS
then
	ok "a hook in a directory systemd does not read is reported as never running"
else
	no "a hook in a directory systemd does not read is reported as never running" \
	   "/etc/systemd/system-sleep/ is a widely repeated mistake and must be caught"
fi

# And the fact itself, checked against this machine rather than remembered.
#
# Deliberately not `strings ... | grep -q`. Under `set -o pipefail` that
# returns 141 when grep -q matches early enough to SIGPIPE strings, so a
# present string reads as absent. This suite has now been bitten by that
# pipeline four separate times; the output is materialised once instead.
SLEEPBIN=/usr/lib/systemd/systemd-sleep
SLEEPSTR=$(strings "$SLEEPBIN" 2>/dev/null || true)
if contains_str "$SLEEPSTR" '^/usr/lib/systemd/system-sleep$' &&
   ! contains_str "$SLEEPSTR" '^/etc/systemd/system-sleep$'; then
	ok "systemd-sleep on this machine contains only the /usr/lib hook path"
elif [ ! -r "$SLEEPBIN" ]; then
	blocked "systemd-sleep on this machine contains only the /usr/lib hook path" \
	        "binary not readable"
else
	no "systemd-sleep on this machine contains only the /usr/lib hook path" \
	   "the assumption behind the hook diagnosis no longer holds - re-check it"
fi

echo "== 7e. Concurrent-capture / jack-power census =="

# vendored/PROVENANCE.md records the risk: the headphone jack callback
# replays the bring-up, which cycles the whole audio function group through
# D3/D0 - and putting the AFG in D3 powers down every widget beneath it,
# including a running capture's ADCs. This is not a safety property; it is a
# tripwire. If a future re-vendoring of the trace changes these counts, the
# risk assessment must be redone, and this census is what says so. A run on
# 2026-09-15 seemed to settle it, but the headphones were already in when it
# asked for the plug; on 2026-10-19 a real plug stopped a running capture
# (docs/INCIDENT-20261019.md), and the driver now re-programs the capture
# converter after every replay. (This comment used to point at a plan that is
# no longer tracked and at docs/JACK-POWER-RISK.md, which never existed.)
afg_power_census() {  # afg_power_census START_LINE END_LINE
	local start="$1" end="$2" d3 d0
	d3=$(awk -v s="$start" -v e="$end" 'NR==s,NR==e' "$SRC/vendored/a1534_sequence.h" \
		| grep -c 'codec->core\.afg, 0, AC_VERB_SET_POWER_STATE, 0x00000003')
	d0=$(awk -v s="$start" -v e="$end" 'NR==s,NR==e' "$SRC/vendored/a1534_sequence.h" \
		| grep -c 'codec->core\.afg, 0, AC_VERB_SET_POWER_STATE, 0x00000000')
	printf '%s %s' "$d3" "$d0"
}

if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "headphones_a1534(): AFG D3/D0 census matches (8/9)" \
	            "setup_a1534(): AFG D3/D0 census matches (46/46)" \
	            "play_a1534(): AFG D3/D0 census matches (0/1)"
else
	HP_START=$(grep -n '^static int headphones_a1534' "$SRC/vendored/a1534_sequence.h" | head -1 | cut -d: -f1)
	SETUP_START=$(grep -n '^static int setup_a1534' "$SRC/vendored/a1534_sequence.h" | head -1 | cut -d: -f1)
	PLAY_START=$(grep -n '^static int play_a1534' "$SRC/vendored/a1534_sequence.h" | head -1 | cut -d: -f1)
	FILE_END=$(wc -l < "$SRC/vendored/a1534_sequence.h")

	check_afg_census() {  # check_afg_census NAME START END WANT_D3 WANT_D0
		local name="$1" start="$2" end="$3" want_d3="$4" want_d0="$5" got
		got=$(afg_power_census "$start" "$((end - 1))")
		if [ "$got" = "$want_d3 $want_d0" ]; then
			ok "$name: AFG D3/D0 census matches ($want_d3/$want_d0)"
		else
			no "$name: AFG D3/D0 census matches ($want_d3/$want_d0)" \
			   "got '$got' (D3 D0) - the vendored trace changed; redo the risk assessment"
		fi
	}

	# Measured directly from the trace during this audit: headphones_a1534() (runs
	# from a1534_hp_jack_callback() when headphones are plugged) cycles the AFG
	# into D3 eight times and into D0 nine times; play_a1534() (runs on unplug)
	# only ever brings it back to D0, once. setup_a1534() is not reached from the
	# jack callback at all, but is counted too because it cycles the AFG far more
	# (46/46) - relevant if it is ever called with a stream running.
	check_afg_census "headphones_a1534()" "$HP_START" "$SETUP_START" 8 9
	check_afg_census "setup_a1534()"      "$SETUP_START" "$PLAY_START" 46 46
	check_afg_census "play_a1534()"       "$PLAY_START" "$((FILE_END + 1))" 0 1
fi

echo "== 8. Hardware-only gates =="
for g in "A1534 fixup actually selected at probe" \
         "amplifier bring-up produces sound" \
         "microphone capture" \
         "deep suspend/resume" \
         "DKMS rebuild across a kernel update" \
         "rollback to the stock codec"; do
	blocked "$g" "requires installing and loading the module on the machine"
done
# regress.concurrent_capture / regress.jack_hotplug_stream: measured on
# hardware (docs/test-status.json; a real plug stopped a running capture on
# 2026-10-19). This suite cannot re-run them, so they stay BLOCKED here with
# the command that does.
blocked "headphone hotplug with a running stream (regress.jack_hotplug_stream)" \
        "resolve with: sudo ./tools/macbook91-runner jackstream"
blocked "concurrent capture during a headphone power transition (regress.concurrent_capture)" \
        "resolve with: sudo ./tools/macbook91-runner jackstream"


echo "== 9. Nothing personal in the repository =="

# This repository is published. Nothing tracked in it may carry the maintainer's
# name, their mail address, an absolute path through their home directory, or
# machine-identifying data. Upstream kernel authors' addresses stay: they are
# GPL attribution, not personal data of this machine's owner.
priv_scan() {  # priv_scan NAME PATTERN [EXCLUDE_PATTERN [case]]
	local name=$1 pat=$2 excl=${3:-} flags=-nIiE
	[ "${4:-}" = case ] && flags=-nIE
	local hits
	hits=$(git -C "$ROOT" ls-files -z -- . ':!private' | xargs -0 grep "$flags" -- "$pat" 2>/dev/null || true)
	[ -n "$excl" ] && hits=$(printf '%s' "$hits" | grep -viE -- "$excl" || true)
	if [ -z "$hits" ]; then
		ok "no $name in tracked files"
	else
		no "no $name in tracked files" "$(printf '%s' "$hits" | head -5)"
	fi
}

# The patterns below use single-character classes so that this file does not
# itself contain the literal strings it searches for: a bracketed letter
# matches the plain spelling and is not matched by it.
priv_scan "owner name or mail"       'p[a]trick|post[e]o|p9[4]\+'
priv_scan "absolute home paths"      '/home/[a-z0-9_-]+'
priv_scan "MAC addresses"            '\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b'
priv_scan "private IPv4 addresses"   '\b(192\.168|10\.[0-9]|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+'
priv_scan "disk or LUKS UUIDs"       '\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
# Serials are upper case, and this one scan is case-sensitive: matched
# without case it also finds lower-case hex digests, such as a sha256 in
# packaging/upstream.lock that starts with c0 and a digit.
priv_scan "Apple hardware serials"   '\b(C0[0-9]|FVF|DLX|F5K)[A-Z0-9]{8,}\b' '' case

# Mail addresses: only upstream kernel authors are allowed.
MAILS=$(git -C "$ROOT" ls-files -z -- . ':!private' \
	| xargs -0 grep -hoIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 2>/dev/null \
	| sort -u || true)
# The maintainer's public GitHub noreply address is the PKGBUILD maintainer line.
UNEXPECTED=$(printf '%s\n' "$MAILS" | grep -vE '^(tiwai@suse\.de|matt\.ranostay@konsulko\.com|noreply@anthropic\.com|748975\+Weegee@users\.noreply\.github\.com)$' || true)
if [ -z "$UNEXPECTED" ]; then
	ok "the only mail addresses are upstream kernel authors and public noreply identities"
else
	no "the only mail addresses are upstream kernel authors and public noreply identities" "$(printf '%s' "$UNEXPECTED" | head -5)"
fi

# The private evidence directory must never become tracked.
if git -C "$ROOT" ls-files | grep -q '^\.conte[x]t/'; then
	no "the local evidence directory is not tracked" "private evidence must stay out of Git"
else
	ok "the local evidence directory is not tracked"
fi

# A tracked symbolic link would travel into an exported snapshot as a link,
# possibly one that points outside the tree. None is tracked.
SYMLINKS=$(git -C "$ROOT" ls-files -s | grep '^120000 ' | cut -f2 | head -5 || true)
if [ -z "$SYMLINKS" ]; then
	ok "the repository tracks no symbolic link"
else
	no "the repository tracks no symbolic link" "$(printf '%s' "$SYMLINKS" | tr '\n' ' ')"
fi

echo "== 9b. Withdrawn claims must not reappear =="

# These phrases described conclusions that were independently measured and
# then withdrawn (docs/CLAIMS-AUDIT.md). This is the second time they have had
# to be chased out of the source tree; a grep test costs nothing to keep them out.
# Excludes this test file itself: it legitimately names these phrases while
# testing that docs/ withdraws them (see the "not fixable" checks above and
# the a1534_amp regression test).
WITHDRAWN_HITS=$(git -C "$ROOT" ls-files -z -- src tools packaging Makefile README.md ':!:tests/run-tests.sh' \
	| xargs -0 grep -nIiE -- \
	  'need a reboot|cannot be restored from the driver|not fixable|demonstrably not answering' \
	  2>/dev/null || true)
if [ -z "$WITHDRAWN_HITS" ]; then
	ok "no withdrawn claim reappears in the source tree"
else
	no "no withdrawn claim reappears in the source tree" "$(printf '%s' "$WITHDRAWN_HITS" | head -5)"
fi

echo "== 9c. Machine-readable status stays true =="

STATUS_JSON="$ROOT/docs/test-status.json"

if python3 -c "import json,sys; d=json.load(open(sys.argv[1]))" "$STATUS_JSON" 2>/dev/null; then
	ok "docs/test-status.json parses"
else
	no "docs/test-status.json parses" "invalid JSON"
fi

# Every gate id unique, every status one of the five legend values, blocker
# non-empty (AC-003-2).
STATUS_CHECK=$(mktemp)
python3 - "$STATUS_JSON" > "$STATUS_CHECK" 2>&1 <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
legend = set(d["legend"].keys())
ids = [g["id"] for g in d["gates"]]
problems = []
if len(ids) != len(set(ids)):
	dupes = sorted({i for i in ids if ids.count(i) > 1})
	problems.append("duplicate gate ids: " + ", ".join(dupes))
bad_status = [g["id"] for g in d["gates"] if g["status"] not in legend]
if bad_status:
	problems.append("gates with a non-legend status: " + ", ".join(bad_status))
if not d.get("blocker", "").strip():
	problems.append("blocker is empty")
if problems:
	print("\n".join(problems))
	sys.exit(1)
PY
if [ $? -eq 0 ]; then
	ok "every gate id is unique, every status is legend-valid, blocker is non-empty"
else
	no "every gate id is unique, every status is legend-valid, blocker is non-empty" "$(cat "$STATUS_CHECK")"
fi
rm -f "$STATUS_CHECK"

# If any gate carrying a declared release blocker is NOT_RUN, BLOCKED or FAIL,
# the summary must mention it by id (AC-003-3). This is what stops the summary
# from being silently emptied again. FAIL counts since 2026-10-19, when
# regress.concurrent_capture failed a real plug.
BLOCKER_GATES="regress.concurrent_capture regress.jack_hotplug_stream fix.capture_resync_after_jack_replay"
STATUS_CHECK2=$(mktemp)
python3 - "$STATUS_JSON" "$BLOCKER_GATES" > "$STATUS_CHECK2" 2>&1 <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
gate_ids = sys.argv[2].split()
by_id = {g["id"]: g for g in d["gates"]}
blocker_text = d.get("blocker", "")
missing = []
for gid in gate_ids:
	g = by_id.get(gid)
	if g and g["status"] in ("NOT_RUN", "BLOCKED", "FAIL") and gid not in blocker_text:
		missing.append(gid)
if missing:
	print("declared-blocker gate(s) not named in 'blocker': " + ", ".join(missing))
	sys.exit(1)
PY
if [ $? -eq 0 ]; then
	ok "unresolved release-blocker gates are named in the status summary"
else
	no "unresolved release-blocker gates are named in the status summary" "$(cat "$STATUS_CHECK2")"
fi
rm -f "$STATUS_CHECK2"

# Four checks remain before the summary: AC-003-8, AC-003-9, AC-003-4
# (regress.suite) and AC-008-11 (README.md). All four assert some recorded
# number equals the actual final total, so they are computed against one
# shared FINAL_COUNT rather than each other's running PASS - otherwise every
# later check in the batch would silently need to be one higher than the
# last.
FINAL_COUNT=$((PASS + 4))

# The version named as the current promoted package in PROJECT_STATE.md must
# equal source_hash in test-status.json and the newest release/*/ directory
# (AC-003-8, R2-01). Mechanical, so this class of contradiction cannot recur.
PROJECT_STATE_MD="$ROOT/docs/PROJECT_STATE.md"
STATUS_CHECK3=$(mktemp)
python3 - "$STATUS_JSON" "$PROJECT_STATE_MD" "$ROOT/release" > "$STATUS_CHECK3" 2>&1 <<'PY'
import json, os, re, sys
status_path, state_path, release_dir = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(status_path))
source_hash = d.get("source_hash", "")
text = open(state_path).read()
m = re.search(
	# Versions before 20261006.01 were MAJOR.MINOR.PATCH, since then
	# YYYYMMDD.NN like the maintainer's other packages; both forms are accepted.
	r'\*\*Current promoted package:\*\* `macbook91-cs4208(?:-dkms)? ([0-9]+(?:\.[0-9]+)+)-1`',
	text,
)
stated = m.group(1) if m else None


def vkey(v):
	return tuple(int(x) for x in v.split("."))


releases = sorted(
	(n for n in os.listdir(release_dir) if os.path.isdir(os.path.join(release_dir, n))),
	key=vkey,
)
newest = releases[-1] if releases else None
problems = []
if stated is None:
	problems.append("PROJECT_STATE.md has no 'Current promoted package' line")
if stated != source_hash:
	problems.append("PROJECT_STATE.md=%r source_hash=%r" % (stated, source_hash))
if stated != newest:
	problems.append("PROJECT_STATE.md=%r newest release/=%r" % (stated, newest))
if problems:
	print("; ".join(problems))
	sys.exit(1)
PY
if [ $? -eq 0 ]; then
	ok "PROJECT_STATE.md's current promoted package matches source_hash and the newest release/ directory"
else
	no "PROJECT_STATE.md's current promoted package matches source_hash and the newest release/ directory" \
	   "$(cat "$STATUS_CHECK3")"
fi
rm -f "$STATUS_CHECK3"

# Neither freshness signal may understate its own age (AC-003-9, R2-02).
# test-status.json's "updated" must not precede the newest date in any gate
# note - unchanged, effective. PROJECT_STATE.md's header "updated" date is
# checked against the file's own last change (git log -1, or today if the
# file is dirty), not just its own prose: a paragraph that carries no date
# at all defeats a body-only check, which is exactly what happened in
# an earlier release promotion (R3-02). The body-date comparison is kept as a second, weaker
# clause - it costs nothing and catches a different mistake. If git history
# for the file is unavailable (a fresh git init, an export), the check
# degrades to the body-date clause alone and says so, rather than passing
# silently as if the stronger check ran.
STATUS_CHECK4=$(mktemp)
GIT_LAST_CHANGE=$(git -C "$ROOT" log -1 --format=%cs -- docs/PROJECT_STATE.md 2>/dev/null || true)
GIT_DIRTY=""
[ -n "$(git -C "$ROOT" status --porcelain -- docs/PROJECT_STATE.md 2>/dev/null)" ] && GIT_DIRTY=1
python3 - "$STATUS_JSON" "$PROJECT_STATE_MD" "$GIT_LAST_CHANGE" "$GIT_DIRTY" > "$STATUS_CHECK4" 2>&1 <<'PY'
import json, re, sys, datetime
status_path, state_path, git_last_change, git_dirty = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(status_path))
updated = d.get("updated", "")
date_re = re.compile(r'\b(20\d{2}-\d{2}-\d{2})\b')
note_dates = []
for g in d["gates"]:
	note_dates += date_re.findall(g.get("note", ""))
newest_note_date = max(note_dates) if note_dates else None
problems = []
degraded = False
if newest_note_date and updated < newest_note_date:
	problems.append(
		"test-status.json updated=%r but a gate note carries %r" % (updated, newest_note_date)
	)
state_text = open(state_path).read()
header_m = re.search(r'^Version \S+ \S+ updated (20\d{2}-\d{2}-\d{2})', state_text, re.MULTILINE)
header_date = header_m.group(1) if header_m else None
body_dates = date_re.findall(state_text[header_m.end():] if header_m else state_text)
newest_body_date = max(body_dates) if body_dates else None
if header_date is None:
	problems.append("PROJECT_STATE.md has no parseable Version/updated header line")
else:
	if newest_body_date and header_date < newest_body_date:
		problems.append(
			"PROJECT_STATE.md header updated=%r but the body carries %r (weaker check)"
			% (header_date, newest_body_date)
		)
	if git_last_change:
		required = datetime.date.today().isoformat() if git_dirty else git_last_change
		if header_date < required:
			basis = "is uncommitted, so today" if git_dirty else "git log"
			problems.append(
				"PROJECT_STATE.md header updated=%r but its last change (%s) is %r"
				% (header_date, basis, required)
			)
	else:
		degraded = True
if problems:
	print("; ".join(problems))
	sys.exit(1)
if degraded:
	print("DEGRADED: no git history for docs/PROJECT_STATE.md - checked body dates only, not the file's last change")
PY
RC4=$?
NOTE4=$(cat "$STATUS_CHECK4")
if [ $RC4 -eq 0 ]; then
	if [ -n "$NOTE4" ]; then
		ok "test-status.json and PROJECT_STATE.md's freshness dates are not older than their own newest content ($NOTE4)"
	else
		ok "test-status.json and PROJECT_STATE.md's freshness dates are not older than their own newest content"
	fi
else
	no "test-status.json and PROJECT_STATE.md's freshness dates are not older than their own newest content" "$NOTE4"
fi
rm -f "$STATUS_CHECK4"

# The last two checks compare a recorded total against this run's own. A run
# that had to block part of the suite has a smaller total by construction,
# so comparing it against the number a complete run recorded would report a
# missing generated file as a stale document. Blocked, with the reason.
# The recorded totals are those of a host with the replacement module loaded,
# where "verifier fails on the stock codec" is BLOCKED. On a host that still
# runs the stock codec that test runs and passes: one more passed, one fewer
# blocked, so the recorded totals do not apply there and the checks are
# BLOCKED, not failed.
if [ "$ASSEMBLED" = 0 ]; then
	gen_blocked "regress.suite matches this run's actual counts" \
	            "README.md's hermetic test count matches this run's actual count"
elif [ "${PKG_AUDITED:-0}" != 1 ]; then
	# The recorded totals come from a run that audited a built package;
	# without one the package checks are BLOCKED and the totals differ.
	for n in "regress.suite matches this run's actual counts" \
	         "README.md's hermetic test count matches this run's actual count"; do
		blocked "$n" "no built package in dist/ - build one (make arch-pkg or arch-pkg-dev) for a complete run"
	done
elif [ "$STOCK_CODEC_TEST_RAN" = 1 ]; then
	for n in "regress.suite matches this run's actual counts" \
	         "README.md's hermetic test count matches this run's actual count"; do
		blocked "$n" "this host runs the stock codec, so 'verifier fails on the stock codec' ran; the recorded totals are those of a host with the replacement module loaded"
	done
else
	# regress.suite's recorded counts must match what this run actually reports
	# (AC-003-4).
	RECORDED_SUITE=$(python3 -c "
	import json
	d = json.load(open('$STATUS_JSON'))
	g = next(g for g in d['gates'] if g['id'] == 'regress.suite')
	print(g['note'])
	")
	EXPECTED_SUITE="tests/run-tests.sh: $FINAL_COUNT passed, $FAIL failed, $BLOCKED blocked"
	case "$RECORDED_SUITE" in
		"$EXPECTED_SUITE"*)
			ok "regress.suite matches this run's actual counts" ;;
		*)
			no "regress.suite matches this run's actual counts" \
			   "recorded '$RECORDED_SUITE', this run says '$EXPECTED_SUITE'" ;;
	esac

	# README.md's hand-written hermetic-test count must match the actual total,
	# so a future suite change can no longer leave it stale (AC-008-11, R2-03).
	README_MD="$ROOT/README.md"
	STATED_COUNT=$(grep -oE 'tests/[[:space:]]+[0-9]+ hermetic tests' "$README_MD" | grep -oE '[0-9]+')
	if [ "$STATED_COUNT" = "$FINAL_COUNT" ]; then
		ok "README.md's hermetic test count matches this run's actual count"
	else
		no "README.md's hermetic test count matches this run's actual count" \
		   "README.md states '${STATED_COUNT:-<none>}', this run says '$FINAL_COUNT'"
	fi
fi

echo
printf '%d passed, %d failed, %d blocked\n' "$PASS" "$FAIL" "$BLOCKED"
[ "$FAIL" -eq 0 ]
