#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Force Show Frontmost Window
# @raycast.mode silent
# @raycast.packageName Lost Window

# Optional parameters:
# @raycast.icon 🎯
# @raycast.description Force the frontmost app window back to a sane visible position.
# @raycast.author hico

REPO_ROOT="${0:A:h:h}"
exec "$REPO_ROOT/bin/lost-window" frontmost
