# Auto

Updated 2026-10-26 22:39, at 1.0.3.

Sundial reads the room's light with the MacBook's ambient light sensor and
sets the monitor from it and the clock. It's the main mode and needs no
presets; Schedule (the presets) is the other.

## Sub-features

- **Brightness is your level times the room.** You set it once with the
  Brightness slider and it stays: Sundial saves it as your level (the
  brightness at 100 lux), and the room scales it by the fourth root of its
  light: sixteen times the light gives twice the brightness. Readings under 1
  lux count as 1. The default level, 45, fits the brightnesses set on the
  evening of 2026-10-26 (17-22 at 2 lux, 25-30 at dusk, 40 at 84 lux). A
  level of 0 is the monitor's darkest in any room.
- **Contrast follows brightness**: √2 × brightness, so brightness 0 is
  contrast 0 too, the monitor's darkest. The presets' own line had the same slope plus 7.8
  (R² 0.82, against 0.71 for √2 ×).
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
- **Auto | Schedule** under the header picks which one drives the monitor.

## How to get to it

Click the sun in the menu bar. Auto is what opens; Schedule is the other half of
the control under the header.

## Driving it

Preconditions: none; needs the Swift toolchain, no sensor or monitor.

`./build.sh drive room-light` (~5s): compiles the app's room-light rules with
a harness. It checks that brightness is the level times the room's fourth
root (the evening's settings at 2, 19-32 and 84 lux, never past 100, level 0
darkest), that a set
brightness comes back in the same room and scales in another, that contrast
is √2 × brightness, that Night Shift lands near the presets it was fitted to, that the blinds
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
- At night the sensor reads 0-3 lux, lit by the monitor alone (2026-10-26),
  so the bottom of the curve is noise; that's why readings under 1 count as
  1. A lamp-lit room may read as bright as a dim afternoon; Night Shift is on
  the clock, brightness isn't.
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
- 2026-10-26 17:28, 1.0.3. The scaling can reach the monitor's darkest, brightness 0 and contrast 0,
  as Schedule's darkest presets did: "I do want to be able to have a scaling
  that can still give me maximum darkness." So contrast is √2 × brightness
  with no offset, though the presets' line had one ("the preset is 1
  datapoint"), and brightness reaches 0 at 2 lux. Applies *Just right for the
  room*.
- 2026-10-26 18:36, 1.0.3. Auto | Schedule is a full-width segmented control under the header. A
  switch was wrong because it changed the whole popup ("what toggle does
  that?"), and tabs read as two pages you could both look at, not one choice
  of what drives the monitor. The first segmented control sized to its labels
  and left the right side empty, so its halves now fill the width. It belongs to the header, with no line
  between them; the selection slides between the halves ("nothing should
  teleport") and the other half glows faintly on hover. The header's right side is
  bare in both modes: the control says the mode, and Schedule opens on the
  preset in force.
- 2026-10-26 22:39, 1.0.3. Brightness follows the fourth root of the room's light, fitted to seven
  brightnesses set across one evening. The square root, shifted to reach 0
  at 2 lux, was a guess before any night readings; the room read 2 lux at
  night, where it gave 0 and the brightness set was 17-22, and every drag
  there saved a level that would have meant 100 by day. Full darkness is a
  level of 0 instead. Applies *Just right for the room*.
