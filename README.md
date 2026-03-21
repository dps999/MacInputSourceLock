# MacInputSourceLock

MacInputSourceLock is a native macOS menu bar utility that forces the keyboard input source back to English when focus changes between apps or windows.

It is intended for the specific macOS behavior where input language follows the last active window, document, or Spotlight session. With this app running, the system is pushed back to a fixed English layout after those focus changes happen.

By default, the enforced input source is:

`com.apple.keylayout.ABC`

## Features

- Forces English again when the frontmost app changes.
- Detects window changes inside the same app.
- Handles common cases like Spotlight switching to a previous layout.
- Runs as a menu bar app with a visible tray icon.
- Shows current status from the tray menu.
- Supports `Run at Startup` from the tray menu.
- Supports manual LaunchAgent install scripts.
- Lets you choose a different English keyboard layout ID such as `US`.

## Requirements

- macOS 13 or later
- Xcode 16.4 or a compatible Swift 6 toolchain
- Accessibility permission for the app

## Download

GitHub Releases now ship a zipped app bundle instead of a raw executable:

- Download `MacInputSourceLock-<version>-macos-<arch>.zip` from the release page
- Move `MacInputSourceLock.app` to `/Applications`
- On first launch, use Finder `Open` once to bypass the unsigned-app warning

If Gatekeeper still blocks the app after moving it, remove the quarantine flag manually:

```bash
xattr -dr com.apple.quarantine /Applications/MacInputSourceLock.app
```

## Permissions

MacInputSourceLock requires this macOS permission:

- `Accessibility`

It uses Accessibility APIs to detect the focused app, focused window, and focused UI element. Without that permission, the app can stay running in the menu bar, but it cannot reliably detect focus changes and switch the keyboard layout back to English.

## Quick Start

After cloning the repository:

```bash
git clone https://github.com/dps999/MacInputSourceLock.git
cd macinputsourcelock
swift build -c release
./.build/release/MacInputSourceLock
```

On first launch, macOS should ask for Accessibility permission. Approve it in:

`System Settings > Privacy & Security > Accessibility`

If the prompt does not appear, launch the app once and add the executable manually in that settings panel.

When the app is running, you should see a `lock + EN` item in the menu bar.

## Build

Debug build:

```bash
swift build
```

Release build:

```bash
swift build -c release
```

Package an unsigned `.app` bundle and zip it for GitHub Releases:

```bash
./Scripts/package-app.sh v0.1.0
```

This writes:

- `dist/MacInputSourceLock.app`
- `dist/MacInputSourceLock-v0.1.0-macos-arm64.zip` on Apple Silicon Macs

## Run

Run the debug build with SwiftPM:

```bash
swift run MacInputSourceLock
```

Run the compiled release binary directly:

```bash
./.build/release/MacInputSourceLock
```

## Choose the English Layout

List available selectable keyboard layouts:

```bash
swift run MacInputSourceLock --list-input-sources
```

Example output:

```text
  com.apple.keylayout.ABC | ABC
  com.apple.keylayout.Greek | Greek
* com.apple.keylayout.Russian | Russian
```

To use `US` instead of `ABC`:

```bash
swift run MacInputSourceLock --input-source-id com.apple.keylayout.US
```

You can also use an environment variable:

```bash
MACINPUTSOURCELOCK_INPUT_SOURCE_ID=com.apple.keylayout.US swift run MacInputSourceLock
```

## Menu Bar Usage

When the app is running, click the tray icon to open the menu. The menu shows:

- Whether the app is running normally or waiting for Accessibility permission
- The target input source ID
- The current input source ID
- The last event handled by the app
- A `Run at Startup` toggle
- A shortcut to macOS Accessibility settings
- A `Quit` action

## Run at Startup

The simplest way is from the tray menu:

1. Start the app normally.
2. Click the menu bar icon.
3. Enable `Run at Startup`.

If you are using the packaged app, move it to a stable path such as `/Applications` before enabling `Run at Startup`.

This creates a LaunchAgent in:

`~/Library/LaunchAgents/com.macinputsourcelock.agent.plist`

The startup item does not change the permission model. The launched app still needs `Accessibility` permission.

You can also install startup manually:

```bash
chmod +x Scripts/install-launch-agent.sh Scripts/uninstall-launch-agent.sh
./Scripts/install-launch-agent.sh
```

To install startup with a different layout:

```bash
MACINPUTSOURCELOCK_INPUT_SOURCE_ID=com.apple.keylayout.US ./Scripts/install-launch-agent.sh
```

To remove startup:

```bash
./Scripts/uninstall-launch-agent.sh
```

## Command Line Options

```text
--input-source-id <id>     Keyboard input source to enforce
--poll-interval <seconds>  Focus polling interval
--list-input-sources       Print available keyboard input source IDs and exit
--no-accessibility-prompt  Do not open the macOS accessibility prompt
--help, -h                 Show help
```

## How to Verify It Is Working

Check that the process is running:

```bash
pgrep -fl MacInputSourceLock
```

If it is installed at startup, check the LaunchAgent:

```bash
launchctl print gui/$UID/com.macinputsourcelock.agent
```

Practical test:

1. Switch to a non-English layout.
2. Open Spotlight or switch to another app or window.
3. The layout should switch back to English.

## Troubleshooting

If the app starts but does not switch layouts:

- Confirm Accessibility permission is granted.
- Open the tray menu and check the status text.
- Make sure the target input source ID exists on your Mac.
- Run `--list-input-sources` and use the exact ID returned by macOS.

If the Accessibility prompt does not appear:

```bash
swift run MacInputSourceLock
```

Then add the executable manually in Accessibility settings.

If you want to add the debug binary manually, it is usually here:

`/Users/.../macinputsourcelock/.build/debug/MacInputSourceLock`

If you run the release build, use the release binary path instead:

`/Users/.../macinputsourcelock/.build/release/MacInputSourceLock`

## Repository Layout

```text
Sources/MacInputSourceLock/
  Configuration.swift
  InputSourceManager.swift
  LanguageEnforcer.swift
  LaunchAgentManager.swift
  MacInputSourceLockApp.swift
  StatusItemController.swift

Scripts/
  install-launch-agent.sh
  uninstall-launch-agent.sh
```

## Notes

- The app is built for the exact workflow of keeping English fixed after macOS focus changes.
- If macOS `Automatically switch to a document's input source` is enabled, this app still attempts to override that by switching back after focus changes.
