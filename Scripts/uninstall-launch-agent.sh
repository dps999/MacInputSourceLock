#!/bin/zsh

set -euo pipefail

AGENT_LABEL="com.macstaticlanguage.agent"
PLIST_PATH="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"

echo "Removed $AGENT_LABEL"
