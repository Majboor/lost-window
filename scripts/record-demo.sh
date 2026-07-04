#!/bin/zsh

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
TARGET_APP="${1:-SimpMusic}"
OUTPUT_DIR="${2:-$REPO_ROOT/assets}"
VIDEO_PATH="$OUTPUT_DIR/lost-window-demo.mp4"
PALETTE_PATH="$OUTPUT_DIR/lost-window-demo-palette.png"
GIF_PATH="$OUTPUT_DIR/lost-window-demo.gif"
SCREEN_SIZE="${LOST_WINDOW_DEMO_SCREEN_SIZE:-1512x982}"
PRE_PICKER_DELAY="${LOST_WINDOW_DEMO_PRE_PICKER_DELAY:-8}"
POST_PICKER_DELAY="${LOST_WINDOW_DEMO_POST_PICKER_DELAY:-8}"
TOTAL_DURATION=$(( PRE_PICKER_DELAY + POST_PICKER_DELAY ))

mkdir -p "$OUTPUT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 "This demo recorder only supports macOS."
  exit 1
fi

for cmd in ffmpeg osascript swift; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    print -u2 "Missing required command: $cmd"
    exit 1
  fi
done

"$REPO_ROOT/bin/lost-window" install-apps >/dev/null

show_desktop() {
  osascript <<'APPLESCRIPT'
tell application "Finder" to activate
tell application "System Events"
  keystroke "h" using {command down, option down}
end tell
APPLESCRIPT
}

move_offscreen() {
  local target="$1"
  TARGET_APP_NAME="$target" swift -e '
import AppKit
import ApplicationServices
import Foundation

let targetName = ProcessInfo.processInfo.environment["TARGET_APP_NAME"] ?? ""

guard let app = NSWorkspace.shared.runningApplications.first(where: {
  $0.activationPolicy == .regular &&
  ($0.localizedName ?? "").caseInsensitiveCompare(targetName) == .orderedSame
}) else {
  fputs("Could not find app named \(targetName)\n", stderr)
  exit(1)
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)
var focused: CFTypeRef?
AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
if focused == nil {
  var main: CFTypeRef?
  AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &main)
  focused = main
}

guard let window = focused else {
  fputs("Could not find a recoverable window for \(targetName)\n", stderr)
  exit(1)
}

var point = CGPoint(x: -9285, y: 60)
let value = AXValueCreate(.cgPoint, &point)!
_ = AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, value)
' >/dev/null
}

osascript <<APPLESCRIPT
display dialog "Lost Window demo is about to start for $TARGET_APP.\n\nWhen recording begins:\n1. Click $TARGET_APP in the Dock.\n2. Open Show All Windows and try opening it.\n3. Wait a few seconds and I will pop the Lost Window picker automatically.\n4. Select $TARGET_APP in the picker.\n\nClick Start when you are ready." buttons {"Cancel", "Start"} default button "Start" with title "Lost Window Demo"
APPLESCRIPT

"$REPO_ROOT/bin/lost-window" fix "$TARGET_APP" >/dev/null 2>&1 || true
show_desktop
osascript -e "tell application \"$TARGET_APP\" to activate"
sleep 0.5
move_offscreen "$TARGET_APP"

ffmpeg -y \
  -f avfoundation \
  -framerate 20 \
  -video_size "$SCREEN_SIZE" \
  -i "5:none" \
  -t "$TOTAL_DURATION" \
  "$VIDEO_PATH" >/tmp/lost-window-demo-ffmpeg.log 2>&1 &
RECORDER_PID=$!

sleep 1
osascript -e "display notification \"Recording started for $TARGET_APP demo.\" with title \"Lost Window\""

sleep "$PRE_PICKER_DELAY"
"$REPO_ROOT/bin/lost-window" choose
sleep "$POST_PICKER_DELAY"

wait "$RECORDER_PID"

ffmpeg -y -i "$VIDEO_PATH" -vf "fps=12,scale=1200:-1:flags=lanczos,palettegen" "$PALETTE_PATH" >/dev/null 2>&1
ffmpeg -y -i "$VIDEO_PATH" -i "$PALETTE_PATH" -lavfi "fps=12,scale=1200:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5" "$GIF_PATH" >/dev/null 2>&1
rm -f "$PALETTE_PATH"

osascript <<APPLESCRIPT
display dialog "Demo capture finished.\n\nGIF: $GIF_PATH\nVideo: $VIDEO_PATH" buttons {"OK"} default button "OK" with title "Lost Window Demo"
APPLESCRIPT
