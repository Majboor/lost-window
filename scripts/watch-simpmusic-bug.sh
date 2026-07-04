#!/bin/zsh

set -euo pipefail

APP_NAME="${1:-SimpMusic}"
APP_BUNDLE_ID="${2:-com.maxrave.simpmusic}"
POLL_INTERVAL="${LOST_WINDOW_WATCH_INTERVAL:-1}"
OUTPUT_ROOT="${LOST_WINDOW_WATCH_ROOT:-$HOME/Desktop/SimpMusic Bug Proofs}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$OUTPUT_ROOT/watch-$STAMP"
STATE_LOG="$OUT_DIR/state.log"
SUMMARY_FILE="$OUT_DIR/summary.txt"
SCREENSHOT_FILE="$OUT_DIR/final.png"

mkdir -p "$OUT_DIR"

notify() {
  osascript - "$1" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title "Lost Window Watch"
end run
APPLESCRIPT
}

show_dialog() {
  osascript - "$1" <<'APPLESCRIPT'
on run argv
  display dialog (item 1 of argv) buttons {"OK"} default button "OK" with title "Lost Window Watch"
end run
APPLESCRIPT
}

capture_state() {
  TARGET_APP_NAME="$APP_NAME" TARGET_BUNDLE_ID="$APP_BUNDLE_ID" swift - <<'SWIFT'
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let env = ProcessInfo.processInfo.environment
let targetName = env["TARGET_APP_NAME"] ?? "SimpMusic"
let targetBundle = env["TARGET_BUNDLE_ID"] ?? "com.maxrave.simpmusic"

let timestamp = ISO8601DateFormatter().string(from: Date())
let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "<none>"

func boolString(_ value: CFTypeRef?) -> String {
  if let number = value as? NSNumber {
    return number.boolValue ? "true" : "false"
  }
  return "nil"
}

func attr(_ element: AXUIElement, _ key: String) -> (AXError, CFTypeRef?) {
  var value: CFTypeRef?
  let err = AXUIElementCopyAttributeValue(element, key as CFString, &value)
  return (err, value)
}

guard let app = NSWorkspace.shared.runningApplications.first(where: {
  ($0.bundleIdentifier == targetBundle) || (($0.localizedName ?? "").caseInsensitiveCompare(targetName) == .orderedSame)
}) else {
  print("\(timestamp)\tfrontmost=\(frontmostApp)\tnot_running")
  exit(0)
}

let appElement = AXUIElementCreateApplication(app.processIdentifier)
let (windowsErr, windowsValue) = attr(appElement, kAXWindowsAttribute)
let windows = windowsValue as? [Any]
let (mainErr, mainValue) = attr(appElement, kAXMainWindowAttribute)
let (focusedErr, focusedValue) = attr(appElement, kAXFocusedWindowAttribute)
let (frontErr, frontValue) = attr(appElement, kAXFrontmostAttribute)
let (hiddenErr, hiddenValue) = attr(appElement, kAXHiddenAttribute)

var cgWindows: [String] = []
let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for window in info {
  guard let owner = window[kCGWindowOwnerName as String] as? String, owner == targetName else { continue }
  let num = window[kCGWindowNumber as String] as? Int ?? -1
  let onscreen = window[kCGWindowIsOnscreen as String] as? Int ?? -1
  let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let x = bounds["X"] ?? "?"
  let y = bounds["Y"] ?? "?"
  let w = bounds["Width"] ?? "?"
  let h = bounds["Height"] ?? "?"
  cgWindows.append("id=\(num),onscreen=\(onscreen),x=\(x),y=\(y),w=\(w),h=\(h)")
}

let zeroWindows = (windowsErr == .success && (windows?.count ?? -1) == 0)
let noMain = (mainValue == nil)
let noFocused = (focusedValue == nil)

print(
  "\(timestamp)\tfrontmost=\(frontmostApp)\tpid=\(app.processIdentifier)\tax_windows_err=\(windowsErr.rawValue)\tax_windows_count=\(windows?.count ?? -1)\tmain_err=\(mainErr.rawValue)\tmain_present=\(mainValue != nil)\tfocused_err=\(focusedErr.rawValue)\tfocused_present=\(focusedValue != nil)\tfront_err=\(frontErr.rawValue)\tfront=\(boolString(frontValue))\thidden_err=\(hiddenErr.rawValue)\thidden=\(boolString(hiddenValue))\tzero_windows=\(zeroWindows)\tno_main=\(noMain)\tno_focused=\(noFocused)\tcg_windows=\(cgWindows.joined(separator: " | "))"
)

if zeroWindows || (noMain && noFocused) {
  exit(42)
}
SWIFT
}

{
  echo "Watching $APP_NAME for the real zero-window bug."
  echo "Output directory: $OUT_DIR"
  echo "Poll interval: ${POLL_INTERVAL}s"
} > "$SUMMARY_FILE"

notify "Watching $APP_NAME for the real bug."

while true; do
  if capture_state >> "$STATE_LOG"; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  screencapture -x "$SCREENSHOT_FILE" >/dev/null 2>&1 || true
  {
    echo
    echo "Detected suspicious state at $(date)."
    echo "Artifacts:"
    echo "- $STATE_LOG"
    echo "- $SCREENSHOT_FILE"
  } >> "$SUMMARY_FILE"
  open "$OUT_DIR"
  notify "Detected a real $APP_NAME zero-window state."
  show_dialog "Detected the real $APP_NAME bug.\n\nArtifacts were saved to:\n$OUT_DIR"
  exit 0
done
