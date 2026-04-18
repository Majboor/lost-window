import AppKit
import ApplicationServices
import Foundation

enum LostWindowError: LocalizedError {
  case accessibilityPermissionMissing
  case missingCommand
  case missingAppName
  case noRegularApps
  case frontmostAppUnavailable
  case appNotFound(String)
  case noRecoverableWindow(String)

  var errorDescription: String? {
    switch self {
    case .accessibilityPermissionMissing:
      return "Accessibility access is missing. Enable it for the app running this command in System Settings > Privacy & Security > Accessibility."
    case .missingCommand:
      return "Missing command. Use list, frontmost, or fix."
    case .missingAppName:
      return "Missing app name. Use: fix \"App Name\""
    case .noRegularApps:
      return "No regular running apps found."
    case .frontmostAppUnavailable:
      return "Could not determine the frontmost app."
    case .appNotFound(let name):
      return "Could not find a regular running app named '\(name)'."
    case .noRecoverableWindow(let name):
      return "Couldn't find a recoverable window for \(name). The app may not have a standard window right now."
    }
  }
}

func fail(_ error: Error) -> Never {
  let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

func regularApps() -> [NSRunningApplication] {
  let sortedApps = NSWorkspace.shared.runningApplications
    .filter { app in
      app.activationPolicy == .regular &&
      !app.isTerminated &&
      (app.localizedName?.isEmpty == false)
    }
    .sorted {
      ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending
    }

  var seen = Set<String>()
  var uniqueApps: [NSRunningApplication] = []

  for app in sortedApps {
    let key = (app.bundleIdentifier?.lowercased())
      ?? (app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    if seen.insert(key).inserted {
      uniqueApps.append(app)
    }
  }

  return uniqueApps
}

func frontmostRegularApp() -> NSRunningApplication? {
  guard let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular else {
    return nil
  }
  return app
}

func app(named input: String) -> NSRunningApplication? {
  let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }

  let apps = regularApps()

  if let exact = apps.first(where: { ($0.localizedName ?? "").caseInsensitiveCompare(trimmed) == .orderedSame }) {
    return exact
  }

  return apps.first(where: { ($0.localizedName ?? "").localizedCaseInsensitiveContains(trimmed) })
}

func pause(_ seconds: TimeInterval) {
  RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
}

func copyAttribute<T>(_ element: AXUIElement, attribute: String) -> T? {
  var value: CFTypeRef?
  let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard error == .success else { return nil }
  return value as? T
}

func setBool(_ element: AXUIElement, attribute: String, value: Bool) {
  let ref: CFBoolean = value ? kCFBooleanTrue : kCFBooleanFalse
  _ = AXUIElementSetAttributeValue(element, attribute as CFString, ref)
}

func setPoint(_ element: AXUIElement, attribute: String, point: CGPoint) {
  var mutablePoint = point
  guard let value = AXValueCreate(.cgPoint, &mutablePoint) else { return }
  _ = AXUIElementSetAttributeValue(element, attribute as CFString, value)
}

func perform(_ element: AXUIElement, action: String) {
  _ = AXUIElementPerformAction(element, action as CFString)
}

func appReference(for app: NSRunningApplication) -> String {
  if let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty {
    return "id \"\(bundleIdentifier.replacingOccurrences(of: "\"", with: "\\\""))\""
  }

  let name = (app.localizedName ?? "").replacingOccurrences(of: "\"", with: "\\\"")
  return "\"\(name)\""
}

func reopen(_ app: NSRunningApplication) {
  let script = "tell application \(appReference(for: app)) to reopen"
  NSAppleScript(source: script)?.executeAndReturnError(nil)
}

func targetWindow(for appElement: AXUIElement) -> AXUIElement? {
  if let focused: AXUIElement = copyAttribute(appElement, attribute: kAXFocusedWindowAttribute) {
    return focused
  }

  if let main: AXUIElement = copyAttribute(appElement, attribute: kAXMainWindowAttribute) {
    return main
  }

  if let windows: [AXUIElement] = copyAttribute(appElement, attribute: kAXWindowsAttribute), let first = windows.first {
    return first
  }

  return nil
}

func safeWindowOrigin() -> CGPoint {
  let screen = NSScreen.main ?? NSScreen.screens.first
  let origin = screen?.frame.origin ?? .zero
  return CGPoint(x: origin.x + 60, y: origin.y + 60)
}

func recoverWindow(for app: NSRunningApplication) -> Bool {
  let appElement = AXUIElementCreateApplication(app.processIdentifier)
  guard let window = targetWindow(for: appElement) else { return false }

  setBool(window, attribute: kAXMinimizedAttribute, value: false)
  setBool(window, attribute: "AXFullScreen", value: false)
  setBool(window, attribute: kAXMainAttribute, value: true)
  perform(window, action: kAXRaiseAction)
  setPoint(window, attribute: kAXPositionAttribute, point: safeWindowOrigin())
  perform(window, action: kAXRaiseAction)

  _ = app.activate(options: [.activateAllWindows])
  pause(0.2)
  return true
}

func recover(app: NSRunningApplication) throws -> String {
  let name = app.localizedName ?? "Unknown App"

  _ = app.activate(options: [.activateAllWindows])
  pause(0.2)

  if recoverWindow(for: app) {
    return "Recovered \(name)."
  }

  reopen(app)
  _ = app.activate(options: [.activateAllWindows])
  pause(0.35)

  if recoverWindow(for: app) {
    return "Recovered \(name) after reopening it."
  }

  throw LostWindowError.noRecoverableWindow(name)
}

func usage() {
  let text = """
  Usage:
    swift bin/lost-window.swift list
    swift bin/lost-window.swift frontmost
    swift bin/lost-window.swift fix "App Name"
  """

  print(text)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
  usage()
  fail(LostWindowError.missingCommand)
}

do {
  switch command {
  case "list":
    let apps = regularApps()
    guard !apps.isEmpty else { throw LostWindowError.noRegularApps }
    for app in apps {
      print(app.localizedName ?? "")
    }

  case "frontmost":
    guard AXIsProcessTrusted() else { throw LostWindowError.accessibilityPermissionMissing }
    guard let app = frontmostRegularApp() else { throw LostWindowError.frontmostAppUnavailable }
    print(try recover(app: app))

  case "fix":
    guard AXIsProcessTrusted() else { throw LostWindowError.accessibilityPermissionMissing }
    let rawName = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawName.isEmpty else { throw LostWindowError.missingAppName }
    guard let target = app(named: rawName) else { throw LostWindowError.appNotFound(rawName) }
    print(try recover(app: target))

  default:
    usage()
    throw LostWindowError.missingCommand
  }
} catch {
  fail(error)
}
