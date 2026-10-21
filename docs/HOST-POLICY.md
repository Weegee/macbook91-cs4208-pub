# Host audio policy: power_save and RTKit

Written 2026-10-14 in answer to a handoff from the macbook91-hw-fixes project, which reviewed
`journalctl -b -p4` on the test machine. Both questions concern host configuration that this package does not own.
Labels: **VERIFIED** = read or measured on the MacBook9,1 with the command named; **NOT VERIFIED** =
inferred or reported, not measured; **REFUTED** = checked and found false.
Names of local power-management hooks are written `legacy-hook-<name>`; the real file names differ.

## 1. snd_hda_intel power_save

### 1.1 Decision

The package ships **no power_save policy**: no udev rule, no `/etc/modprobe.d` file. The values
host tools set stay. The kernel default is 10 (`CONFIG_SND_HDA_POWER_SAVE_DEFAULT=10`). cachyos-settings asks
for 0 on AC power and on battery restores the saved value, or 10 when none is saved. On the test machine the value in effect
is 1 on battery and on AC (both VERIFIED, 1.2). TLP writes it at a battery boot (VERIFIED); that TLP is
also what rewrites it to 1 on AC, on every power-supply event, is an inference (NOT VERIFIED, 1.2). The
udev error messages are a cachyos-settings defect that upstream has already fixed (1.4); they are documented
here, not overridden.

### 1.2 Evidence

| Claim | Status | How |
| --- | --- | --- |
| On battery `power_save` is 1 and `power_save_controller` is Y | VERIFIED 2026-10-14 | `cat /sys/module/snd_hda_intel/parameters/power_save{,_controller}`, BAT0 `Discharging`, ADP1 `online=0` |
| On AC power `power_save` is also 1, although cachyos-settings' AC rule writes 0 | VERIFIED 2026-10-14 09:53 | same command, BAT0 `Charging`, ADP1 `online=1`; the rule's state file holds `1` (written 09:43:28 by the AC rule, which saves the old value before writing 0) |
| The kernel default is 10 | VERIFIED 2026-10-14 | `zcat /proc/config.gz \| grep SND_HDA_POWER_SAVE_DEFAULT` prints `CONFIG_SND_HDA_POWER_SAVE_DEFAULT=10`; no `power_save` in `/etc/modprobe.d`, `/usr/lib/modprobe.d` or `/proc/cmdline` |
| TLP is the writer of the battery value 1 | VERIFIED 2026-10-14 for battery boots | boot 0 on battery: the card0 rule fails at 08:57:20, `journalctl -b 0 -u tlp` shows `tlp[1045]: Applying power save settings...done.` at 08:57:22, and the value read afterwards on battery is 1; TLP's `SOUND_POWER_SAVE_ON_BAT` defaults to 1 (`/usr/share/tlp/defaults.conf:49`) |
| TLP is the writer that puts it back to 1 on AC | NOT VERIFIED (inference) | tlp 1.10.2 is active (`systemctl is-active tlp`); `/usr/lib/udev/rules.d/85-tlp.rules` runs `tlp auto` on every power_supply change; `/usr/share/tlp/func.d/05-tlp-func-pm:165-195` writes `SOUND_POWER_SAVE_ON_AC`, default 1 (`/usr/share/tlp/defaults.conf:48`), and `/etc/tlp.d/99-legacy-hook-tlp.conf` leaves it unset. Which rule wrote last was not traced (no udev debug run) |
| With 1, the CS4208 codec is powered down almost all of the idle time: 2037 s suspended against 4 s active after 34 min uptime | VERIFIED 2026-10-14 | `/sys/bus/hdaudio/devices/hdaudioC0D0/power/runtime_{suspended,active}_time` |
| Every runtime resume replays the full A1534 bring-up, because `cs_suspend()` clears `bringup_valid` on every D3 transition | VERIFIED (source) | `src/cs420x-a1534/a1534_pcm.h` comment above `a1534_resume()`, `cs_suspend()` in `local-changes.patch` |
| That replay causes an audible pop or a cut-off start | NOT VERIFIED | the replay latency is unmeasured (same comment); the maintainer has never noticed a crackle, pop or cut-off start on battery (maintainer, 2026-10-14) |
| `power_save=0` costs measurably more battery than 1 | NOT VERIFIED | the maintainer declined the measurement on 2026-10-14; the kernel's power-saving design powers the codec down when unused, so the direction is expected, the size is unknown |
| The repository holds evidence of crackling at any power_save value | REFUTED | `rg -n -i 'power_save\|crackl\|knack' docs src tools` finds only the collector's read-out |

