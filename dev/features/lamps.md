# Lamps

Updated 2026-11-04 22:51, at 1.1.0.

Sundial sets the Hue lamps through the day from your scenes, so the room's
artificial light follows the natural light along with the screen.

## Sub-features

- **Lights window.** One row per bulb across the day, on a card, read from the bridge, the
  band showing the bulb's colour dimmed by its brightness, reaching 90% of the real colour at full brightness. A keyframe is its true colour in a ring whose white fills
  with its brightness, clockwise from the top; an off one is its colour at half strength, as the card's wheel is when off, with a slash in the ring's grey running past the rim, as in ∅. Above the bands are
  today's Sunrise, Sunset and Bedtime times, worked out each day; a label too close
  to another moves aside, and a tick stays on the real time. A line marks the time now, ending in a solid head under the last row.
- **Keyframes.** Each bulb has its own, with a straight line between neighbours
  and no hidden holds: a hold is two matching keyframes. Click a band to add one
  (the band doesn't change, since it takes the colour in between). Click a dot for its time, on/off, brightness, temperature
  (700 to 6500 K) and colour. Right-click a dot to delete it. A bulb the bridge has no scene for starts
  on three: sunrise, sunset and bedtime. Until they're changed its name says to click a dot.
- **Temperature** only means something for the glowing-metal whites. For any other colour
  the slider dims, says "Color", and stays where it was before the wheel left the whites.
  That's remembered until Sundial quits; a keyframe that's already a colour sits at its
  nearest temperature. Dragging the slider goes back to a white.
- **Moving.** Dragging a keyframe changes only its time, as typing one does: it keeps its colour, brightness and on or off, and the band reshapes around it as it moves. The bulbs stay as they are until the drop, then fade to the new day at the usual pace. Within 10 minutes of a mark it snaps and
  follows that mark. Imported keyframes can follow one at an offset, such as 40
  minutes before sunset.
- **Previews.** Changing a keyframe's settings shows it on the bulb. A badge in the top row says
  what it lands on, such as 45% at 6:48 PM, during a drag too. On letting go of a setting the bulb fades back to where
  the day has it, or to its hold, over half a second, and only the bulbs that moved are sent.
- **Holding.** Click a bulb's name and its whole row lights up, and the same card changes that bulb right now,
  from what the lamp is doing, without touching a keyframe. The first change holds it: its name turns orange
  and the card says "Held until sunrise" with Return to schedule in orange text, which fades it back in half a second.
  A hold ends by itself at the next sunrise and is forgotten on relaunch. Bulbs following the one clicked take the hold too, unless they're held themselves:
  a follower's own card can hold it apart, and its Return to schedule ends whichever hold it's under. Rename is on the right-click menu.
- **Card.** Click a keyframe and its settings come down on a card from behind the
  rows' card, which stays put: a colour wheel, then the settings reading left to right and top
  to bottom: the bulb with its on/off switch to the left of its name and "Keyframe" or "6 Keyframes" after it, the time,
  then long Brightness and Temperature sliders. A faint line divides the wheel from the rest. Off dims the wheel and
  sliders, keeping their fill, and both say "Off". Every button shades on hover. The rows scroll only if the
  window can't fit them and the card. Its close button or clicking the dot again puts it
  away, as does clicking around the rows. A right-click leaves it open. If its keyframe goes, from a delete, Paste Day or an undo, it moves to that bulb's own card.
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
the keyframe rules: straight lines, fading to off, snapping, anchors, and reading whites back as a temperature, and that a
lamp someone switched off is left alone.

It also checks that a keyframe saved as disabled counts, a new bulb's three keyframes, what counts as new, and that whites have a
temperature and colours don't.

It also checks when a hold ends and whose hold a follower is under.

`./build.sh drive held-lamp` (~15s): the real `LampController` with a stand-in bridge that records what lands, so no bulb moves. A keyframe's drag sends nothing, even with a tick landing during it, and its drop arrives at the usual fade. After a preview a bulb goes back to its hold or the
day, quickly, followers too, paused or not, including letting go with a preview's send still on its way, and previewing an off keyframe doesn't leave it off. A routine moving a bulb gets put back, held or on a flat stretch.

The law `tests/drag-moves-time.sh` checks the window's half of that: a drag's functions write only the time and call nothing that sends to the bulbs, and a new keyframe samples the band. `tests/card-stays-open.sh` checks that only `deselect` closes the card and the menus don't call it.

`./build.sh drive time-field` (~6s): clicks the time field's arrows off-screen, taking no focus. They step
what's highlighted and write to the keyframe showing now.

By hand only: the window, how the card moves, pairing, that the bridge takes the fades, how the
blend looks in the room.

## Calls

- 2026-11-04 11:57, 1.1.0. **A keyframe's settings sit on a card under the rows, not an inspector.** The day runs left to
  right and an inspector takes that width from it, and the sliders stay long: "i just like the
  long sliders more". It's there only while a keyframe is selected, so nothing has to say "select
  one": the dots are "the most obvious thing to explore". It comes down from under the timeline
  and never covers it, "always below the timeline".

- 2026-11-04 21:19, 1.1.0. **Rows keep their height.** Rows stretched to fill the window looked "horrendous", and
  the space below them isn't the problem *Empty space is spread out* is about: that was the
  writing on the card. They grew twice, to a 34-point band, so a keyframe has room
  around it: "you can barely see the bg around it when its near the bright spots".

- 2026-11-04 14:51, 1.1.0. **Holding is a small extra.** "Sometimes I just need to get more light or something", then back to the
  schedule. It isn't a reason to open Sundial, so the seed stays as it is and holding shouldn't grow into a mode.

- 2026-11-04 22:14, 1.1.0. **A hold holds against the bridge too.** "The hold color doesn't actually hold it sometimes? It goes back to the preset colors." Sundial only sent when its target moved and a hold's
  doesn't, so anything else moving the bulb had it to itself: the room log showed both bulbs falling from 100% for four minutes while every tick sent 0. So a tick also compares what
  the bulb reads. Applies *Never a fight with the controls*.

- 2026-11-04 22:30, 1.1.0. **Brightness is a ring around the true colour.** "Make the brightness fill the white around the ring", from the top and clockwise, picked over pill bars, at 20 points with a thin
  line: 22 was "a bit" big, so it came back down keeping "the ratio of circle to ring". With the true colour and the brightness both here, the band's top can hold back: full brightness shows 90% of the real colour because it's "a bit too bright sometimes at night". The dim end stays
  dim, since lifting it looked "a bit too bright": "the real dimness from before". An off keyframe isn't pitch black: it's dimmed as the card's wheel
  is, with a diagonal in the ring's grey that runs "a bit outside the circle so it looks like the ∅".

- 2026-11-04 21:17, 1.1.0. **A follower follows a hold too.** "When a light is following another light the temp colors should also be followed." Its day is the other bulb's, and a held
  colour sits on top of that day. Applies *Never a fight with the controls*.

- 2026-11-04 14:17, 1.1.0. **No Disable.** It only existed to hold a colour for a while, and two on/off controls side by side were
  the cost: a new person can't tell them apart. Holding does that job, so a keyframe is either in the day or
  deleted. Keyframes saved as disabled count again.

- 2026-11-04 14:17, 1.1.0. **Every control says what it is.** The switch sits beside the name it controls and always means the bulb.
  Time keeps its label even though the value explains itself, and off is a switch rather than the bottom of
  the slider, which only looks obvious to whoever built it. Applies *Never a fight with the controls*.

- 2026-11-04 18:22, 1.1.0. **Delete is on right-click only.** "There's no good place to put it" on the card: a trash icon beside the X was "very easy to
  mix up", and in words it took the end of the time's row for something rarely used. The X stays at the top right, and the time goes
  right under the name because "the time is basically their id".

- 2026-11-04 18:22, 1.1.0. **A card says whether it's a light or a keyframe.** The two look alike: "its not immediately obvious". So the name is followed by
  "Keyframe" or "6 Keyframes", in the same style, and only the light lights up its whole row. A keyframe shows on its dot.

- 2026-11-04 22:29, 1.1.0. **Return to schedule is orange text.** "It's the call to action", on an ordinary button rather than a filled one. It's worded as an imperative, since it's something you do: it used to say Back to schedule.

- 2026-11-04 20:47, 1.1.0. **The rows are on a card too.** "Yeah the light can go in a card too." Both cards share one ground, and a keyframe's comes out from behind the rows'.

- 2026-11-04 16:21, 1.1.0. **A dimmed slider keeps its fill.** Off looks the same as Temperature on a colour: a grey fill at half strength. `.disabled` would
  take the fill away, and "removing the filled bar looks kind of weird". Temperature's look was already "fine". Applies *What you
  touch is what the monitor does*: it says "Off" and can't be dragged.

- 2026-11-04 20:47, 1.1.0. **A time looks the same everywhere.** "Why is there no line on the popup one?" and "theres more padding on the bottom than the top": the window, the
  popup and the Schedule share `TimeField`, so they can't drift apart. Its arrows are the system's stepper and step what's highlighted, as the picker's own
  did. Applies *Never a fight with the controls*.

- 2026-11-04 22:51, 1.1.0. **A right-click leaves the card open.** "Right click actions should not close the color setting if it's open." Deleting the keyframe it shows leaves nothing to show, and then "it can just select the row
  instead". Applies *Never a fight with the controls*.

- 2026-11-04 22:50, 1.1.0. **A drag moves the time, not the room.** Dragging a keyframe used to show it on the bulb: "there's no need since dragging just means change the time not the colors". The band already
  shows the day it makes, and scrubbing past noon at night would flood the room (*Motion spends attention*). *What you touch is what the monitor does* is about sliders: a time isn't something
  the room can show. So the bulb waits for the drop and then fades at the usual pace, since nothing moved for it to come back from.

- 2026-11-04 22:50, 1.1.0. **A drag changes only the time.** A dragged keyframe used to take the colour under it, worked out without itself, so a 10-minute nudge took noon from 100% to about 49%, and it used to turn an off one
  back on: "why does dragging a keyframe that is off turn it back on?" A typed time already kept its look. "If you want a color between 2 keyframes that's what making a new keyframe is for." Applies *Never a fight with the controls*.

- 2026-11-04 20:47, 1.1.0. **The way back is quick.** 1 second "still feels a bit slow", and the wait before it counted too: the moved bulb took its turn behind the rest. Gradually is for
  the day (*Just right for the room*); this answers your hand. Half a second, the moved bulbs first, with the preview's pacing cut short.

- 2026-11-02 05:18, 1.1.0. **A lamp switched off by hand stays off.** Sundial used to send on with every
  fade, so a lamp switched off from the phone came back on within a minute: "It
  should not re set the light color when I've turned off the lights". Only the
  person who switched it off switches it back on. Applies *Never a fight with the controls*.

- 2026-11-04 12:17, 1.1.0. **A colour's Temperature slider stays still.** The dimmed look is fine, but moving with the wheel
  "sends mixed signals": it says the number still means something. It keeps the value from before
  the colour.

## Gotchas

- The status line stays on its last "Paired" through a stall. Each tick logs one line, so whether the lamps are being sent is read with `/usr/bin/log show --last 1h --predicate 'subsystem == "com.aurende.sundial" AND category == "lamps"'`. A "back to the day" line says how long a return took to send.
- A lit lamp's colour or brightness changed in the Hue app, or by a routine there, is set back within a minute or so while Follow is on, held or not. A tick's log line says how many it put back. Pause keeps the change.
- Previewing a keyframe or Play the day lights a bulb that was off, and it stays on afterwards. Previewing an off keyframe counts as Sundial turning it off, so the way back lights it even if someone had switched it off first.
- After a relaunch, a lamp that a keyframe had turned off counts as switched off by hand, since that memory isn't saved, and stays off until it's switched on.
- Above about 5 calls a second the bridge still answers 200 but takes seconds to (measured 2026-11-01: 0.3s at 5/s, 2.3s at 10/s, 3.8s at 20/s), so previews send only the newest state, about 2 per bulb per second, and a slower one would look like lag, not failure.
- Color temperature stops at 2000 K on these bulbs and a higher mirek silently gives 2000 K, so Sundial always sends xy, which holds 1700 K exactly. Below that the white curve is a table of Planck's law, ending at 700 K, where it reaches these bulbs' red corner (xy 0.692, 0.308).
- SwiftUI's time picker puts its text high in its field (3 points above, 6 below) and draws a bright line between its arrows until its shown time changes, then a faint one (macOS 27, measured off-screen). A vibrant appearance, a redraw or focus doesn't change the line, and overriding the cell's interior drawing doesn't move the text. So `TimeField` is a bare picker on its own ground with a separate stepper, whose line is always faint.
- macOS asks for the Keychain again after every `./build.sh`, because the app is
  signed ad-hoc and each build is a new signature to it. Allow lasts one launch,
  Always Allow lasts until the next build. Until it's answered the lamps wait and
  the status says so; the rest of the app runs.
- macOS asks for local network access the first time Sundial looks for the bridge.
  Refused, no bridge is found. Allow it in System Settings → Privacy & Security
  → Local Network.
