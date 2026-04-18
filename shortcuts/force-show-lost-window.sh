#!/bin/zsh

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
exec "$REPO_ROOT/bin/lost-window" choose
