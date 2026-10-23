# Sundial

A person comes to Sundial so their screen is never too bright or too dark for
the room, at any time of day, without touching a slider. They open it only to
change a preset or its time.

What a user can do, and the checks for each, are in `features/`. Build, check
and install with `./build.sh` (see the README).

## Principles

How Sundial ought to be, so a session can decide a case nobody has met yet.
Rulings on one thing go in that feature's file, under Calls, and name the
principle they apply. The walled_garden `AGENTS.md` principles hold here too
(motion spends attention; a menu bar popup opens at its final size; never a
fight with the controls).

- 2026-10-22 22:34, 1.0.3. **Just right for the room.** The screen is bright enough to see by in
  daylight and dim enough not to glare at night, and it gets there gradually,
  so nobody notices it change.
- 2026-10-22 22:34, 1.0.3. **What you touch is what the monitor does.** A slider moves the real monitor
  as you drag, and editing a preset previews it on the monitor. A control that
  can't move the monitor isn't offered as if it could: its reason takes its
  place. (From the contrast lock.)
