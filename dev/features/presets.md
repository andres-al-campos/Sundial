# Presets

Updated 2026-11-08 00:49, at 1.1.0.

A preset is a brightness, a contrast and a Night Shift strength with a time of
day. In Schedule mode Sundial applies the preset whose time most recently
passed. Auto mode doesn't use them (see auto.md).

## Sub-features

- Edit a preset's time, name, brightness, contrast and Night Shift, and turn it
  on or off.
- The active preset's sliders move the monitor as you drag.
- Dragging a slider on another preset previews that preset on the monitor; the
  Preview button does the same. Collapsing the row or closing the menu ends it.
- Add a preset from the footer (it opens expanded, scrolled into view), and
  delete one from its card.
- **Contrast locks in HDR.** While the configured display is in HDR, the
  Contrast slider is replaced by the text "Locked by monitor in HDR", with a
  lock beside the label. The value stays visible. The schedule still sends contrast: the
  monitor stores it and uses it when HDR goes off.

## How to get to it

Click the sun in the menu bar, then Open Sundial, then Presets. Choose Schedule
on the popup's Display tab to have them drive the monitor; the popup then keeps the current
one's card open. Click a
preset's row to expand it.

## Driving it

Preconditions: none; needs the Swift toolchain, no monitor.

`./build.sh drive hdr-contrast-lock` (~5s): compiles the app's HDR decision
with a harness and feeds it screen lists. It checks that the lock is on only
when the screen matching the display name has HDR headroom: not in SDR, not
because another screen is in HDR, not with no name set.

Last driven: 2026-10-12, macOS. Passed; failed as expected against a copy with
the headroom comparison loosened.

`./build.sh drive time-field` (~6s): the arrows on the time field, which a preset's Time uses.

`./build.sh drive scroll-once` (~10s): opens and closes a card in a list long enough to scroll,
off-screen, and checks the list's scroll height changes once per toggle, so the scroll bar's handle
resizes once rather than on every frame. Last driven: 2026-11-08, passed; failed with 22 changes
per toggle when the change was wrapped in `withAnimation`, as it was before.

By hand only: that the note replaces the slider and goes away again when HDR
is toggled in System Settings → Displays, and everything else in this feature (editing, live apply,
preview, add, delete).

## Gotchas

- A Gigabyte M27Q in HDR accepts a contrast write over DDC and reads it back
  (48, 64 and 19 all round-tripped on 2026-10-12) while the picture doesn't
  change. The scheduler's drift check therefore sees a match in HDR.
- HDR is read from macOS (the screen's potential EDR headroom), because DDC
  has no standard code for it. It read 4.18 on the M27Q with
  HDR on, and the lock comes and goes as HDR is toggled (seen 2026-10-12).
- The lock applies to any display in HDR, on the assumption that monitors
  generally lock contrast there. Only the M27Q was observed.
- Brightness is not locked. Whether the M27Q honours it in HDR is not known.
- The note takes the slider's place instead of adding a line, so the card
  keeps its height whether HDR is on or off.
- The list shows one expanded card, its line and one collapsed card before it
  scrolls. The expanded card's height is measured and the cap follows
  it. The old fixed 195 had drifted from the real 189 and left a strip of the
  Add button peeking under the last card (fixed 2026-10-27). Each expand
  first reports 195, then 189 about 40ms later, so the cap takes a height
  only after it has held for 0.1s.
- The note is not a system tooltip: one was tried first and never appeared in
  the menu. The "Active" badge still uses one and may have the same problem.
- The lock follows an HDR toggle after a short delay.
- The popup opened at a 44pt floor, showed "No presets yet", then expanded the
  active card: three resizes per open (fixed 2026-10-21). Each open builds the
  panel views fresh, so anything set after the first layout is a resize. The
  list and the expanded card now come from the app's state at construction,
  and the list's first height is computed from its rows (the cap, for two or
  more presets). Setup and Settings are plain stacks, which size in one pass;
  the Connect button keeps its spinner's space when idle.
- The panel keeps its views' @State across opens, so a value given at
  construction counts only on the first open, and onDisappear doesn't fire on
  every close. The popup sometimes opened on the card it was closed on, or with
  the name field still in edit mode (fixed 2026-10-26): closing is now read
  from the window resigning key, which resets the expanded card to the active
  preset and ends a name edit. An active-preset change while closed also moves
  the expanded card.

- A time picker's hour or minute stayed selected after a click elsewhere,
  until the panel was rebuilt: SwiftUI's empty space and plain views don't
  take keyboard focus. A tap on the popup's background fixed Auto but not the
  cards, whose list catches the clicks first, so `EditFocus` watches every
  click and ends an edit on anything that isn't a field (2026-10-31).

## Calls

- 2026-10-12 19:29, 1.0.3. The HDR note is always shown, left-aligned, in the
  slider's place, not on hover: a slider that can't move has nothing to show,
  and the reason is the thing worth reading. Applies *The room shows what
  you're changing*.
- 2026-10-21 21:31, 1.0.3. Jitter on the first open after launch counts too,
  though nothing is kept yet: the list's first height is computed from its
  rows. A case of walled_garden's "A menu bar popup opens at its final size".
- 2026-11-02 02:08, 1.1.0. The popup's footer has Quit on the left and Open Sundial on the right, in
  every mode, and Add Preset moved to the window with the list. The popup only shows the
  current preset's card, expanded: it's for seeing and small tweaks, not sitting down to edit. Quit stays in one
  place across modes, and Open Sundial is blue, white on hover ("blue and white on hover"), in
  the link blue: the accent blue was too dark to read on the glass. Applies *Never a fight with
  the controls*.
- 2026-11-08 00:29, 1.1.0. In the window, the preset list is one column at Settings' width, centered, with Add Preset at
  the top right, and only one card opens at a time. A grid with every card open was tried and
  turned down: "theres no reason to see more than one at the same time".
- 2026-11-08 01:04, 1.1.0. Every button in the popup, Pause and Return to schedule as well as Quit and Open Sundial, is
  the one outlined style at one size: text in its own color at rest, and under the pointer white
  text, a shade and a brighter outline. The outline tells you where the click is. Applies *Never a
  fight with the controls*.
