#!/bin/zsh

set -euo pipefail

APP_NAME="${1:-SimpMusic}"
APP_BUNDLE_ID="${2:-com.maxrave.simpmusic}"
DURATION="${LOST_WINDOW_PROOF_DURATION:-30}"
SCREEN_DEVICE="${LOST_WINDOW_PROOF_SCREEN_DEVICE:-5}"
OUTPUT_ROOT="${LOST_WINDOW_PROOF_ROOT:-$HOME/Desktop/SimpMusic Bug Proofs}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$OUTPUT_ROOT/$STAMP"
STATE_LOG="$OUT_DIR/state.log"
SUMMARY_FILE="$OUT_DIR/summary.txt"
SCREENSHOT_FILE="$OUT_DIR/final.png"
VIDEO_FILE="$OUT_DIR/screen.mp4"
FFMPEG_LOG="$OUT_DIR/ffmpeg.log"

mkdir -p "$OUT_DIR"

show_dialog() {
  osascript - "$1" <<'APPLESCRIPT'
on run argv
  display dialog (item 1 of argv) buttons {"OK"} default button "OK" with title "Lost Window Proof"
end run
APPLESCRIPT
}

notify() {
  osascript - "$1" <<'APPLESCRIPT'
on run argv
  display notification (item 1 of argv) with title "Lost Window Proof"
end run
APPLESCRIPT
}

screen_size() {
  swift -e 'import AppKit
if let frame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame {
  print("\(Int(frame.width))x\(Int(frame.height))")
} else {
  print("1512x982")
}'
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

print(
  "\(timestamp)\tfrontmost=\(frontmostApp)\tpid=\(app.processIdentifier)\tax_windows_err=\(windowsErr.rawValue)\tax_windows_count=\(windows?.count ?? -1)\tmain_err=\(mainErr.rawValue)\tmain_present=\(mainValue != nil)\tfocused_err=\(focusedErr.rawValue)\tfocused_present=\(focusedValue != nil)\tfront_err=\(frontErr.rawValue)\tfront=\(boolString(frontValue))\thidden_err=\(hiddenErr.rawValue)\thidden=\(boolString(hiddenValue))\tcg_windows=\(cgWindows.joined(separator: " | "))"
)
SWIFT
}

write_summary() {
  local zero_count
  local missing_main_count
  local suspicious_lines

  zero_count="$(rg -c 'ax_windows_count=0' "$STATE_LOG" || true)"
  missing_main_count="$(rg -c 'main_present=false' "$STATE_LOG" || true)"
  suspicious_lines="$(rg 'ax_windows_count=0|main_present=false|focused_present=false' "$STATE_LOG" | tail -20 || true)"

  {
    echo "Lost Window Proof Summary"
    echo
    echo "App: $APP_NAME"
    echo "Duration: ${DURATION}s"
    echo "Output directory: $OUT_DIR"
    echo
    echo "Suspicious samples:"
    echo "- ax_windows_count=0 samples: ${zero_count:-0}"
    echo "- main_present=false samples: ${missing_main_count:-0}"
    echo
    echo "Last suspicious lines:"
    if [[ -n "$suspicious_lines" ]]; then
      echo "$suspicious_lines"
    else
      echo "None captured."
    fi
    echo
    echo "Artifacts:"
    echo "- $STATE_LOG"
    if [[ -f "$VIDEO_FILE" ]]; then
      echo "- $VIDEO_FILE"
    fi
    if [[ -f "$SCREENSHOT_FILE" ]]; then
      echo "- $SCREENSHOT_FILE"
    fi
  } > "$SUMMARY_FILE"
}

RECORDING=0
VIDEO_PID=""
SCREEN_SIZE="$(screen_size)"

if command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -loglevel error -nostdin -y \
    -f avfoundation \
    -framerate 20 \
    -pixel_format uyvy422 \
    -video_size "$SCREEN_SIZE" \
    -i "${SCREEN_DEVICE}:none" \
    -t "$DURATION" \
    "$VIDEO_FILE" >"$FFMPEG_LOG" 2>&1 &
  VIDEO_PID="$!"
  sleep 1
  if kill -0 "$VIDEO_PID" >/dev/null 2>&1; then
    RECORDING=1
  fi
fi

osascript <<APPLESCRIPT
display dialog "Proof capture is starting for $APP_NAME.\n\nFor the next $DURATION seconds:\n1. Click the app in the Dock.\n2. Try Show All Windows / Mission Control.\n3. Try the exact broken flow manually.\n\nThis recorder will capture system state without forcing the bug." buttons {"Start"} default button "Start" with title "Lost Window Proof"
APPLESCRIPT

notify "Proof capture started for $APP_NAME."

SECONDS_LEFT="$DURATION"
while (( SECONDS_LEFT > 0 )); do
  capture_state >> "$STATE_LOG"
  sleep 1
  SECONDS_LEFT=$((SECONDS_LEFT - 1))
done

if [[ "$RECORDING" == "1" && -n "$VIDEO_PID" ]]; then
  wait "$VIDEO_PID" || true
fi

screencapture -x "$SCREENSHOT_FILE" >/dev/null 2>&1 || true
write_summary

open "$OUT_DIR"
show_dialog "Proof capture finished.\n\nArtifacts were saved to:\n$OUT_DIR"
