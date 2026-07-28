# Sundial

A macOS menu bar app that schedules your monitor's brightness, contrast, and Night Shift by time of day — so your screen matches the room as it shifts from morning to night, without you ever touching a slider.

Sundial drives your monitor's **hardware** brightness and contrast over DDC (via the [BetterDisplay](https://github.com/waydabber/BetterDisplay) CLI), not a software dimming overlay — so it's the real backlight changing, the same as the buttons on the monitor itself. Night Shift warmth is driven through macOS's built-in Night Shift.

## What it does

- **Time-of-day presets** — define presets like _Morning_, _Day_, _Evening_, _Night_, each with a brightness, contrast, and Night Shift strength.
- **Scheduling** — assign a preset to a time; Sundial applies it automatically and smoothly interpolates between presets so the change is gradual, not a jarring jump.
- **Live control** — drag a slider in the menu bar to adjust the current display immediately.
- **Wake handling** — re-applies the correct preset when your Mac wakes, so the screen is right the moment you return.
- **Launch at login** — optional; lives quietly in the menu bar (no Dock icon).

Presets and schedule live in `config.json` under `~/Library/Application Support/Sundial/`.

## Requirements

- macOS 14 (Sonoma) or later
- [BetterDisplay](https://github.com/waydabber/BetterDisplay) installed (provides the CLI Sundial uses to set hardware brightness/contrast). Hardware brightness and contrast control are free features.
- A monitor that supports DDC/CI (most external displays do)
- For building: [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode

## Monitor compatibility

I've only tested Sundial on my own monitor — a Gigabyte M27Q. It controls brightness and contrast over DDC/CI (a VESA standard) via the BetterDisplay CLI, so it should work on most external monitors that support DDC, but I can't promise it works on yours.

If it doesn't, the usual suspects are: DDC/CI is switched off in the monitor's on-screen menu (often the default), the monitor doesn't properly honor the standard brightness/contrast controls, or it's connected over HDMI to an Apple Silicon Mac (hit or miss — DisplayPort/USB-C is more reliable). Built-in laptop and most Apple displays don't use DDC at all.

To keep this from being a mystery, Sundial won't let you create presets until it's confirmed it can actually read your monitor: on first launch you enter your BetterDisplay path and display name, hit **Connect Monitor**, and presets unlock only if that succeeds. If it works on a monitor not listed here, a note or PR is welcome.

## Build & install

```bash
./build.sh          # build, install to /Applications, and relaunch
```

`build.sh` regenerates the Xcode project from `project.yml`, builds a Release `.app`, copies it to `/Applications`, and relaunches it. Other options:

```bash
./build.sh -n       # build only, stage into ./build/Sundial.app (no install)
./build.sh -v       # verbose xcodebuild output
./build.sh --help   # usage
```

> Install via `./build.sh` (not by running a Debug build from Xcode) so launch-at-login binds the app in `/Applications` rather than a transient DerivedData path.

Prefer not to build it yourself? Grab the latest `Sundial.app` from the [Releases](https://github.com/andres-al-campos/Sundial/releases) page, unzip it, and drag it to `/Applications`.

## First run

1. Click the sun icon in the menu bar — Sundial opens to a **setup screen**.
2. Confirm the **BetterDisplay path** (default: `/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay`) and enter your **display name** — any partial match of the monitor name shown in BetterDisplay.
3. Hit **Connect Monitor**. If Sundial can read your monitor over DDC, presets unlock; otherwise the error tells you what to check (see [Monitor compatibility](#monitor-compatibility)).
4. Edit the presets and schedule to taste. Sundial takes over from there. You can revisit the path/name later via the **gear** icon.

## How it works

| Setting     | Driven by                                                        |
| ----------- | --------------------------------------------------------------- |
| Brightness  | BetterDisplay CLI → DDC VCP `0x10` (real backlight)             |
| Contrast    | BetterDisplay CLI → DDC VCP `0x12`                              |
| Night Shift | macOS Night Shift (CoreBrightness)                              |

The scheduler picks the active preset for the current time and interpolates between presets for smooth transitions. On wake, it forces a full re-apply so the display state always matches the schedule.

## Releasing

To cut a release, bump `MARKETING_VERSION` in `project.yml`, commit, push, then run:

```bash
./release.sh
```

It reads the version from `project.yml`, refuses to run on a dirty or unpushed tree, builds a fresh `.app`, zips it, tags `v<version>`, and publishes a GitHub release with the zip attached and auto-generated notes.
