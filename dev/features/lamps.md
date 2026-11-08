# Lamps

Updated 2026-11-07 20:47, at 1.1.0.

Sundial sets the Hue lamps through the day from your scenes, so the room's
artificial light follows the natural light along with the screen.

## Sub-features

- **Lights window.** One row per bulb across the day, on a card, read from the bridge, the
  band showing the bulb's colour dimmed by its brightness, reaching 90% of the real colour at full brightness. A keyframe is its true colour in a ring whose white fills
  with its brightness, clockwise from the top; an off one is its colour at half strength, as the card's wheel is when off, with a slash in the ring's grey running past the rim, as in ∅. Above the bands are
  today's Sunrise, Sunset and Bedtime times, worked out each day; a label too close
  to another moves aside, and a tick stays on the real time. A line marks the time now, ending in a solid head under the last row.
- **Popup.** The popup's Lights tab (Light, with one bulb, the window's name for them) has a row per bulb: its true colour, its name, and a
  brightness slider with a sun before it, as Control Center's display slider has. A drag moves
  the bulb as it goes and holds it, as the window's card does, and turns on a bulb that was off.
  While paused there's no hold: the drag just sets the bulb, and pausing ends every hold, from
  the button or the command line, so Resume takes every bulb back to the day.
  A click on the name opens the window. Over the rows one line says Paused or when the next
  color key comes; under them, outlined, Pause on the left and, while a bulb is held, Return to schedule beside it,
  which glides the sliders back as the bulbs fade. The orange name says a bulb is held: a third
  orange "Held until sunrise" was "too much orange". While the
  lights are off the day the tab's label is orange, on either tab, so the orange sun leads to
  it. Unpaired, the tab offers to pair the bridge.
