# Sundial

A macOS menu bar app that sets your monitor's brightness, contrast and Night Shift, and your Philips Hue lamps, so the light in the room matches the natural light from morning to night without you touching a slider.

Sundial drives your monitor's **hardware** brightness and contrast over DDC, not a software dimming overlay — so it's the real backlight changing, the same as the buttons on the monitor itself. Night Shift warmth is driven through macOS's built-in Night Shift.

## What it does

- **Auto** (the main mode) — reads the room's light with the MacBook's ambient light sensor, the photodiode beside the camera (not the camera). By day you set the brightness you like once and the room's light scales it; contrast follows brightness at a multiple you can drag. From 30 minutes before sunset the sensor mostly sees the lamps, so the clock takes over: the screen fades to your night minimum by bedtime, fast at first and slower later. A drag in the evening restarts the fade from what you chose, and is kept through sleep and restarts. Night Shift warms from before sunset to full at bedtime, then turns off before sunrise. No presets needed.
- **Lamps** — pair a Hue bridge and each bulb gets a day of color keys, each a brightness and a color or white temperature, at a time or tied to sunrise, sunset or bedtime. The Lights window draws them as a band per bulb; Sundial fades the bulbs between keys. A drag in the popup holds a bulb until you return it to the schedule.
- **Presets and a schedule** — instead of Auto, presets like _Morning_, _Day_, _Evening_ and _Night_, each a brightness, contrast and Night Shift strength at a time of day. Sundial applies the one whose time most recently passed, fading to it over a minute.
- **Live control** — drag a slider in the menu bar and the monitor or bulb follows as you drag.
- **Undo** — in the window, Cmd-Z undoes changes to presets and color keys; Shift-Cmd-Z, Cmd-Y or Control-Y redo.
- **Wake handling** — re-applies the right settings when your Mac wakes, so the screen is right the moment you return.
- **Launch at login** — optional; lives quietly in the menu bar, with a Dock icon only while its window is open. Pinned to the Dock, a click opens the window.

Everything lives under `~/Library/Application Support/Sundial/`: settings, presets and color keys in `config.json`, and two logs, kept for tuning Auto against what you actually chose: `room-log.csv` (the room's light, what the screen and bulbs were set to, and each drag, once a minute) and `lights-log.jsonl` (each change to the color keys). The bridge's key is in the Keychain.

## Requirements

- macOS 14 (Sonoma) or later
- A Mac with Apple silicon
- A monitor that supports DDC/CI (most external displays do)
- Optional: a Philips Hue bridge on the same network, for the lamps
- For building: [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode

## Monitor compatibility

I've only tested Sundial on my own monitor — a Gigabyte M27Q. It controls brightness and contrast over DDC/CI (a VESA standard), so it should work on most external monitors that support DDC, but I can't promise it works on yours.

If it doesn't, the usual suspects are: DDC/CI is switched off in the monitor's on-screen menu (often the default), the monitor doesn't properly honor the standard brightness/contrast controls, or an adapter or dock in between doesn't pass DDC through. The Mac's own HDMI port works: Sundial talks to its converter chip the way [m1ddc](https://github.com/waydabber/m1ddc) does. Built-in laptop and most Apple displays don't use DDC at all.

To keep this from being a mystery, Sundial does nothing until it has found your monitor: on first launch it fills in the connected monitor's name, you hit **Connect Monitor**, and the rest unlocks only if a monitor by that name is there. If it works on a monitor not listed here, a note or PR is welcome.

## Build & install

```bash
./build.sh          # build, install to /Applications, and relaunch
```

`build.sh` regenerates the Xcode project from `project.yml`, builds a Release `.app`, copies it to `/Applications`, and relaunches it. To install somewhere else, copy `build.local.env.example` to `build.local.env` and set `INSTALL_DIR`. Other options:

```bash
./build.sh -n       # build only, stage into ./build/Sundial.app (no install)
./build.sh check    # the checks in tests/: types, tests and laws (no build, no window)
./build.sh drive    # every feature check in tests/drive/, off-screen; add a name for one
./build.sh -v       # verbose xcodebuild output
./build.sh --help   # usage
```

> Install via `./build.sh` (not by running a Debug build from Xcode) so launch-at-login binds the app in `/Applications` rather than a transient DerivedData path.

Prefer not to build it yourself? Grab the latest `Sundial.app` from the [Releases](https://github.com/andres-al-campos/Sundial/releases) page, unzip it, and drag it to `/Applications`.

## First run

1. Click the sun icon in the menu bar — Sundial opens to a **setup screen**.
2. Check the **monitor name**, filled in from the connected monitor (any part of the name matches).
3. Hit **Connect Monitor**. If a monitor by that name is connected, the popup opens on Auto; otherwise the error tells you what to check (see [Monitor compatibility](#monitor-compatibility)).
4. Sundial starts in Auto. Drag Brightness once in daylight to the level you like and it takes over from there. To set up lamps, open the popup's Lights tab and pair the bridge; macOS asks for local network access and, after each new build, for the Keychain. You can change the monitor's name later in Open Sundial → Settings.

## How it works

| Setting     | Driven by                                                        |
| ----------- | --------------------------------------------------------------- |
| Brightness  | DDC VCP `0x10` (real backlight)                                 |
| Contrast    | DDC VCP `0x12`                                                  |
| Night Shift | macOS Night Shift (CoreBrightness)                              |
| Lamps       | Philips Hue bridge, over the local network                      |

In Auto, brightness before sunset is your level times the square root of the room's light against 100 lux, and contrast is a multiple of brightness. After the handover it fades toward your night minimum, with what's left halving every 2.5 hours, scaled to arrive at bedtime. The monitor moves at most 5 points a second, so changes are gradual. On a schedule, the active preset holds until the next, fading over a minute. On wake, Sundial forces a full re-apply.

## Releasing

To cut a release, bump `MARKETING_VERSION` in `project.yml`, commit, push, then run:

```bash
./release.sh
```

It reads the version from `project.yml`, refuses to run on a dirty or unpushed tree, builds a fresh `.app`, zips it, tags `v<version>`, and publishes a GitHub release with the zip attached and auto-generated notes.
