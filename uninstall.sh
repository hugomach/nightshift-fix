#!/bin/bash
# Completely removes nsfix from the system.
set -uo pipefail

LABEL="com.user.nightshift-fix"

echo "→ Stopping LaunchAgent…"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

echo "→ Removing files…"
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/.local/nightshift-fix"
rm -f "$HOME/Library/Logs/nsfix.log"

echo "✓ nsfix has been uninstalled. Night Shift keeps working as usual (just without the fix)."
