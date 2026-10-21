#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Static check of the A1534 locking rule.

The first test build wedged the codec with an AB-BA deadlock: the unsolicited
jack callback held st->lock while replaying ~1700 verbs, the first of which
triggered a runtime resume, whose .resume callback then blocked on that same
lock.

The rule that prevents it: never call anything that can trigger runtime PM
while holding st->lock, and always take the PM reference before the lock.
An unlock nested deeper than its lock (unlock; goto out;) is an early exit and
does not end the region.

A second lock joined on 2026-10-19: the capture converter resync needs the HDA
bus prepare_mutex. snd_hda_codec_prepare() holds prepare_mutex while it calls
a1534_playback_prepare(), which takes st->lock, so prepare_mutex must never be
taken while st->lock is held, and a1534_capture_resync() may only run under
prepare_mutex or from the capture hook, which prepare already runs under.
"""
import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src/cs420x-a1534/a1534_pcm.h"
if len(sys.argv) > 1:
    SRC = Path(sys.argv[1])

# Scoped lock forms this line-based check cannot follow; refuse them.
SCOPED = re.compile(r"\b(?:scoped_)?guard\s*\(\s*mutex\s*\)?\s*[(,]\s*&st->lock")

# Calls that can block on runtime PM, directly or through a codec read.
PM_TRIGGERING = re.compile(
    r"\b(setup_a1534|play_a1534|headphones_a1534|snd_hda_jack_detect|"
    r"snd_hda_power_up_pm|snd_hda_jack_detect_enable_callback)\s*\("
)

PREPARE_LOCK = "mutex_lock(&codec->bus->prepare_mutex)"
PREPARE_UNLOCK = "mutex_unlock(&codec->bus->prepare_mutex)"
# Scoped forms of the prepare lock cannot be followed either.
SCOPED_PREPARE = re.compile(
    r"\b(?:scoped_)?guard\s*\(\s*mutex\s*\)?\s*[(,]\s*&codec->bus->prepare_mutex"
)
# A call of the capture resync, not its definition.
RESYNC_CALL = re.compile(r"\ba1534_capture_resync\s*\(\s*codec\s*\)\s*;")
# The start of a function definition or prototype, to name the caller.
FUNC_START = re.compile(r"^static [^;=]*?\b(\w+)\s*\(")
# The capture hook runs from snd_hda_codec_prepare(), under prepare_mutex.
RESYNC_UNDER_PREPARE = {"a1534_capture_hook"}

def main() -> int:
    text = SRC.read_text()
    # Indentation of each open mutex_lock(&st->lock). An unlock nested deeper
    # than its lock is an early exit from inside a branch (unlock; goto out;):
    # the fall-through path still holds the lock, so the region goes on.
    held = []
    failures = []
    # prepare_mutex regions have no early exits, so a depth counter will do.
    prepare_depth = 0
    func = None
    for lineno, line in enumerate(text.splitlines(), 1):
        indent = len(line) - len(line.lstrip())
        start = FUNC_START.match(line)
        if start:
            func = start.group(1)
        if SCOPED.search(line):
            failures.append((lineno, "st->lock taken through guard()/scoped_guard(); "
                             "this check only follows mutex_lock/mutex_unlock"))
        if SCOPED_PREPARE.search(line):
            failures.append((lineno, "prepare_mutex taken through guard()/scoped_guard(); "
                             "this check only follows mutex_lock/mutex_unlock"))
        if PREPARE_LOCK in line:
            if held:
                failures.append((lineno, "prepare_mutex taken while st->lock is held "
                                 "(snd_hda_codec_prepare() takes them the other way round)"))
            prepare_depth += 1
        if (RESYNC_CALL.search(line) and not prepare_depth
                and func not in RESYNC_UNDER_PREPARE):
            failures.append((lineno, f"a1534_capture_resync() called in {func}() "
                             "without prepare_mutex"))
        if PREPARE_UNLOCK in line and prepare_depth:
            prepare_depth -= 1
        if "mutex_lock(&st->lock)" in line:
            held.append(indent)
        if held and PM_TRIGGERING.search(line):
            failures.append((lineno, line.strip()))
        if "mutex_unlock(&st->lock)" in line and held and indent <= held[-1]:
            held.pop()

    if held:
        failures.append((0, f"unbalanced st->lock ({len(held)} open at EOF)"))
    if prepare_depth:
        failures.append((0, f"unbalanced prepare_mutex ({prepare_depth} open at EOF)"))

    # Every function that takes the lock and then does codec I/O must hold a
    # PM reference for the whole region.
    for name in ("a1534_hp_jack_callback", "a1534_playback_prepare",
                 "a1534_playback_cleanup"):
        # Locate the definition itself, then take the body up to the first
        # line that is a bare closing brace. A greedy regex here would span
        # into the preceding function and report false violations.
        m = re.search(rf"^static [^\n]*\b{name}\(", text, re.M)
        if not m:
            failures.append((0, f"{name}() not found"))
            continue
        end = text.find("\n}", m.start())
        body = text[m.start():end if end != -1 else len(text)]
        if "snd_hda_power_up_pm" not in body or "snd_hda_power_down_pm" not in body:
            failures.append((0, f"{name}() does not hold a runtime-PM reference"))
            continue
        up = body.index("snd_hda_power_up_pm")
        lock = body.find("mutex_lock(&st->lock)")
        if lock != -1 and up > lock:
            failures.append((0, f"{name}() takes st->lock before the PM reference"))

    for lineno, what in failures:
        where = f"a1534_pcm.h:{lineno}: " if lineno else ""
        print(f"  FAIL  {where}{what}")
    if failures:
        print(f"\n{len(failures)} locking violation(s)")
        return 1
    print("  PASS  no PM-triggering call runs under st->lock")
    print("  PASS  every locking function takes its PM reference first")
    print("  PASS  prepare_mutex is never taken under st->lock")
    print("  PASS  the capture resync runs under prepare_mutex")
    return 0

if __name__ == "__main__":
    sys.exit(main())
