#!/bin/zsh

set -euo pipefail

REPO="${LOST_WINDOW_REPO:-Majboor/lost-window}"
REF="${LOST_WINDOW_REF:-main}"
SOURCE_DIR="${LOST_WINDOW_SOURCE_DIR:-}"
INSTALL_DIR="${LOST_WINDOW_INSTALL_DIR:-$HOME/.local/share/lost-window}"
BIN_DIR="${LOST_WINDOW_BIN_DIR:-$HOME/.local/bin}"
WITH_APPS=0

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [--with-apps] [--install-dir PATH] [--bin-dir PATH]

Environment overrides:
  LOST_WINDOW_REPO
  LOST_WINDOW_REF
  LOST_WINDOW_SOURCE_DIR
  LOST_WINDOW_INSTALL_DIR
  LOST_WINDOW_BIN_DIR
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --with-apps)
      WITH_APPS=1
      shift
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --bin-dir)
      BIN_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 "Unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 "Lost Window only supports macOS."
  exit 1
fi

for cmd in curl tar mktemp swift; do
  if [[ -z "$SOURCE_DIR" ]] && [[ "$cmd" == "curl" || "$cmd" == "tar" ]] && ! command -v "$cmd" >/dev/null 2>&1; then
    print -u2 "Missing required command: $cmd"
    exit 1
  fi

  if [[ "$cmd" == "mktemp" || "$cmd" == "swift" ]] && ! command -v "$cmd" >/dev/null 2>&1; then
    print -u2 "Missing required command: $cmd"
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "$SOURCE_DIR" ]]; then
  SRC_DIR="${SOURCE_DIR:A}"
else
  ARCHIVE_URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${REF}"
  ARCHIVE_PATH="$TMP_DIR/lost-window.tar.gz"

  curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
  tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"
  SRC_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'lost-window-*' | head -n 1)"
fi

if [[ -z "$SRC_DIR" || ! -d "$SRC_DIR" ]]; then
  print -u2 "Could not unpack the Lost Window archive."
  exit 1
fi

for required_path in \
  "$SRC_DIR/bin/lost-window" \
  "$SRC_DIR/bin/lost-window.swift" \
  "$SRC_DIR/bin/lost-window-install-apps" \
  "$SRC_DIR/raycast/force-show-lost-window.sh" \
  "$SRC_DIR/raycast/force-show-frontmost-window.sh" \
  "$SRC_DIR/shortcuts/force-show-lost-window.sh" \
  "$SRC_DIR/shortcuts/force-show-frontmost-window.sh"; do
  if [[ ! -e "$required_path" ]]; then
    print -u2 "Install source is missing required file: $required_path"
    exit 1
  fi
done

mkdir -p "$BIN_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -R "$SRC_DIR"/. "$INSTALL_DIR"/

chmod +x \
  "$INSTALL_DIR/bin/lost-window" \
  "$INSTALL_DIR/bin/lost-window-install-apps" \
  "$INSTALL_DIR/raycast/force-show-lost-window.sh" \
  "$INSTALL_DIR/raycast/force-show-frontmost-window.sh" \
  "$INSTALL_DIR/shortcuts/force-show-lost-window.sh" \
  "$INSTALL_DIR/shortcuts/force-show-frontmost-window.sh"

ln -sfn "$INSTALL_DIR/bin/lost-window" "$BIN_DIR/lost-window"

if (( WITH_APPS == 1 )); then
  "$BIN_DIR/lost-window" install-apps
fi

cat <<EOF
Installed Lost Window into:
- $INSTALL_DIR

CLI entrypoint:
- $BIN_DIR/lost-window

Try it:
- lost-window choose
- lost-window frontmost
- lost-window fix "SimpMusic"
EOF

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  cat <<EOF

$BIN_DIR is not currently on your PATH.
Add this to ~/.zshrc if you want the command globally available:

  export PATH="$BIN_DIR:\$PATH"
EOF
fi

if (( WITH_APPS == 0 )); then
  cat <<'EOF'

Want Dock/Shortcuts launcher apps too?
Run:

  lost-window install-apps
EOF
fi