### 1.3 Why no package policy

1. The reason cachyos-settings sets 0 on AC is crackling "on some hardware". This codec has shown none at
   the battery value 1 (maintainer report). Whether the maintainer has also listened on AC at the value 1 that TLP
   sets there is NOT VERIFIED. TLP's own configuration comment for this machine says to set
   `SOUND_POWER_SAVE_ON_AC=0` only if the first tone after a pause crackles; that is the host's switch,
   and the one to use if it ever does.
2. `power_save` belongs to the HDA controller driver and also governs the HDMI codec (`hdaudioC0D2`).
   A CS4208 package overriding it would set policy for hardware it does not own.
3. A replacement `/etc/udev/rules.d/20-audio-pm.rules` from this package would mask the upstream rule, and
   with it the upstream fix, for as long as the package is installed.

Revisit only if a pop or a cut-off start is heard on battery that does not occur on AC. Then measure first:
the bring-up replay is the first suspect, not the power_save value.

### 1.4 The two udev messages: a cachyos-settings defect

The rule file is `/usr/lib/udev/rules.d/20-audio-pm.rules` from cachyos-settings 1:1.4.1-1 (VERIFIED,
`pacman -Qo`).

**card0, once per battery boot.** The add rule runs
`touch <state>; [[ <BAT0 status> != "Discharging" ]] && <save> && echo 0 > power_save`. On battery the
test is false, the `&&` chain ends with status 1, and udev logs "failed with exit code 1". Nothing breaks:
power_save stays at the kernel default, which is 10, until TLP writes 1 two seconds later (08:57:22 on 2026-10-14). VERIFIED: one such line in each of the last three boots (2026-10-13 20:22:48,
2026-10-14 08:44:42, 08:57:20), each booted on battery.

**ADP1, after a udev change replay.** The same add rule `touch`es the state file before the test, so a
battery boot leaves `/run/udev/snd-hda-intel-powersave` empty (VERIFIED: size 0 on the battery boot,
created 08:57:20 by the card0 rule; it holds `1` since the AC plug-in at 09:43:28, when the AC rule saved the
old value there). The battery rule then runs `echo $(cat <state> || echo 10) > power_save`. `cat` of an
empty file succeeds, the fallback 10 never applies, an empty string is written, and the write fails with
status 1. The kernel rejects the empty string: VERIFIED 2026-10-14 about 09:54 by writing an empty line to the
parameter as root, `tee` reported `Invalid argument` and the value stayed 1. The three ADP1 lines (2026-10-13 22:11:59 and 22:22:37,
2026-10-14 08:53:41) each fall in the same second as systemd-logind re-announcing every input device, that
is a udev change replay, after snapshot or package transactions (VERIFIED, journal timestamps; which
command started the replay is NOT VERIFIED). TLP's `tlp auto` runs on the same power_supply events
(1.2), so on the test machine the failed empty write is followed by TLP writing 1 (NOT VERIFIED, order not traced).
The handoff's guesses: "the file is empty" VERIFIED;
"the file is missing" REFUTED for these boots; "the write fails while the codec is suspended" NOT
VERIFIED and not needed to explain the lines.

**Upstream.** CachyOS-Settings commit `c8e575bbd4`, "udev/audio-pm: Misc fixes (#245)", 2026-09-24,
replaces the inline rules with a helper `/usr/lib/udev/audio-pm-ctl` whose `init` step returns 0 on
battery and whose `battery` step writes 10 when the state file is empty or missing (read on 2026-10-14
from https://github.com/CachyOS/CachyOS-Settings, branch master, by the audit's planning session; the
implementing session did not fetch it again). The installed 1:1.4.1-1 does not contain
it yet (VERIFIED: installed rule text; `pacman -Si` listed 1:1.4.1-1 as newest on 2026-10-14). No local
action: the messages go away with the first cachyos-settings release that carries the commit. Side effect
to expect then: on a battery boot that never saw AC, the battery value can become 10 instead of 1. Both
values enable power saving. On the test machine TLP rewrites the value afterwards anyway (1.2).

Check after a cachyos-settings update (the second line must print `helper-present`, the third `0`):

