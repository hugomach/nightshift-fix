#!/bin/bash
# Installs nsfix: compiles the helper and registers a LaunchAgent.
set -euo pipefail

LABEL="com.user.nightshift-fix"
DEST="$HOME/.local/nightshift-fix"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC="$(cd "$(dirname "$0")" && pwd)/src/nsfix.m"

if ! command -v clang >/dev/null; then
  echo "clang not found. Install Command Line Tools: xcode-select --install" >&2
  exit 1
fi

echo "→ Compiling helper…"
mkdir -p "$DEST"
cp "$SRC" "$DEST/nsfix.m"
clang -fobjc-arc -O2 -framework Foundation -framework AppKit -framework CoreGraphics \
  "$DEST/nsfix.m" -o "$DEST/nsfix"

echo "→ Writing LaunchAgent…"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEST/nsfix</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/nsfix.log</string>
</dict></plist>
EOF

echo "→ Starting…"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✓ Done. nsfix is running and will start automatically at every login."
