# Auto

Updated 2026-11-08 19:25, at 1.1.0.

Sundial reads the room's light with the MacBook's ambient light sensor and
sets the monitor from it before sunset and from the clock after. It's the main mode and needs no
presets; Schedule (the presets) is the other.

## Sub-features

- **Before sunset, brightness is your level times the room.** You set it with
  the Brightness slider and it stays: Sundial saves it as your level (the
  brightness at 100 lux), and the room scales it by the square root of its
  light: four times the light gives twice the brightness. Readings under 0.1
  lux count as 0.1. The default level, 30, and the square root fit the 13
  settled drags made before sunset from 2026-10-27 to 11-01 (level 30.4, power
  0.51, 25 to 470 lux). A level of 0 is the monitor's darkest in any room.
- **Contrast follows brightness** at a multiple you set by dragging the
  Contrast slider: it starts at π × brightness, and a drag keeps the
  multiple that gives what you chose, so brightness 0 is still contrast 0, the
  monitor's darkest. Four days of drags (2026-10-26 to 30) fitted 3.0 × and
  settled at 3.5-4 × from the 28th; a curve bent no better (power 0.99).
  Below brightness 1 a drag leaves the multiple alone: every multiple gives
  0 there.
- **Night Shift follows the sun**: it starts warming 30 minutes before
  sunset, rises evenly to full at your bedtime (the time in the Night Shift
  row, "Bedtime", midnight by default; past midnight counts as the same
  night), and turns off 46 minutes before
  sunrise. Fitted to the presets' evening values (R² 0.98) on 2026-10-26,
  when that was 5:13 PM to 6:30 AM. Sunrise and sunset are computed for the
  spot picked in Settings, by searching for a city (Apple's place search, which
  sees what's typed) or clicking the map, rounded to whole degrees either way, with
  no location permission. Until one is picked it's the point macOS's time zone table gives
  your time zone (Chicago for America/Chicago); each degree of longitude from
  the real place moves them about 4 minutes. A zone with no point (UTC) and no
  pick keeps the fixed 5:23 PM and 6:30 AM. When the Mac changes time zone
  (traveling, with "Set time zone automatically" on), the clock and the sun
  move to the new zone at once, leaving the pick behind until you're back.
- **After sunset, the clock dims to bedtime.** From where Night Shift starts
  warming (30 minutes before sunset, where the lamps start on Twilight), lux
  stops counting: brightness and contrast slide evenly from what the room gave
  at that moment to the night pair (brightness 1, contrast 3 to start) by
  bedtime, and stay there until Night Shift turns off. If Sundial didn't see
  the handover, it starts from your level at 38 lux, the median there over the
  first week. Contrast at night is its own number, not a multiple, so brightness
  0 can still have some. A drag before bedtime holds what you chose and the
  slide runs on from it for the rest of the evening, across a wake too; it saves
  nothing. A drag after bedtime sets the night pair. A drag before sunset at
  0 lux holds until the room is lit or the Mac wakes.
- **Easing.** The sensor is read once a second; a median of the last five
  readings drops a hand passing the notch, and a 6-second average smooths the
  rest, so a big change (blinds, a cloud) lands in about 20 seconds. Waking
  the Mac or logging in skips both: the first reading after is the room, and
  the monitor goes straight to it. The
  monitor moves at most 5 a second for brightness and contrast, 1 for Night
  Shift. Big changes are meant to be seen; most are small.
- **No reading.** With the lid closed or no sensor, Auto keeps the last room
  it saw (100 lux before the first) and the Room row says "no reading".
- **Room log.** One line a minute, and one each time you let go of a slider
  (with the level, contrast multiple, night brightness or night contrast saved), in
  `room-log.csv` next to `config.json`. The `dark` column is how far along the
  evening's slide it was (0 to 1), and from 2026-11-01 runs all evening, not
  only at 0 lux; `dark_hold` marks a drag that held. Rows from 2026-10-30 on carry the
  night minimum and `dark` columns, from 2026-10-31 night contrast, and from 2026-11-04 `lamps`, each bulb's brightness and xy or "off" at the last
  read, up to 30 seconds old, as `Light 1=45/0.512/0.414;Light 2=off`. A log started before then has the older header.
- **Display Follows**, a popup at the top of the Display tab, picks which one drives the monitor: Room Light or Schedule. The schedule's card opens that preset in the window on a click.

## How to get to it

Click the sun in the menu bar. Auto is what opens; Display Follows → Schedule
shows the schedule's preset in force.

## Driving it

Preconditions: none; needs the Swift toolchain, no sensor or monitor.

`./build.sh drive room-light` (~5s): compiles the app's room-light rules with
a harness. It checks that brightness before sunset is the level times the
room's square root (the day's drags at 35 to 470 lux, never past 100, level 0
darkest), that the evening slides to the night pair by bedtime and not
outside Night Shift's hours, that only a lit daytime drag saves the level, that a set
brightness comes back in the same room and scales in another, that a set
contrast comes back at the same brightness and scales with it, that a click on
the location map gives the whole degree under it and moves the sun, that a
searched city is kept to whole degrees, that sunrise
and sunset for Chicago land on its solstice times (and zone.tab's point
parses), that Night Shift lands near the presets it was fitted to, that the blinds
shutting as logged (237 → 35 lux) lands in about 20 seconds, and that a 1s
spike or dip (a hand at the notch) leaves the average where it was.

