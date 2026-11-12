#!/bin/bash
# Kompletně odebere nsfix ze systému.
set -uo pipefail

LABEL="com.user.nightshift-fix"

echo "→ Zastavuji LaunchAgent…"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

echo "→ Mažu soubory…"
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/.local/nightshift-fix"

echo "✓ nsfix byl odinstalován. Night Shift funguje dál normálně (jen bez opravy)."
