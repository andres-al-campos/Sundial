# Lamps

Updated 2026-11-04 14:17, at 1.1.0.

Sundial sets the Hue lamps through the day from your scenes, so the room's
artificial light follows the natural light along with the screen.

## Sub-features

- **Lights window.** One row per bulb across the day, read from the bridge, the
  band showing the bulb's colour dimmed by its brightness. Above the bands are
  today's Sunrise, Sunset and Bedtime times, worked out each day; a label too close
  to another moves aside, and a tick stays on the real time.
- **Keyframes.** Each bulb has its own, with a straight line between neighbours
  and no hidden holds: a hold is two matching keyframes. Click a band to add one
  (the band doesn't change). Click a dot for its time, on/off, brightness, temperature
  (700 to 6500 K) and colour, or to delete it. A bulb the bridge has no scene for starts
  on three: sunrise, sunset and bedtime. Until they're changed its name says to click a dot.
- **Temperature** only means something for the glowing-metal whites. For any other colour
  the slider dims, says "Color", and stays where it was before the wheel left the whites.
  That's remembered until Sundial quits; a keyframe that's already a colour sits at its
  nearest temperature. Dragging the slider goes back to a white.
- **Moving.** A dragged keyframe shows the colour under it and takes that on
  drop. A typed time keeps its look. Within 10 minutes of a mark it snaps and
  follows that mark. Imported keyframes can follow one at an offset, such as 40
  minutes before sunset.
- **Previews.** Dragging a keyframe or changing its settings shows it on the bulb,
  with a badge in the top row saying what it lands on, such as 45% at 6:48 PM. On letting go the bulb fades back to where
  the day has it, over 1 second.
- **Holding.** Click a bulb's name and the same card changes that bulb right now, from what the
  lamp is doing, without touching a keyframe. The first change holds it: its name turns orange
  and the card says "Held until sunrise" with Back to schedule, which fades it back in 1 second.
  A hold ends by itself at the next sunrise, covers only the bulb clicked and not those linked to
  it, and is forgotten on relaunch. Rename is on the right-click menu.
- **Card.** Click a keyframe and its settings come down on a card from behind the
  rows, which stay put: a colour wheel, then the settings reading left to right and top
  to bottom: the bulb with its on/off switch, long Brightness and Temperature sliders, then the
  time with Delete in the far corner. Off dims the rest and shows "Off". The rows scroll only if the
  window can't fit them and the card. Its close button or clicking the dot again puts it
  away, as does clicking around the rows.
- **Colour wheel.** Its green and blue are the screen's and its red the bulbs', so every
  temperature has its own spot. Screens run out of red around 900 K, so below that the
  thumb moves and the bulb changes while the colours on screen stay the same red.
- **Right-click.** Copy and paste a keyframe, its look, or a bulb's whole day;
  rename a bulb, which renames it on the bridge; make one bulb follow another's
  day, and unlink it again.
- **Undo.** Cmd-Z and Shift-Cmd-Z cover every change to the bulbs.
- **Play the day** runs the day on the bulbs in 10 seconds and returns to now.
- **Pause** stops Sundial changing the bulbs until Resume, so the Hue app can use them.
  A preview while paused still shows on the bulb, then fades back to what the bulb was.
  While paused the status line is orange and Resume is filled orange.
- **Import.** The first run makes each bulb's day from the seven named scenes on
  the bridge, keeping what the lamps did at every minute. After that Sundial holds the
  settings, and scene edits in the Hue app aren't read.
- **Continuous fade.** Every 30 seconds each bulb is sent a 30-second fade to
  where it should be, so it never steps. After wake, every bulb is sent again.
  A lamp switched off in the Hue app or anywhere else gets nothing until it's
  switched back on, and it catches up within 30 seconds of that.
- **Pairing.** Settings → Lamps → Pair Hue Bridge finds the bridge with
  Bonjour and waits up to 30 seconds for its button to be pressed. The key is
  kept in the Keychain. Only the home network is needed, not the internet.

Not built: deleting a bulb from the bridge, or adding a new one. Undo doesn't cover presets.

## How to get to it

Click the sun in the menu bar, then Open Sundial, then Lights. Clicking its icon in the Dock, once pinned, opens the window too.

## Driving it

Preconditions: none; needs the Swift toolchain, no bridge.

`./build.sh drive lamps` (~3s): compiles the app's blending with a harness
and checks that a lamp on a keyframe is that scene, halfway between two is
halfway in brightness and xy, each lamp keeps its own brightness, the blend
wraps midnight, DuskLight holds until 30 minutes before Morning, a lamp
missing from a scene takes the other's value, 2000 K and 6400 K land on the
right whites, and the scenes sit on the sun and Night Shift's ramp, with
DuskLight at bedtime and the night scenes moving with it.

Last driven: 2026-10-28, macOS. Passed; it failed as expected with a wrong
halfway value.

It also checks that importing the scenes matches the old blend at every minute,
the keyframe rules: straight lines, fading to off, leaving out a dragged
keyframe, snapping, anchors, and reading whites back as a temperature, and that a
lamp someone switched off is left alone.

It also checks that a keyframe saved as disabled counts, a new bulb's three keyframes, what counts as new, and that whites have a
temperature and colours don't.

It also checks when a hold ends. What a held bulb is sent has no check yet.

By hand only: the window, how the card moves, pairing, that the bridge takes the fades, how the
blend looks in the room.

## Calls

- 2026-11-04 11:57, 1.1.0. **A keyframe's settings sit on a card under the rows, not an inspector.** The day runs left to
  right and an inspector takes that width from it, and the sliders stay long: "i just like the
  long sliders more". It's there only while a keyframe is selected, so nothing has to say "select
  one": the dots are "the most obvious thing to explore". It comes down from under the timeline
  and never covers it, "always below the timeline".

- 2026-11-04 12:11, 1.1.0. **Rows keep their height.** Rows stretched to fill the window looked "horrendous", and
  the space below them isn't the problem *Empty space is spread out* is about: that was the
  writing on the card.

- 2026-11-04 14:17, 1.1.0. **No Disable.** It only existed to hold a colour for a while, and two on/off controls side by side were
  the cost: a new person can't tell them apart. Holding does that job, so a keyframe is either in the day or
  deleted. Keyframes saved as disabled count again.

- 2026-11-04 14:17, 1.1.0. **Every control says what it is.** The switch sits beside the name it controls and always means the bulb.
  Time keeps its label even though the value explains itself, and off is a switch rather than the bottom of
  the slider, which only looks obvious to whoever built it. Applies *Never a fight with the controls*.

- 2026-11-04 14:17, 1.1.0. **Delete is far from Close.** Side by side they're "very easy to mix up", so Delete takes the bottom right
  corner and Close the top right.

- 2026-11-02 05:18, 1.1.0. **A lamp switched off by hand stays off.** Sundial used to send on with every
  fade, so a lamp switched off from the phone came back on within a minute: "It
  should not re set the light color when I've turned off the lights". Only the
  person who switched it off switches it back on. Applies *Never a fight with the controls*.

- 2026-11-04 12:17, 1.1.0. **A colour's Temperature slider stays still.** The dimmed look is fine, but moving with the wheel
  "sends mixed signals": it says the number still means something. It keeps the value from before
  the colour.

## Gotchas

- The status line stays on its last "Paired" through a stall. Each tick logs one line, so whether the lamps are being sent is read with `/usr/bin/log show --last 1h --predicate 'subsystem == "com.aurende.sundial" AND category == "lamps"'`.
- A lit lamp's colour or brightness changed in the Hue app is set back within a minute while Follow is on. Pause keeps it.
- Previewing a keyframe or Play the day lights a bulb that was off, and it stays on afterwards.
- After a relaunch, a lamp that a keyframe had turned off counts as switched off by hand, since that memory isn't saved, and stays off until it's switched on.
- Above about 5 calls a second the bridge still answers 200 but takes seconds to (measured 2026-11-01: 0.3s at 5/s, 2.3s at 10/s, 3.8s at 20/s), so previews send only the newest state, about 2 per bulb per second, and a slower one would look like lag, not failure.
- Color temperature stops at 2000 K on these bulbs and a higher mirek silently gives 2000 K, so Sundial always sends xy, which holds 1700 K exactly. Below that the white curve is a table of Planck's law, ending at 700 K, where it reaches these bulbs' red corner (xy 0.692, 0.308).
- macOS asks for the Keychain again after every `./build.sh`, because the app is
  signed ad-hoc and each build is a new signature to it. Allow lasts one launch,
  Always Allow lasts until the next build. Until it's answered the lamps wait and
  the status says so; the rest of the app runs.
- macOS asks for local network access the first time Sundial looks for the bridge.
  Refused, no bridge is found. Allow it in System Settings → Privacy & Security
  → Local Network.
