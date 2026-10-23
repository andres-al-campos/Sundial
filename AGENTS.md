# Sundial

A person comes to Sundial to stop thinking about their monitor: it sets the
screen to suit the room at each time of day, and they open it only to adjust
a preset or its time.

What a user can do, and the checks for each, are in `features/`. Build, check
and install with `./build.sh` (see the README).

## Principles

Rules that decide cases nobody has met yet. Rulings on one thing go in that
feature's file, under Calls. The walled_garden `AGENTS.md` principles apply
here too (motion spends attention; a menu bar popup opens at its final size).

- 2026-10-12 19:29, 1.0.3. **A control that can't act shows why, in its own place.** A slider locked by
  HDR is replaced by its reason rather than greyed out beside it: a control
  that can't move has nothing to show, and the reason is the thing worth
  reading. (From the contrast lock.)