Last driven: 2026-10-27, macOS. Passed; on 2026-10-26 it failed as expected with the Night
Shift ramp an hour late, and with the median removed.

Seen on the real thing 2026-10-26: installed, it read 27 lux, stayed up, and
followed the slider live; the level saved and survived a restart.

By hand only: how the easing feels, the popup's look, wake, and the lid-closed
row.

`./build.sh drive time-field` (~6s): the arrows on the time field, which Bedtime uses.

`./build.sh drive slow-monitor` (~10s): the monitor's commands against a stand-in monitor that
takes 2 seconds a write. The main thread keeps answering, and the values land in the order a drag
sent them. Fails as expected with the write on the main thread.

`./build.sh check` runs `tests/ddc-packets.sh`, the DDC/CI bytes against hand-worked packets and a
real reply from the M27Q.

## Gotchas

- Sundial sets the monitor itself over IOAVService, Apple silicon's private DDC path, since
  2026-11-05; before, it went through BetterDisplay's command line, which took about 16 seconds a
  command with BetterDisplay's app closed. On the Mac's own HDMI port the I2C chip address is
  0xB7, not 0x37: at 0x37 the M27Q took every write without acting on it and answered reads
  empty (`6e 80 be`), while the call itself reported success. A write that "worked" is only
  shown by reading the value back. See `IOAVLink` in `src/control/DDC.swift`.

- The sensor sits beside the camera. A camera cover over it reads a flat 0
  lux, which counts as a pitch-dark room; turned round to cover only the lens,
  the same cover read normally (2026-10-26).
- Reading the sensor is private IOKit API. The event-system client has to be
  kept alive with the service: freed, the next read crashed on a freed lock
  inside IOKit (three crashes on 2026-10-26 before the fix).
- On 2026-10-12 the sensor gave no reading at all while the laptop's own
  screen was at 0 nits. If that holds, a fully dark laptop screen freezes Auto
  on the last room it saw.
- The sensor's lux counts whole numbers, so a dark room reads 0 from a dim
  lamp down to black. Below 10 lux Sundial reads a raw detector count
  instead (about 10 per lux), which told apart an LED's settings at 0.15,
  2.2, 7 and 11 lux where lux read 0, 0, 2 and 7 (2026-10-26). Below about
  0.1 lux both read 0, so the two lowest settings look the same.
- The sensor reads the lamps. By evening that's why the clock takes over; by
  day the Morning and Noon scenes still add to the lux the curve scales from.
  Evening light Sundial doesn't control (a ceiling light) doesn't raise the
  screen either: a drag holds until the next evening.
- The monitor's own light reaches the sensor. A brighter monitor reads as a
  brighter room; small at the levels seen so far.
- Auto writes only when a value changes, so a change made with the monitor's
  buttons stays until the room moves or the Mac wakes.
- The first Auto (2026-10-26, a few hours) used two ends, Dark room and Bright
  room, and a hold that lapsed after 20 minutes; its log is
  `room-log-first-version.csv`.

- The sensor gives no reading while the laptop's screen is off, and the Mac
  stays awake overnight with it off: the log's raw lux is blank from then
  until the display wakes, and the average holds its last value.

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
- 2026-10-26 22:40, 1.0.3. The scaling can reach the monitor's darkest, brightness 0 and contrast 0,
  as Schedule's darkest presets did: "I do want to be able to have a scaling
  that can still give me maximum darkness." So contrast is √2 × brightness
  with no offset, though the presets' line had one ("the preset is 1
  datapoint"), so a level of 0 is brightness 0 and contrast 0. Applies *Just right for the
  room*.
