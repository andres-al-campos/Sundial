# Auto

Updated 2026-10-26 17:25, at 1.0.3.

Sundial reads the room's light with the MacBook's ambient light sensor and
sets the monitor from it and the clock. It's the main mode and needs no
presets; Schedule (the presets) is the other.

## Sub-features

- **Brightness is your level times the room.** You set it once with the
  Brightness slider and it stays: Sundial saves it as your level (the
  brightness at 100 lux), and the room scales it by the square root of its
  light. Sixteen times the light gives four
  times the brightness. The default level, 18, gives the old Morning preset's
  42 in the lit room (~550 lux) and about 1 in a dark room at night.
- **Contrast follows brightness**, on the line fitted to the six presets
  (7.8 + 1.41 × brightness, R² 0.82). AfterNoon and Twilight sat 12 and 20
  off it.
- **Night Shift follows the clock**, fitted to the presets' evening values
  (R² 0.98): off until 5:13 PM, rising ~14% an hour to full at 12:11 AM, full
  until 6:30 AM, then off.
- **Easing.** The sensor is read once a second; a median of the last five
  readings drops a hand passing the notch, and a 6-second average smooths the
  rest, so a big change (blinds, a cloud) lands in about 20 seconds. The
  monitor moves at most 5 a second for brightness and contrast, 1 for Night
  Shift. Big changes are meant to be seen; most are small.
- **No reading.** With the lid closed or no sensor, Auto keeps the last room
  it saw (100 lux before the first) and the Room row says "no reading".
- **Room log.** One line a minute, and one each time you let go of the slider
  (with the level saved), in `room-log.csv` next to `config.json`.
- **Auto | Schedule** at the bottom of the popup switches modes.

## How to get to it

Click the sun in the menu bar. Auto is what opens; the switch at the bottom
goes to Schedule.

## Driving it

Preconditions: none; needs the Swift toolchain, no sensor or monitor.

`./build.sh drive room-light` (~5s): compiles the app's room-light rules with
a harness. It checks that brightness is the level times the room's square
root (Morning's 42 at 550 lux, ~1 in the dark, never past 100), that a set
brightness comes back in the same room and scales in another, that contrast
and Night Shift land near the presets they were fitted to, that the blinds
shutting as logged (237 → 35 lux) lands in about 20 seconds, and that a 1s
spike or dip (a hand at the notch) leaves the average where it was.

Last driven: 2026-10-26, macOS. Passed; failed as expected with the Night
Shift ramp an hour late, and with the median removed.

Seen on the real thing 2026-10-26: installed, it read 27 lux, stayed up, and
followed the slider live; the level saved and survived a restart.

By hand only: how the easing feels, the popup's look, wake, and the lid-closed
row.

## Gotchas

- The sensor sits beside the camera. A camera cover over it reads a flat 0
  lux, which counts as a pitch-dark room; turned round to cover only the lens,
  the same cover read normally (2026-10-26).
- Reading the sensor is private IOKit API. The event-system client has to be
  kept alive with the service: freed, the next read crashed on a freed lock
  inside IOKit (three crashes on 2026-10-26 before the fix).
- On 2026-10-12 the sensor gave no reading at all while the laptop's own
  screen was at 0 nits. If that holds, a fully dark laptop screen freezes Auto
  on the last room it saw.
- Night readings aren't known yet. A lamp-lit room at night may read as bright
  as a dim afternoon; Night Shift is on the clock, brightness isn't.
- The monitor's own light reaches the sensor. A brighter monitor reads as a
  brighter room; small at the levels seen so far.
- Auto writes only when a value changes, so a change made with the monitor's
  buttons stays until the room moves or the Mac wakes.
- The first Auto (2026-10-26, a few hours) used two ends, Dark room and Bright
  room, and a hold that lapsed after 20 minutes; its log is
  `room-log-first-version.csv`.

## Calls

- 2026-10-26 16:34, 1.0.3. Auto follows the light measured in the room, not
  the clock or a weather forecast. A forecast knew the sky over a 3 km square
  but not whether the blinds were shut; "it should just work with the light in
  the room". Applies *Just right for the room*.
- 2026-10-26 17:08, 1.0.3. The brightness you set is permanent, in Auto too, and the room's light
  multiplies it: "how do you know what right looks like? I imagine it's
  different for different eyes. Hence the lux should be a sort of multiplier."
  It replaced a hold that lapsed and two ends to set. Applies *Just right for
  the room*.
- 2026-10-26 17:25, 1.0.3. Easing is quick, about 20 seconds for a big change: "big changes are
  supposed to be salient, and most will not be." It replaced a minute or more.
  Applies *Just right for the room*.
