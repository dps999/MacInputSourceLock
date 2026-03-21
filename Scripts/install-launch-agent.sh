#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:A:h:h}
BUILD_PATH="$ROOT_DIR/.build/release/MacStaticLanguage"
AGENT_LABEL="com.macstaticlanguage.agent"
PLIST_PATH="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
LOG_DIR="$HOME/Library/Logs/MacStaticLanguage"
ENVIRONMENT_BLOCK=""

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$LOG_DIR"

cd "$ROOT_DIR"
swift build -c release

if [[ -n "${MACSTATICLANGUAGE_INPUT_SOURCE_ID:-}" || -n "${MACSTATICLANGUAGE_POLL_INTERVAL:-}" ]]; then
ENVIRONMENT_BLOCK=$(cat <<EOF
    <key>EnvironmentVariables</key>
    <dict>
$(if [[ -n "${MACSTATICLANGUAGE_INPUT_SOURCE_ID:-}" ]]; then printf '        <key>MACSTATICLANGUAGE_INPUT_SOURCE_ID</key>\n        <string>%s</string>\n' "$MACSTATICLANGUAGE_INPUT_SOURCE_ID"; fi)$(if [[ -n "${MACSTATICLANGUAGE_POLL_INTERVAL:-}" ]]; then printf '        <key>MACSTATICLANGUAGE_POLL_INTERVAL</key>\n        <string>%s</string>\n' "$MACSTATICLANGUAGE_POLL_INTERVAL"; fi)    </dict>
EOF
)
fi

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BUILD_PATH</string>
    </array>
$ENVIRONMENT_BLOCK
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <array>
        <string>Aqua</string>
    </array>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/stderr.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl kickstart -k "gui/$UID/$AGENT_LABEL"

echo "Installed $AGENT_LABEL"
echo "Logs:"
echo "  $LOG_DIR/stdout.log"
echo "  $LOG_DIR/stderr.log"
if [[ -n "${MACSTATICLANGUAGE_INPUT_SOURCE_ID:-}" ]]; then
    echo "Input source override: $MACSTATICLANGUAGE_INPUT_SOURCE_ID"
fi
