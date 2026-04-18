#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Force Show Lost Window
# @raycast.mode silent
# @raycast.packageName Lost Window

# Optional parameters:
# @raycast.icon 🪟
# @raycast.description Pick a running app and yank its main window back onscreen.
# @raycast.author hico

REPO_ROOT="${0:A:h:h}"
exec "$REPO_ROOT/bin/lost-window" choose