- 2026-11-07 23:20, 1.1.0. Display Follows is a two-choice popup at the right of the Display tab's
  first row, Room Light or Schedule, so the row reads as a sentence; a bare "Screen" under
  the Display tab said display twice. It began as a switch that changed the whole popup ("what
  toggle does that?"), then a segmented Auto | Schedule; once the header became Display |
  Lights, that second segmented row read as a second level of tabs ("having to tab toggle
  feels kind of off"). A switch again named only one side ("Auto is not very descriptive"),
  and the popup names both. It stays in the popup: in the window's Presets, picking it
  changed nothing you could see. Clicking the schedule's card,
  which shades on hover, opens that preset in the window. Applies *Never a fight with the controls*.
- 2026-11-01 20:34, 1.1.0. Before sunset brightness follows the room, after sunset the clock, because
  once Sundial drives the lamps the sensor is reading its own light: "post sunset
  light lerps, so essentially the monitor would also just follow the post sunset
  algo. It's not pre 0 lux and post 0 lux, it's just pre sunset and post sunset."
  The drags alone fitted one curve equally well on both sides; the split comes
  from the loop, not the fit. It replaces the slide that began at 0 lux and limits
  the 2026-10-26 "not the clock" call above to before sunset. The curve went from
  a fourth root to a square root fitted to daytime drags, and the level moved to
  a new config key since the old number meant something else. Applies *Just
  right for the room*.
- 2026-10-26 22:39, 1.0.3. Brightness follows the fourth root of the room's light, fitted to seven
  brightnesses set across one evening. The square root, shifted to reach 0
  at 2 lux, was a guess before any night readings; the room read 2 lux at
  night, where it gave 0 and the brightness set was 17-22, and every drag
  there saved a level that would have meant 100 by day. Full darkness is a
  level of 0 instead. Applies *Just right for the room*.
- 2026-10-26 23:43, 1.0.3. Contrast gets its own slider, so its log shows what fits instead of
  following a fixed √2. The aim is the curves that need the fewest
  interventions: "I'm trying to find the minimal interventions curves that
  fit my eyes." A few days of drags come first, then a curve fitted to them,
  maybe two anchors. Applies *Just right for the room*.
- 2026-10-27 01:02, 1.0.3. Night Shift's start and end follow sunset and sunrise, located by the time
  zone rather than Location Services: "timezone is good enough". Full warmth
  stays at midnight ("just midnight is fine"), which the sun doesn't move. Applies *Just right for the room*.
- 2026-11-04 21:46, 1.1.0. The room log says what the lamps were doing too, since they're part of the light the sensor reads: "it should also track what the current light colors are, not just
  the monitors, since it affects the lux obviously." Paused included, when the Hue app may have them doing anything. Applies *Just right for the room*.
- 2026-11-02 16:21, 1.1.0. A sunset set by the time zone alone isn't good enough after all: in a big zone
  it can be an hour from the real one. So Settings shows a map to confirm
  the spot, but stays coarse, rounded to whole degrees and with no Location Services:
  "id rather not have to ask for ppls exacto location". The map is drawn from
  outlines in the app, since Apple Maps would tell a server the area looked at. This
  revises the Call above. Applies *Just right for the room*.
- 2026-11-02 23:34, 1.1.0. Picking on the map still asks you to know where you are on a small map, so a search for
  your city sits above it: "Most ppl don't know their lat lon". It uses Apple's place
  search, which sees what's typed ("apple is ok"), and offers cities rather than street
  addresses. What's kept is the name and the same whole degrees a click gives. Applies
  *Just right for the room*.
- 2026-10-28 00:22, 1.1.0. Bedtime, where Night Shift is full, is yours to set in Auto, and
  the lamps' dimmest scene lands on it too: "it should be the same as night
  shift ... and the auto mode night shift should be customizable too". It
  replaces the fixed midnight above, which stays the default. Applies *Just
  right for the room*.
- 2026-11-07 20:38, 1.1.0. Bedtime lives in the Night Shift row as "Bedtime [time]", not its own
  row: one time is where Night Shift is full, the lamps reach DuskLight and a
  dark room has the screen at its dimmest, and a Bedtime row repeated Night
  Shift's "full at" ("the bedtime line is kind of redundant ... still make it
  obvious the value means at this time you get min brightness"). The row
  drops "warms at" and "off at", which follow the sun and can't be set. Named
  "Bedtime", as the Lights band names the mark, after "darkest at" for a while:
  "i honestly can't think of anything else that means this is the point the
  light should be the darkest at".
  Applies *Just right for the room*.
- 2026-10-30 17:34, 1.1.0. When the room reads 0 before bedtime, brightness keeps falling by the clock
  to the night minimum at bedtime ("if lux is 0 before midnight it should
  interpolate"). The log showed it: the room read 0 from 22:30-23:00 every
  night, and 30-60 minutes later the last drag took the screen to 1 (six
  nights of seven). Applies *Just right for the room*.
- 2026-10-30 17:34, 1.1.0. Contrast starts at π × brightness ("how about a multiple of pi?"), between
  the 3 × the drags fitted and the 3.5-4 × of the last days. Applies *Just
  right for the room*.
- 2026-10-31 14:10, 1.1.0. Waking the Mac or logging in goes straight to the room's brightness instead
  of easing for 20 seconds from the night's: "immediately go to the new day's
  brightness every time I wake up and log in." The screen was off, so the
  jump is nothing anyone sees change. Applies *Just right for the room*.
- 2026-10-31 14:10, 1.1.0. The dark's minimum is a brightness and a contrast of their own, both set by
  dragging after bedtime in the dark. Contrast as a multiple made brightness
  0 contrast 0, and a nudge of Contrast there saved the multiple as 1: "when
  brightness and contrast both go to 0 it messes up the multiplication and
  now everything is one to one" (2026-10-31). The nights' drags wanted
  contrast 3 at brightness 0. Applies *Never a fight with the controls*.
- 2026-11-01 18:25, 1.1.0. A drag in the dark holds for the night and doesn't touch the day's level.
  Brightness 1 at 0 lux worked back to a level of 5.6, so every morning from
  2026-10-27 to 11-01 opened at about a fifth of the room's brightness, and the
  first drag of the day repaired it: "I don't think the on wake worked", when
  the jump had worked and landed on that level. Applies *Just right for the room*.
