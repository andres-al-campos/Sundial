#!/bin/bash
# Law: dragging a keyframe changes its time and sends nothing to the bulbs.
#
# "dragging just means change the time not the colors". The held-lamp drive covers the controller's
# half but makes the window's calls itself, and SwiftUI's gestures take no clicks off-screen, so
# this reads what the drag's two functions call.

cd "$(dirname "$0")/.."
view=src/views/LightsView.swift

for f in moveKey dropKey; do
    body=$(awk -v f="private func $f" 'index($0, f){on=1} on{print} on && /^    }$/{on=0}' "$view")
    if [ -z "$body" ]; then
        echo "✗ drag-moves-time: can't find $f in $view. If it was renamed, update tests/drag-moves-time.sh."
        exit 1
    fi
    if printf '%s\n' "$body" | grep -nE 'previewOn\(|onPreviewLamps|endPreviewNow|onEndLampPreview' >&2; then
        echo "✗ drag-moves-time: $f in $view sends to the bulbs or ends a preview. A drag only moves the time: set \`previewing\` for the badge, and let the drop's save take the bulb to the new day at the usual fade."
        exit 1
    fi
done
echo "✓ drag-moves-time: dragging a keyframe sends nothing to the bulbs"
