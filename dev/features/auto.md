# Auto

Updated 2026-10-26 16:34, at 1.0.3.

Sundial reads the room's light with the MacBook's ambient light sensor and
sets the monitor's brightness and contrast to match. It's the main mode;
Schedule (the presets) is the other.

## Sub-features

- **Follows the room.** The room's light, averaged over about a minute, picks
  a point between two ends, Dark room and Bright room, each a brightness and a
  contrast. The scale is logarithmic from 5 lux (fully dark) to 500 (fully
  bright). The monitor eases to a new point at half a step per second.
- **The two ends.** Each is a card like a preset's. Dragging its sliders shows
  that end on the monitor until the card collapses or the popup closes;
  Preview does the same. A config from before Auto takes its ends from the
  dimmest and brightest presets.
- **Hold.** The Brightness slider moves the monitor at once and holds there:
  for 20 minutes, until the room's light doubles or halves, or until Back to
  Auto. Then it eases back to the room. The header reads Held meanwhile.
- **Night Shift** follows the schedule's presets, as in Schedule mode.
- **No reading.** With the lid closed or no sensor, the popup says so and the
  schedule drives the monitor until a reading returns.
- **Room log.** One line a minute, and one per hold starting or ending, in
  `room-log.csv` next to `config.json`: lux, averaged lux, what was sent, and
  any held brightness.
- **Auto | Schedule** at the bottom of the popup switches modes.

## How to get to it

Click the sun in the menu bar. Auto is what opens; the switch at the bottom
goes to Schedule.

## Driving it

Preconditions: none; needs the Swift toolchain, no sensor or monitor.

`./build.sh drive room-light` (~5s): compiles the app's room-light decisions
with a harness and feeds them readings logged on 2026-10-26. It checks the
lux scale and its ends, that the average takes minutes to follow the blinds
shutting (237 → 35 lux) and barely moves for a hand passing the notch (a 1s
spike to 3300), that a step toward a target is capped, and when a hold lapses.

Last driven: 2026-10-26, macOS. Passed; failed as expected with the averaging
removed.

Seen on the real thing 2026-10-26: installed, it read 41–44 lux and eased the
M27Q from 25/55 to 19/34 in about 40s.

By hand only: how the easing feels, the popup's look, Hold and Back to Auto,
previewing an end, the lid-closed fallback, and wake.

## Gotchas

- The sensor sits beside the camera. A camera cover over it reads a flat 0
  lux, which Auto takes for a dark room; turned round to cover only the lens,
  the same cover read normally (2026-10-26).
- Reading the sensor is private IOKit API. The event-system client has to be
  kept alive with the service: freed, the next read crashed on a freed lock
  inside IOKit (three crashes on 2026-10-26 before the fix).
- On 2026-10-12 the sensor gave no reading at all while the laptop's own
  screen was at 0 nits. If that holds, a fully dark laptop screen puts Auto on
  the schedule.
- Night readings aren't known yet. A lamp-lit room at night may read as bright
  as a dim afternoon, and Auto would then set the monitor brighter than the
  Night presets did.
- The monitor's own light reaches the sensor. A brighter monitor reads as a
  brighter room; small at the levels seen so far.
- Auto writes only when a value changes, so a change made with the monitor's
  buttons stays until the room moves or the Mac wakes.

## Calls

- 2026-10-26 16:34, 1.0.3. Auto follows the light measured in the room, not
  the clock or a weather forecast. A forecast knew the sky over a 3 km square
  but not whether the blinds were shut; "it should just work with the light in
  the room". Applies *Just right for the room*.
- 2026-10-26 16:34, 1.0.3. Brightness and contrast stay two values at each
  end rather than one combined level: "if it's hard to collapse all vars into
  one then we don't". Night Shift stays on the schedule's clock. Applies none.
