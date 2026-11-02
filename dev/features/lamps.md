# Lamps

Updated 2026-11-02 02:02, at 1.1.0.

Sundial sets the Hue lamps through the day from your scenes, so the room's
artificial light follows the natural light along with the screen.

## Sub-features

- **Lights window.** One row per bulb across the day, read from the bridge, the
  band showing the bulb's colour dimmed by its brightness, with Sunrise, Sunset
  and Darkest marked.
- **Keyframes.** Each bulb has its own, with a straight line between neighbours
  and no hidden holds: a hold is two matching keyframes. Click a band to add one
  (the band doesn't change). Click a dot for its time, on/off, brightness, white
  (1700 to 6500 K) and colour, or to delete it.
- **Moving.** A dragged keyframe shows the colour under it and takes that on
  drop. A typed time keeps its look. Within 10 minutes of a mark it snaps and
  follows that mark. Imported keyframes can follow one at an offset, such as 40
  minutes before sunset.
- **Previews.** Changing a keyframe shows it on the bulb until its settings close.
- **Right-click.** Copy and paste a keyframe, its look, or a bulb's whole day;
  rename a bulb, which renames it on the bridge; make one bulb follow another's
  day, and unlink it again.
- **Undo.** Cmd-Z and Shift-Cmd-Z cover every change to the bulbs.
- **Play the day** runs the day on the bulbs in 20 seconds and returns to now.
- **Pause** stops Sundial changing the bulbs until Resume, so the Hue app can use them.
- **Import.** The first run makes each bulb's day from the seven named scenes on
  the bridge, keeping what the lamps did at every minute. After that Sundial holds the
  settings, and scene edits in the Hue app aren't read.
- **Continuous fade.** Every 30 seconds each bulb is sent a 30-second fade to
  where it should be, so it never steps. After wake, every bulb is sent again.
- **Pairing.** Settings → Lamps → Pair Hue Bridge finds the bridge with
  Bonjour and waits up to 30 seconds for its button to be pressed. The key is
  kept in the Keychain. Only the home network is needed, not the internet.

Not built: deleting a bulb from the bridge, or adding a new one. Undo doesn't cover presets.

## How to get to it

Click the sun in the menu bar, then Open Sundial, then Lights.

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
and the keyframe rules: straight lines, fading to off, leaving out a dragged
keyframe, snapping, anchors, and reading whites back as a temperature.

By hand only: the window, pairing, that the bridge takes the fades, how the
blend looks in the room.

## Gotchas

- The status line stays on its last "Paired" through a stall. Each tick logs one line, so whether the lamps are being sent is read with `/usr/bin/log show --last 1h --predicate 'subsystem == "com.aurende.sundial" AND category == "lamps"'`.
- A lamp changed in the Hue app is set back within 30 seconds while Follow is on.
- Above about 5 calls a second the bridge still answers 200 but takes seconds to (measured 2026-11-01: 0.3s at 5/s, 2.3s at 10/s, 3.8s at 20/s), so previews send only the newest state, about 2 per bulb per second, and a slower one would look like lag, not failure.
- Color temperature stops at 2000 K on these bulbs and a higher mirek silently gives 2000 K, so Sundial always sends xy, which holds 1700 K exactly.
- macOS asks for local network access the first time Sundial looks for the bridge.
  Refused, no bridge is found. Allow it in System Settings → Privacy & Security
  → Local Network.
