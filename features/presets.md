# Presets

A preset is a brightness, a contrast and a Night Shift strength with a time of
day. Sundial applies the preset whose time most recently passed.

## Sub-features

- Edit a preset's time, name, brightness, contrast and Night Shift, and turn it
  on or off.
- The active preset's sliders move the monitor as you drag.
- Dragging a slider on another preset previews that preset on the monitor; the
  Preview button does the same. Collapsing the row or closing the menu ends it.
- Add and delete presets.
- **Contrast locks in HDR.** While the configured display is in HDR, the
  Contrast slider is greyed out with a lock beside its label, and hovering the
  row says why. The value stays visible. The schedule still sends contrast: the
  monitor stores it and uses it when HDR goes off.

## How to get to it

Click the sun in the menu bar, then click a preset's row to expand it.

## Driving it

Preconditions: none; needs the Swift toolchain, no monitor.

`./build.sh drive hdr-contrast-lock` (~5s): compiles the app's HDR decision
with a harness and feeds it screen lists. It checks that the lock is on only
when the screen matching the display name has HDR headroom: not in SDR, not
because another screen is in HDR, not with no name set.

Last driven: 2026-10-12, macOS. Passed; failed as expected against a copy with
the headroom comparison loosened.

By hand only: that the slider greys and ungreys when HDR is toggled in System
Settings → Displays, and everything else in this feature (editing, live apply,
preview, add, delete).

## Gotchas

- A Gigabyte M27Q in HDR accepts a contrast write over DDC and reads it back
  (48, 64 and 19 all round-tripped on 2026-10-12) while the picture doesn't
  change. The scheduler's drift check therefore sees a match in HDR.
- HDR is read from macOS (the screen's potential EDR headroom), because
  BetterDisplay's `-hdr` query answers "Pro required". Measured once: 4.18 on
  the M27Q, presumably with HDR on. That it drops to 1 with HDR off is an
  agent's assumption from how macOS reports external displays, not yet
  measured. If the slider stays grey with HDR off, this is why.
- The lock applies to any display in HDR, on the assumption that monitors
  generally lock contrast there. Only the M27Q was observed.
- Brightness is not locked. Whether the M27Q honours it in HDR is not known.
- The note is a tooltip and a lock glyph, not a line of text, because the
  expanded card's height is pinned and a new line would push the card below
  it out of view. An agent's call.
- The slider refreshes its HDR state when the row appears and when macOS
  reports a screen change. Whether toggling HDR sends that report is not
  verified; reopening the row always refreshes.
