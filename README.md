# Lost Window

macOS occasionally pulls this stupid trick where the app is clearly running, Mission Control can still see the window thumbnail, and clicking the app does absolutely nothing useful because the real window is stranded off-screen or stuck in some weird window-state limbo.

This repo exists because that got old fast.

The fix here is intentionally boring:

- ask macOS for a regular running app
- grab its focused or main window through the accessibility API
- unminimize it if needed
- drop fullscreen if needed
- raise it
- shove it back to a sane visible position

That is it. No pretending the window manager is behaving. No restarting random apps until the problem disappears.

Built because I kept losing app windows and got tired of the whole "the app is open, technically" routine. Thanks to Codex for helping wire it up.

## What You Get

- `./bin/lost-window choose`
  Opens a picker for regular running apps, then forces the selected app's window back onscreen.
- `./bin/lost-window frontmost`
  Fixes the current frontmost app without asking questions.
- `./bin/lost-window fix "SimpMusic"`
  Targets one app directly by name.
- `raycast/`
  Raycast Script Command wrappers.
- `shortcuts/`
  Thin shell entrypoints you can call from the macOS Shortcuts app.

## Requirements

- macOS
- Xcode Command Line Tools or Xcode, because the core command runs through `swift`
- Accessibility permission for whichever app launches the command:
  - Terminal
  - Raycast
  - Shortcuts

If you skip Accessibility permission, the script will fail loudly instead of pretending it worked.

## CLI Usage

Run it directly from the repo:

```bash
./bin/lost-window choose
./bin/lost-window frontmost
./bin/lost-window fix "SimpMusic"
```

The command is a thin shell wrapper around [`bin/lost-window.swift`](bin/lost-window.swift), which does the actual macOS window recovery work.

## Raycast Setup

This repo uses Raycast Script Commands, not a custom extension. That keeps setup dead simple and is enough for this job.

Setup:

1. Open Raycast Preferences.
2. Go to `Extensions`.
3. Hit the `+` button.
4. Choose `Add Script Directory`.
5. Point it at this repo's [`raycast`](raycast) directory.
6. Run either:
   - `Force Show Lost Window`
   - `Force Show Frontmost Window`

The picker command is the one you probably want day to day.

Relevant docs:

- Raycast Script Commands repo: https://github.com/raycast/script-commands
- Raycast FAQ on script commands vs extensions: https://developers.raycast.com/misc/faq

## Shortcuts Setup

If you want the same thing behind a native macOS keyboard shortcut:

1. Open the `Shortcuts` app.
2. Create a new shortcut.
3. Add `Run Shell Script`.
4. Use `/bin/zsh` as the shell.
5. Call one of these repo scripts:

```bash
/absolute/path/to/repo/shortcuts/force-show-lost-window.sh
/absolute/path/to/repo/shortcuts/force-show-frontmost-window.sh
```

6. Open the shortcut details and assign a keyboard shortcut.

That gives you a clean native macOS shortcut without copying logic into Shortcuts itself.

## Why There Is No Dock Menu Hack

The obvious dream feature is this:

- right-click the app in the Dock
- next to `Show All Windows`, see `Force Window to Show`
- click it and move on with your life

That is not a sane supported extension point on macOS. You can absolutely go down the hack route, but it is brittle, invasive, and not something I’d put in a repo and tell another developer to trust.

So this repo ships the maintainable version:

- one real recovery command
- one Raycast flow
- one Shortcuts flow

## Notes

- Some apps expose weird or non-standard windows. When that happens, the script tries the focused window first, then the main window, then the first accessibility window it can find.
- If an app truly has no recoverable standard window open, the command fails instead of guessing.
- The default recovery position is near the top-left of the current main screen. The goal is reliability, not fancy placement heuristics.
