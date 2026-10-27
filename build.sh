#!/bin/bash
# Build Sundial.app, install to /Applications, and relaunch.
#
# Usage:
#   ./build.sh                 # build, install to /Applications, relaunch (default)
#                              # (set INSTALL_DIR in build.local.env to install elsewhere)
#   ./build.sh --no-install    # build only, stage into ./build/Sundial.app
#   ./build.sh -n              # short form of --no-install
#   ./build.sh check           # run the laws in tests/ (no build)
#   ./build.sh check --drives  # the laws, then every drive in tests/drive/
#   ./build.sh drive [name]    # run every feature check in tests/drive/, or one
#   ./build.sh -v              # verbose xcodebuild output
#   ./build.sh -n -v           # both

set -e

# The pre-commit hook stamps the docs a commit changes (dev/hooks/stamp-docs.mjs).
git -C "$(dirname "$0")" rev-parse --git-dir >/dev/null 2>&1 && git -C "$(dirname "$0")" config core.hooksPath dev/hooks || true

APP_NAME=Sundial
INSTALL=1
VERBOSE=0
MODE=build   # build | check | drive
DRIVE_NAME=""
DRIVES=0   # check runs the drives only with --drives

for arg in "$@"; do
    # The word after `drive` is the feature to drive, not a flag.
    if [ "$MODE" = "drive" ] && [ -z "$DRIVE_NAME" ] && [ "${arg#-}" = "$arg" ]; then
        DRIVE_NAME="$arg"
        continue
    fi
    case "$arg" in
        check)           MODE=check ;;
        drive)           MODE=drive ;;
        --drives)        DRIVES=1 ;;
        -n|--no-install) INSTALL=0 ;;
        -v|--verbose)    VERBOSE=1 ;;
        -h|--help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown flag '$arg'. Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

cd "$(dirname "$0")"

# Every feature check in tests/drive/, or the one named. A name with no script is an
# error, so a typo can't pass by running nothing.
drive() {
    local name="$1" failed=0 ran=0
    if [ -n "$name" ]; then
        if [ ! -f "tests/drive/$name.sh" ]; then
            echo "error: no drive named \"$name\": there's no tests/drive/$name.sh. Fix the name, or write that check."
            local there
            there=$(ls tests/drive 2>/dev/null | sed -n 's/\.sh$//p' | tr '\n' ' ' || true)
            echo "       The ones there: ${there:-none yet}"
            return 1
        fi
        "tests/drive/$name.sh"
        return $?
    fi
    for d in tests/drive/*.sh; do
        [ -f "$d" ] || continue
        ran=1
        "$d" || failed=1
    done
    [ "$ran" = 1 ] || echo "No drives yet: tests/drive/ has no checks. dev/features/README.md lists what isn't covered."
    return $failed
}

if [ "$MODE" = "drive" ]; then
    drive "$DRIVE_NAME" && exit 0
    exit 1
fi

if [ "$MODE" = "check" ]; then
    failed=0
    for law in tests/*.sh; do
        "$law" || failed=1
    done
    if [ "$DRIVES" = 1 ]; then
        drive "" || failed=1
    else
        echo "The drives didn't run: ./build.sh check --drives runs them."
    fi
    exit $failed
fi

# Where to install. build.local.env (gitignored) can set INSTALL_DIR; see
# build.local.env.example.
INSTALL_DIR=/Applications
if [ -f build.local.env ]; then
    # shellcheck disable=SC1091
    . ./build.local.env
fi
if [ "$INSTALL" = "1" ] && [ ! -d "$INSTALL_DIR" ]; then
    echo "error: install folder '$INSTALL_DIR' doesn't exist. Create it with 'mkdir -p \"$INSTALL_DIR\"' or fix INSTALL_DIR in build.local.env."
    exit 1
fi

# 1. Regenerate project from project.yml
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen not installed. Install with: brew install xcodegen"
    exit 1
fi
echo "→ xcodegen generate"
xcodegen generate --quiet

# 2. Build
DERIVED_DATA=$(mktemp -d)
trap 'rm -rf "$DERIVED_DATA"' EXIT

echo "→ xcodebuild ($APP_NAME, Release)"
XCB_ARGS=(
    -project "$APP_NAME.xcodeproj"
    -scheme "$APP_NAME"
    -configuration Release
    -destination 'generic/platform=macOS'
    -derivedDataPath "$DERIVED_DATA"
    -allowProvisioningUpdates
)
if [ "$VERBOSE" = "1" ]; then
    xcodebuild "${XCB_ARGS[@]}"
else
    # xcbeautify if available, else grep for the interesting lines
    if command -v xcbeautify >/dev/null 2>&1; then
        set -o pipefail
        xcodebuild "${XCB_ARGS[@]}" | xcbeautify
    else
        set -o pipefail
        xcodebuild "${XCB_ARGS[@]}" 2>&1 \
            | grep -E "(error|warning): |\*\* BUILD (SUCCEEDED|FAILED) \*\*" \
            || true
    fi
fi

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "error: .app not found at $APP_PATH. Re-run with -v to see full xcodebuild output."
    exit 1
fi

# 3. Stage into ./build
OUT_DIR="build"
mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/$APP_NAME.app"
cp -R "$APP_PATH" "$OUT_DIR/"
echo "✓ Built: $OUT_DIR/$APP_NAME.app"

# 4. Optional install + relaunch
if [ "$INSTALL" = "1" ]; then
    echo "→ Stopping any running $APP_NAME..."

    # Ask nicely first (lets the app run deinit / save state)
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true

    # Wait up to 5s for graceful exit. pgrep -f matches the full path since
    # the running argv[0] is /Applications/Sundial.app/Contents/MacOS/Sundial.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if ! pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null; then
            break
        fi
        sleep 0.5
    done

    # Force-kill any stragglers (covers Debug builds from DerivedData too,
    # not just /Applications/ — pattern matches any Sundial.app path)
    if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null; then
        echo "  (forcing quit — app did not respond to AppleScript)"
        pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
        sleep 0.5
    fi

    # Last resort: SIGKILL. Rare, but a zombied Debug build from Xcode can
    # ignore SIGTERM if its code-sign state is weird.
    if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null; then
        pkill -9 -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
        sleep 0.3
    fi

    # Confirm before copying — catching this early beats "Resource busy" mid-copy
    if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null; then
        # Check for the classic cause: a Debug build from DerivedData that's
        # still attached to Xcode's debugger. Those are unkillable from the
        # shell — only Xcode can release them.
        if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" | xargs -I{} ps -p {} -o stat= 2>/dev/null | grep -q X; then
            echo "error: $APP_NAME is being held by Xcode's debugger (status 'X'). Switch to Xcode and hit Product → Stop (⌘.) or quit Xcode, then re-run ./build.sh."
        else
            echo "error: $APP_NAME survived SIGTERM + SIGKILL. Run 'pgrep -fl Sundial' to inspect, then kill manually."
        fi
        exit 1
    fi

    echo "→ Installing to $INSTALL_DIR/$APP_NAME.app"
    rm -rf "${INSTALL_DIR:?}/$APP_NAME.app"
    cp -R "$OUT_DIR/$APP_NAME.app" "$INSTALL_DIR/"

    echo "→ Launching..."
    open "$INSTALL_DIR/$APP_NAME.app"
    echo "✓ $APP_NAME running. Check the menu bar."
fi
