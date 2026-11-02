# Lamps

Updated 2026-11-02 01:39, at 1.1.0.

Sundial sets the Hue lamps through the day from your scenes, so the room's
artificial light follows the natural light along with the screen.

## Sub-features

- **Scenes are keyframes.** Sundial reads the scenes on the Hue Bridge and
  places seven of them, by name, on the day: Morning at sunrise, Noon at 12:00,
  Twilight where Night Shift starts warming, Evening at last light (30 minutes
  after sunset), Night two hours before bedtime, MidNight one hour before,
  and DuskLight, the dimmest, at bedtime, where Night Shift is full. Bedtime
  is set in Auto (midnight by default). A scene that isn't on the
  bridge is left out. The times aren't settable yet.
- **Blending.** Between two scenes each lamp moves in brightness and colour
  along a straight line in the bridge's colour space (CIE xy), with its own
  brightness from each scene. Whites stored as colour temperature are
  converted to xy first. From Twilight to DuskLight the blend runs the whole
  way; Morning, Noon and DuskLight hold until 30 minutes before the next
  scene, so the lamps don't brighten all night.
- **Continuous fade.** Every 30 seconds each lamp is sent a 30-second fade to
  where it should be, so it never steps. After wake, every lamp is sent again.
- **Pairing.** Settings → Lamps → Pair Hue Bridge finds the bridge with
  Bonjour and waits up to 30 seconds for its button to be pressed. The key is
  kept in the Keychain. Only the home network is needed, not the internet.
- **Follow the day's scenes** in Settings turns it on or off. It runs in Auto
  and Schedule alike.

## How to get to it

Click the sun in the menu bar, open Settings, and find Lamps.

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

By hand only: pairing, that the bridge takes the fades, how the blend looks
in the room.

## Gotchas

- The status line stays on its last "Paired" through a stall. Each tick logs one line, so whether the lamps are being sent is read with `/usr/bin/log show --last 1h --predicate 'subsystem == "com.aurende.sundial" AND category == "lamps"'`.
- A lamp changed in the Hue app is set back within 30 seconds while Follow is on.
- Apart from bedtime, the scene times are fixed in `LampBlend.defaultTimes` until there's an editor.
- macOS asks for local network access the first time Sundial looks for the bridge.
  Refused, no bridge is found. Allow it in System Settings → Privacy & Security
  → Local Network.
