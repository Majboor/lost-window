# Lost Window for macOS: App Is Open but No Window Shows

If you searched for any of this, you are in the right repo:

- macOS app is open but no window shows
- app is running but not visible on Mac
- Show All Windows can see the app but clicking it does nothing
- Mission Control shows the window thumbnail but the app will not open
- app window is off-screen on macOS
- app disappeared from the desktop but is still running

macOS occasionally pulls this stupid trick where the app is clearly running, Mission Control or `Show All Windows` can still see the window thumbnail, and clicking the app does absolutely nothing useful because the real window is stranded off-screen or stuck in some weird window-state limbo.

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

## Common Symptoms

This tool is specifically for cases like:

- the app icon shows as open in the Dock, but no usable window appears
- `Show All Windows` can see the window, but selecting it does not bring it back
- Mission Control shows the window preview, but the app still feels lost
- the app window got moved to a bad off-screen position
- switching back to the app does nothing even though the process is alive

## What You Get

- `./bin/lost-window choose`
  Opens a picker for regular running apps, then forces the selected app's window back onscreen.
- `./bin/lost-window frontmost`
  Fixes the current frontmost app without asking questions.
- `./bin/lost-window fix "SimpMusic"`
  Targets one app directly by name.
- `./bin/lost-window install-apps`
  Builds native launcher apps you can pin to the Dock or trigger from the Shortcuts app.
- `raycast/`
  Raycast Script Command wrappers.
- `shortcuts/`
  Thin shell entrypoints you can call from the macOS Shortcuts app.
- `install.sh`
  Curl-friendly installer for a fast local setup.
- `Formula/lost-window.rb`
  Homebrew formula for installing the CLI from this repo.

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
./bin/lost-window install-apps
```

The command is a thin shell wrapper around [`bin/lost-window.swift`](bin/lost-window.swift), which does the actual macOS window recovery work.

## Install Options

### Curl Installer

Fastest path:

```bash
curl -fsSL https://raw.githubusercontent.com/Majboor/lost-window/main/install.sh | zsh
```

If you also want native launcher apps for the Dock and Shortcuts:

```bash
curl -fsSL https://raw.githubusercontent.com/Majboor/lost-window/main/install.sh | zsh -s -- --with-apps
```

That installs the repo into `~/.local/share/lost-window` and symlinks `lost-window` into `~/.local/bin`.

### Homebrew

Homebrew wants a real tap, so the install path is:

```bash
brew tap Majboor/lost-window
brew install --HEAD Majboor/lost-window/lost-window
```

After install, the same CLI is available:

```bash
lost-window choose
lost-window frontmost
lost-window install-apps
```

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

If you want the same thing behind a native macOS keyboard shortcut, you now have two decent paths.

### Easy Native Path

Install the launcher apps:

```bash
lost-window install-apps
```

That creates:

- `~/Applications/Lost Window/Force Show Lost Window.app`
- `~/Applications/Lost Window/Force Show Frontmost Window.app`

From there:

1. Open the `Shortcuts` app.
2. Create a new shortcut.
3. Add `Open App`.
4. Pick one of the generated Lost Window apps.
5. Assign a keyboard shortcut.

That is the cleanest Shortcuts flow, and it also gives you something you can pin to the Dock.

### Shell Script Path

If you prefer to keep it script-driven:

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

Note:

- If you trigger the generated launcher apps directly, add those apps to Accessibility.
- If you use `Run Shell Script` from Shortcuts, add Shortcuts itself to Accessibility.

## Dock Usage

You still cannot inject a custom item into another app's Dock menu in a sane supported way, so there is still no native `Force Window to Show` item beside `Show All Windows`.

What you can do now:

1. Run `lost-window install-apps`
2. Pin `Force Show Lost Window.app` to the Dock

That gets you one-click Dock access without messing with unsupported Dock hacks.

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
- one installable Dock launcher path
- one brew install path
- one curl quick-install path

## Notes

- Some apps expose weird or non-standard windows. When that happens, the script tries the focused window first, then the main window, then the first accessibility window it can find.
- If an app truly has no recoverable standard window open, the command fails instead of guessing.
- The default recovery position is near the top-left of the current main screen. The goal is reliability, not fancy placement heuristics.