```
pacman -Q cachyos-settings
test -x /usr/lib/udev/audio-pm-ctl; and echo helper-present
journalctl -b -p4 | grep -c -E 'snd-hda-intel-powersave|snd_hda_intel/parameters'
```

## 2. RTKit

### 2.1 Decision

Keep **rtkit installed** (it was installed on 2026-10-14). No module-rt configuration, and nothing in this
package: realtime scheduling of PipeWire is not specific to the CS4208.

### 2.2 Evidence

| Claim | Status | How |
| --- | --- | --- |
| The handoff: "pipewire and wireplumber report RTKit errors" | VERIFIED for the login greeter, REFUTED for the user session | every `mod.rt: RTKit …` line at `-p4` in the boots of 2026-10-13 and 2026-10-14 has `_UID=957` (`plasmalogin`); the user's pipewire, wireplumber and pipewire-pulse logged none (`journalctl -b <n> -p4 -o verbose`, grouped by `_UID`) |
| The handoff: realtime comes from `99-realtime-privileges.conf` | REFUTED | the user is in `audio`, not `realtime` (`id -nG`); the limit is `@audio - rtprio 99` from `/etc/security/limits.d/20-audio.conf` (cachyos-settings); `/proc/<pid>/limits` and `LimitRTPRIO` read 99 |
| Before rtkit: data-loop threads SCHED_FIFO 88 (pipewire), 83 (wireplumber, pipewire-pulse) | VERIFIED 2026-10-14 09:30 | `ps -L -o tid,cls,rtprio,comm` on processes started 08:57, before rtkit was installed at 09:15 |
| After rtkit, with restarted user services: 88 (pipewire), 83 (wireplumber), 83 (pipewire-pulse); no RTKit or mod.rt line at `-p4` since the restart (the only `-p4` lines in that window are plasmashell and kded6 `No object for name …` notices from the restart itself); rtkit-daemon inactive | VERIFIED 2026-10-14 | `systemctl --user restart pipewire pipewire-pulse wireplumber` at 2026-10-14 09:56:11, same `ps` command, `journalctl -b --since 2026-10-14 09:56:11 -p4` |
| module-rt in PipeWire 1.6.9 accepts `rtkit.enabled` and `rtportal.enabled` | VERIFIED | `strings /usr/lib/pipewire-0.3/libpipewire-module-rt.so`; also `nice.level`, `rt.prio`, `rt.time.soft`, `rt.time.hard`, `rlimits.enabled`, `uclamp.min`, `uclamp.max` |
| The greeter's and the portal's RTKit messages are gone with rtkit installed | VERIFIED 2026-10-15 | the boot that started 2026-10-14 12:29:53, after rtkit was installed, has no RTKit or RealtimeKit line at `-p4` (command in 2.4); the three boots whose greeter started before rtkit had 21, 21 and 36 |

### 2.3 Why (b)

- **(a) leave it**: keeps 18 greeter lines and 3 portal lines in the `-p4` journal of every boot (VERIFIED for the boot of 2026-10-14: 12 + 6 greeter lines, 3 `xdg-desktop-portal` lines).
- **(c) module-rt with `rtkit.enabled = false`**: the user session never asks RTKit anyway, so the lines it
  would silence are the greeter's, which means a system-wide `/etc/pipewire` and WirePlumber drop-in. The
  greeter has no `RLIMIT_RTPRIO`, so there it would remove realtime scheduling, not a message. It would
  also leave the portal's message, which no PipeWire setting reaches.
- **(b) rtkit**: the greeter gets realtime through RTKit, the portal finds `org.freedesktop.RealtimeKit1`,
  and the user session stays on its rlimit path at the priorities measured above.

### 2.4 Still open

- Done 2026-10-15: on the boot that started 2026-10-14 12:29:53, after rtkit was installed, this prints `0`
  (VERIFIED; it printed 21, 21 and 36 on the three boots whose greeter started
  before rtkit):
  `journalctl -b -p4 | grep -c -i -E 'rtkit|realtimekit'`
- Not RTKit and not handled here: the greeter's WirePlumber logs `Failed to get percentage from UPower:
  NameHasNoOwner` (2026-10-14 08:57:25), two seconds before `upower.service` became active (08:57:27).
  A start-order effect in the greeter session (VERIFIED timestamps; the cause is NOT VERIFIED),
  handed back to macbook91-hw-fixes.
