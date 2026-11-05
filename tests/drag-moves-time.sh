#!/bin/bash
# Law: dragging a keyframe changes only its time and sends nothing to the bulbs, and a new keyframe
# is how a colour between two others gets made.
#
# "dragging just means change the time not the colors", and "new keyframes should get the in-between
# color". The held-lamp drive covers the controller's half but makes the window's calls itself, and
# SwiftUI's gestures take no clicks off-screen, so this reads what the window's functions do.

cd "$(dirname "$0")/.."
view=src/views/LightsView.swift

body_of() { awk -v f="private func $1" 'index($0, f){on=1} on{print} on && /^    }$/{on=0}' "$view"; }

for f in moveKey dropKey; do
    body=$(body_of "$f")
    if [ -z "$body" ]; then
        echo "✗ drag-moves-time: can't find $f in $view. If it was renamed, update tests/drag-moves-time.sh."
        exit 1
    fi
    if printf '%s\n' "$body" | grep -nE 'previewOn\(|onPreviewLamps|endPreviewNow|onEndLampPreview' >&2; then
        echo "✗ drag-moves-time: $f in $view sends to the bulbs or ends a preview. A drag only moves the time: set \`previewing\` for the badge, and let the drop's save take the bulb to the new day at the usual fade."
        exit 1
    fi
    if printf '%s\n' "$body" | grep -nE '\$0\.(on|brightness|xy|x|y) *=' >&2; then
        echo "✗ drag-moves-time: $f in $view changes the keyframe's look. A drag keeps its colour, brightness and on or off, and writes only \`minute\` and \`anchor\`."
        exit 1
    fi
done
if ! body_of addKey | grep -q 'LightDay.state(bulb.keys, at:'; then
    echo "✗ drag-moves-time: addKey in $view no longer samples the band. A new keyframe takes the colour between its neighbours, so adding one doesn't change the day."
    exit 1
fi
echo "✓ drag-moves-time: dragging a keyframe changes only its time and sends nothing to the bulbs; a new keyframe takes the colour in between"
