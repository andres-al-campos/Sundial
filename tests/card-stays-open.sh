#!/bin/bash
# Law: a right-click never closes the Lights card.
#
# "right click actions should not close the color setting if it's open". Only `deselect` closes the
# card, and it's for the X and clicks around the rows, so this reads who sets the selection to nil
# and who calls it. SwiftUI's menus can't be opened off-screen.

cd "$(dirname "$0")/.."
view=src/views/LightsView.swift

body_of() { awk -v f="private func $1" 'index($0, f){on=1} on{print} on && /^    }$/{on=0}' "$view"; }

outside=$(awk 'index($0, "private func deselect"){skip=1} !skip && /selection = nil/{print NR": "$0} skip && /^    }$/{skip=0}' "$view")
if [ -n "$outside" ]; then
    echo "✗ card-stays-open: $view closes the card outside deselect, at line $outside. Move the selection instead: showRow(bulb) puts the bulb's own card in its place."
    exit 1
fi
for menu in keyMenu bandMenu rowMenu; do
    body=$(body_of "$menu")
    if [ -z "$body" ]; then
        echo "✗ card-stays-open: can't find $menu in $view. If it was renamed, update tests/card-stays-open.sh."
        exit 1
    fi
    if printf '%s\n' "$body" | grep -q 'deselect'; then
        echo "✗ card-stays-open: $menu in $view calls deselect, so a right-click closes the card. Leave the selection alone, or use showRow(bulb) if its keyframe is gone."
        exit 1
    fi
done
if ! grep -q 'onChange(of: keyframeGone)' "$view"; then
    echo "✗ card-stays-open: $view no longer watches for the card's keyframe going away. Without it a deleted keyframe leaves a stale card whose controls do nothing. Move to showRow(bulb) when it goes."
    exit 1
fi
echo "✓ card-stays-open: a right-click leaves the card open, and a keyframe going away moves it to the bulb's own card"
