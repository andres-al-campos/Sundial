# Sundial

A person comes to Sundial so the artificial light in the room, the screen and
the smart lights, matches the natural light, at any time of day, without
touching anything. They open it only to
change a preset or its time.

What a user can do, and the checks for each, are in `dev/features/`. Build, check
and install with `./build.sh` (see the README).

## Principles

How Sundial ought to be, so a session can decide a case nobody has met yet.
Rulings on one thing go in that feature's file, under Calls, and name the
principle they apply. The Principles in the `AGENTS.md` files above
this one (walled_garden's and `~/Projects/Code`'s) hold here too, unless this
file refines one or names an exception.

- 2026-10-22 22:34, 1.0.3. **Just right for the room.** The screen is bright enough to see by in
  daylight and dim enough not to glare at night, and it gets there gradually,
  so nobody notices it change.
- 2026-10-22 22:34, 1.0.3. **What you touch is what the monitor does.** A slider moves the real monitor
  as you drag, and editing a preset previews it on the monitor. A control that
  can't move the monitor isn't offered as if it could: its reason takes its
  place. (From the contrast lock.)
- 2026-11-04 11:57, 1.1.0. **Empty space is spread out.** What's on a screen shares the room it has, so empty space
  reads as chosen rather than left over: "the empty space should feel intentional. spread
  out", not "all crammed in at the top" with the rest empty below. (From the Lights window.)
