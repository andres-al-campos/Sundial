# Sundial

A person comes to Sundial so the light in the room, the screen and the smart
lights, follows the day without their touching anything: it matches the natural
light while the sun is up, then carries on as an artificial sunset that ends when
their night does. Opening it means something isn't right yet. Some of that will
always happen; the aim is that it happens less.

What a user can do, and the checks for each, are in `dev/features/`. Build, check
and install with `./build.sh` (see the README).

## Principles

How Sundial ought to be, so a session can decide a case nobody has met yet.
Rulings on one thing go in that feature's file, under Calls, and name the
principle they apply. The Principles in the `AGENTS.md` files above
this one (walled_garden's and `~/Projects/Code`'s) hold here too, unless this
file refines one or names an exception.

- 2026-11-05 13:35, 1.1.0. **Just right for the room.** The screen and the lamps are bright enough to
  see by in daylight and dim enough not to glare at night, and they get there
  gradually, so nobody notices them change.
- 2026-11-05 14:07, 1.1.0. **The room shows what you're changing.** When seeing the change is the point
  of a control, which is what it's named for, the monitor and bulbs move as you
  drag, with no Preview button. When it isn't, the room stays put, so fiddling
  can't light it up by accident. A control that can't move the monitor shows
  its reason instead. (From the contrast lock, and a keyframe's drag that blasted
  the room at night.)
- 2026-11-04 12:11, 1.1.0. **Empty space is spread out.** What's inside a card reads like writing, left to right
  and top to bottom, so empty space looks chosen rather than left over: "the empty space
  should feel intentional. spread out", not "all crammed in at the top" with an empty row
  below. Things keep their own size to do it. (From the keyframe card.)