- **Keyframes** ("color keys" on screen). Each bulb has its own, with a straight line between neighbours
  and no hidden holds: a hold is two matching keyframes. Click a band to add one
  (the band doesn't change, since it takes the colour in between). Click a dot for its time, on/off, brightness, temperature
  (700 to 6500 K) and colour. Right-click a dot to delete it. A bulb the bridge has no scene for starts
  on three: sunrise, sunset and bedtime. Until they're changed its name says to click a dot.
- **Temperature** only means something for the glowing-metal whites. For any other colour
  the slider dims, says "Color", and stays where it was before the wheel left the whites.
  That's remembered until Sundial quits; a keyframe that's already a colour sits at its
  nearest temperature. Dragging the slider goes back to a white.
- **Moving.** Dragging a keyframe changes only its time, as typing one does: it keeps its colour, brightness and on or off, and the band reshapes around it as it moves. The bulbs stay as they are until the drop, then fade to the new day at the usual pace. Dropped within 10 minutes of a mark it lands on it and reads "At sunset".
- **Following the day.** The menu beside a keyframe's time says what it keeps to: "Every day at this time", like an alarm, or a time after the mark on its left or before the one on its right, such as "1 hr 9 min after sunset", so it moves as the sun's times change across the year. On a mark, the choices are that time or "At sunset". Dragging keeps the choice, following whichever marks are now either side; a typed time is taken as typed, without snapping. A new keyframe follows the nearer mark.
- **Previews.** Changing a keyframe's settings shows it on the bulb. A badge in the top row says
  what it lands on, such as 45% at 6:48 PM, during a drag too. On letting go of a setting the bulb fades back to where
  the day has it, or to its hold, over half a second, and only the bulbs that moved are sent.
- **Holding.** Click a bulb's name and its whole row lights up, and the same card changes that bulb right now,
  from what the lamp is doing, without touching a keyframe. The first change holds it: its name turns orange
  and the card says "Held until sunrise" with Return to schedule in orange text, which fades it back in half a second.
  A hold ends by itself at the next sunrise, and a relaunch keeps it until then. Bulbs following the one clicked take the hold too, unless they're held themselves:
  a follower's own card can hold it apart, and its Return to schedule ends whichever hold it's under. Rename is on the right-click menu.
- **Card.** Click a keyframe and its settings come down on a card from behind the
  rows' card, which stays put: a colour wheel, then the settings reading left to right and top
  to bottom: the bulb with its on/off switch to the left of its name and "Color Key" or "6 Color Keys" after it, the time,
  then long Brightness and Temperature sliders. A faint line divides the wheel from the rest. Off dims the wheel and
  sliders, keeping their fill, and both say "Off". Every button shades on hover, and pointing at a bulb's name shades its whole row. The band shows nothing on hover:
  a ring where a click would add a color key was "annoying when you're just moving around". The rows scroll only if the
  window can't fit them and the card. Its close button or clicking the dot again puts it
  away, as does clicking around the rows. A right-click leaves it open. If its keyframe goes, from a delete, Paste Day or an undo, it moves to that bulb's own card.
- **Colour wheel.** Its green and blue are the screen's and its red the bulbs', so every
  temperature has its own spot. Screens run out of red around 900 K, so below that the
  thumb moves and the bulb changes while the colours on screen stay the same red.
- **Right-click.** Copy a keyframe and paste it onto another or onto a band at the point clicked. It brings its look and its rule (every day at this time, or after or before a mark), at the time where it lands, or copy and paste a bulb's whole day;
  rename a bulb, which renames it on the bridge; make one bulb follow another's
  day, and unlink it again.
- **Undo.** Cmd-Z and Shift-Cmd-Z cover every change to the bulbs.
- **Play the day** runs the day on the bulbs in 10 seconds and returns to now.
- **Pause** stops Sundial changing the bulbs until Resume, so the Hue app can use them.
  A preview while paused still shows on the bulb, then fades back to what the bulb was.
  While paused the status line, Resume and the menu bar sun are orange; Stop is orange while the day plays, and Return to schedule shows in the header while a bulb is held.
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

It also checks that importing the scenes matches the old blend at every minute,
the keyframe rules: straight lines, fading to off, snapping, anchors, and reading whites back as a temperature, and that a
lamp someone switched off is left alone.

It also checks that a keyframe saved as disabled counts, a new bulb's three keyframes, what counts as new, and that whites have a
temperature and colours don't.

It also checks when a hold ends and whose hold a follower is under.

`./build.sh drive held-lamp` (~15s): the real `LampController` with a stand-in bridge that records what lands, so no bulb moves. A keyframe's drag sends nothing, even with a tick landing during it, and its drop arrives at the usual fade. After a preview a bulb goes back to its hold or the
day, quickly, followers too, paused or not, including letting go with a preview's send still on its way, and previewing an off keyframe doesn't leave it off, while a bulb switched off by hand goes back off after a preview. A routine moving a bulb gets put back, held or on a flat stretch.

The law `tests/drag-moves-time.sh` checks the window's half of that: a drag's functions write only the time and call nothing that sends to the bulbs, and a new keyframe samples the band. `tests/card-stays-open.sh` checks that only `deselect` closes the card and the menus don't call it.

`./build.sh drive window` (~20s): builds the real window from the code as it is and renders Lights off-screen to PNGs, dark and light, taking no focus. `WINDOW_OUT=dir` keeps them and `WINDOW_REAL=1` starts from a throwaway copy of the real config. It shows the window at rest; showing a card takes a scratch copy of `src/` calling the view's private functions.

`./build.sh drive popup` (~20s): builds the real popup and renders both tabs off-screen, taking no focus. It checks the Lights label turns orange while a bulb is held and that a hold doesn't resize the popup. `POPUP_OUT=dir` keeps the PNGs. A slider's drag isn't driven: the hold it makes is `AppState.holdLamp`, the window card's too.

`./build.sh drive time-field` (~6s): clicks the time field's arrows off-screen, taking no focus. They step
what's highlighted and write to the keyframe showing now.

By hand only: the window, a real drag and the right-click menus (SwiftUI's gestures and menus take nothing off-screen), how the card moves, pairing, that the bridge takes the fades, how the
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

- 2026-11-04 23:22, 1.1.0. **Sundial is the lights' only schedule.** The bridge's own routines were turned off in the Hue app "so they don't get in the way". The cost is that the lights stay where they are while the Mac is asleep or off,
  and catch up on wake.

- 2026-11-04 22:30, 1.1.0. **Brightness is a ring around the true colour.** "Make the brightness fill the white around the ring", from the top and clockwise, picked over pill bars, at 20 points with a thin
  line: 22 was "a bit" big, so it came back down keeping "the ratio of circle to ring". With the true colour and the brightness both here, the band's top can hold back: full brightness shows 90% of the real colour because it's "a bit too bright sometimes at night". The dim end stays
  dim, since lifting it looked "a bit too bright": "the real dimness from before". An off keyframe isn't pitch black: it's dimmed as the card's wheel
  is, with a diagonal in the ring's grey that runs "a bit outside the circle so it looks like the ∅".

- 2026-11-04 14:17, 1.1.0. **No Disable.** It only existed to hold a colour for a while, and two on/off controls side by side were
  the cost: a new person can't tell them apart. Holding does that job, so a keyframe is either in the day or
  deleted. Keyframes saved as disabled count again.

- 2026-11-05 18:30, 1.1.0. **Delete is on right-click only.** "There's no good place to put it" on the card: a trash icon beside the X was "very easy to
  mix up", and in words it took the end of the time's row for something rarely used. The close chevron stays at the top right, and the time goes
  right under the name because "the time is basically their id".

- 2026-11-04 16:21, 1.1.0. **A dimmed slider keeps its fill.** Off looks the same as Temperature on a colour: a grey fill at half strength. `.disabled` would
  take the fill away, and "removing the filled bar looks kind of weird". Temperature's look was already "fine". Applies *The room shows
  what you're changing*: it says "Off" and can't be dragged.

- 2026-11-05 12:13, 1.1.0. **The way back is quick.** 1 second "still feels a bit slow", and the wait before it counted too: the moved bulb took its turn behind the rest. Gradually is for
  the day (*Just right for the room*); this answers your hand. Half a second, the moved bulbs first, with the preview's pacing cut short. A deleted keyframe's bulb goes the same way: half a second.

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
- After a relaunch, a lamp that a keyframe had turned off counts as switched off by hand, since that memory isn't saved, and stays off until it's switched on.
- Above about 5 calls a second the bridge still answers 200 but takes seconds to (measured 2026-11-01: 0.3s at 5/s, 2.3s at 10/s, 3.8s at 20/s), so previews send only the newest state, about 2 per bulb per second, and a slower one would look like lag, not failure.
- Color temperature stops at 2000 K on these bulbs and a higher mirek silently gives 2000 K, so Sundial always sends xy, which holds 1700 K exactly. Below that the white curve is a table of Planck's law, ending at 700 K, where it reaches these bulbs' red corner (xy 0.692, 0.308).
- SwiftUI's time picker puts its text high in its field (3 points above, 6 below) and draws a bright line between its arrows until its shown time changes, then a faint one (macOS 27, measured off-screen). A vibrant appearance, a redraw or focus doesn't change the line, and overriding the cell's interior drawing doesn't move the text. So `TimeField` is a bare picker on its own ground with a separate stepper, whose line is always faint.
- macOS asks for the Keychain again after every `./build.sh`, because the app is
  signed ad-hoc and each build is a new signature to it. Allow lasts one launch,
  Always Allow lasts until the next build. Until it's answered the lamps wait and
  the status says so; the rest of the app runs. Declined, the lamps stop and the
  popup, the Lights window and Settings say why, with Allow Keychain Access to
  ask again (tests/drive/held-lamp.sh).
- macOS asks for local network access the first time Sundial looks for the bridge.
  Refused, no bridge is found. Allow it in System Settings → Privacy & Security
  → Local Network.
