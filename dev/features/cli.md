# Command line

Updated 2026-11-12 21:09, at 1.1.0.

A script, a shortcut or a session can see what Sundial is doing and change it
without opening it.

## Sub-features

- **`scripts/sundial`**: `status`, `pause` and `resume` (the lights), `auto`,
  `schedule`, `open [lights|schedule|settings]` (`presets`, the Schedule tab's old
  name, still works), `brightness 0-100` and
  `contrast 0-100`. It prints the app's answer as JSON and exits non-zero if the
  app couldn't do it.
- **`lights`** prints every bulb's keyframes as JSON. **`lights load <file>`** replaces
  them with an edited copy, refusing a bad one and saying why, and keeps what it
  replaced in `lights-before-load.json`; the change goes in the lights log too. Minutes count from midnight, `anchor` ties
  a keyframe to `sunrise`, `sunset` or `darkest` plus an `offset`, and `x`, `y` is the
  colour. A new keyframe needs no `id`.
- **`hue`** prints the bridge's scenes and smart scenes as it holds them, without
  a Keychain prompt, since the app already has the key.
- **`screenshot`** captures Sundial's window to a PNG and prints its path. It needs
  no Screen Recording permission, since the window is the app's own.
- **`sundial://` URLs**: what the command sends, usable from anything that opens
  a URL: `sundial://lights/pause`, `sundial://mode/auto`, `sundial://open/lights`,
  `sundial://brightness/40`.
- **`status.json`** beside the config holds the last answer: the mode, brightness,
  contrast, Night Shift, room light, lights and any error.

## How to get to it

Run `scripts/sundial status` from the repo. To have it everywhere, link it onto
your PATH:

`ln -s "$PWD/scripts/sundial" ~/.local/bin/sundial`

## Driving it

Preconditions: none; needs the Swift toolchain, not the app.

`./build.sh drive remote` (~3s): compiles the app's parser with a harness and
checks what each URL means and that a wrong one says what would work.

By hand, on the installed app: `scripts/sundial status`, then `pause` and
`resume` (`lightsFollowing` flips), `brightness 200` (refused, exit 1), `lights`,
and `open` then `screenshot`.

## Gotchas

- `lights load` doesn't reach Cmd-Z in the window. `lights-before-load.json` is the way back.
- `brightness` and `contrast` act like dragging Auto's sliders: by day they change the level
  Sundial uses for this kind of room, not just the monitor for now; in the evening they hold until
  bedtime and the fade runs on from them; after bedtime they set the night pair.
- Any app or web page can open a `sundial://` URL. The worst it can do is change
  a setting you can change back, so nothing here deletes anything or reads a key.
- `open -g` starts Sundial if it isn't running, so a command can launch it.
