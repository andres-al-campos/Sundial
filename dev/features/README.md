# Sundial features

Updated 2026-11-12 21:09, at 1.1.0.

What a user can do with Sundial, how to reach it, and how to drive it. Read
this before adding anything: if it's already here, extend it instead of
building it again.

This map is partial. It grows one feature at a time, as each is changed.

| Feature | File | Platforms | Driveable headless? |
|---|---|---|---|
| Room Light | [room-light.md](room-light.md) | macOS | Partly: the room-light decisions (2026-10-26), a hold surviving a relaunch (2026-11-09) |
| Schedule | [schedule.md](schedule.md) | macOS | Partly: the HDR contrast lock's decision (2026-10-12), the scroll handle resizing once (2026-11-08), undo (2026-11-09) |
| Lamps | [lamps.md](lamps.md) | macOS | Partly: the blending between keyframes (2026-11-02), the lights log (2026-11-09) |
| Command line | [cli.md](cli.md) | macOS | Partly: what each URL means (2026-11-02) |

## What counts as a feature

Something a user sets out to do, with its own way in. What you only reach
inside a feature is a sub-feature and lives in that feature's file.

## Each file has

- **Sub-features**: what a user can do inside it, including limits.
- **How to get to it**: the user's path.
- **Driving it**: preconditions, the command that checks it, and what it
  observes. With no check, "No check yet" and why.
- **Gotchas**: what has bitten us or will.

Claims describe observable behavior, not code locations.

## Keeping it current

Update a feature's file in the same commit that changes the feature. A
feature touched for the first time gets a file and a row here.

## Driving conventions

`./build.sh check` runs every law in `tests/`, including the one that keeps
this map and its files in step. `./build.sh check --drives` then runs every drive.

A feature's check is `tests/drive/<name>.sh`. `./build.sh drive` runs them all and
`./build.sh drive <name>` runs one; a name with no script is an error. There
is no test target.

Sundial's features act on a real monitor over DDC, and
its UI lives in a menu bar popover, so a drive covers a decision the app makes
(compiled out of the app's source with a harness) and the rest is checked by
hand.
