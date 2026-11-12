#!/bin/bash
# Nainstaluje nsfix: zkompiluje helper a zaregistruje LaunchAgent.
set -euo pipefail

LABEL="com.user.nightshift-fix"
DEST="$HOME/.local/nightshift-fix"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC="$(cd "$(dirname "$0")" && pwd)/src/nsfix.m"

if ! command -v clang >/dev/null; then
  echo "Chybí clang. Nainstaluj Command Line Tools: xcode-select --install" >&2
  exit 1
fi

echo "→ Kompiluji helper…"
mkdir -p "$DEST"
cp "$SRC" "$DEST/nsfix.m"
clang -fobjc-arc -O2 -framework Foundation -framework AppKit -framework CoreGraphics \
  "$DEST/nsfix.m" -o "$DEST/nsfix"

echo "→ Zapisuji LaunchAgent…"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEST/nsfix</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
EOF

echo "→ Spouštím…"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✓ Hotovo. nsfix běží a spustí se automaticky po každém přihlášení."
