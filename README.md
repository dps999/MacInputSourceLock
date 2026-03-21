# MacStaticLanguage

`MacStaticLanguage` is a small macOS background utility that keeps your keyboard input source on English whenever the focused app or focused window changes. It is intended to override macOS behaviors such as per-window input source switching and Spotlight stealing the previous layout.

The default enforced input source is `com.apple.keylayout.ABC`, which is the standard English layout on current macOS versions.

## What It Does

- Monitors the frontmost application.
- Polls the focused window or focused UI element so window-to-window changes inside the same app are also detected.
- Switches the keyboard layout back to the configured English input source when focus changes.
- Can run automatically at login through a LaunchAgent.

## Requirements

- macOS 13 or later
- Xcode 16.4 or a compatible Swift 6 toolchain
- Accessibility permission for the process

## Build

```bash
swift build
```

## List Available Input Sources

Use this first if you want `US` instead of `ABC` or if your English layout uses a different ID:

```bash
swift run MacStaticLanguage --list-input-sources
```

The current selection is marked with `*`.

## Run Manually

```bash
swift run MacStaticLanguage
```

To enforce a different layout ID:

```bash
swift run MacStaticLanguage --input-source-id com.apple.keylayout.US
```

You can also set the ID with an environment variable:

```bash
MACSTATICLANGUAGE_INPUT_SOURCE_ID=com.apple.keylayout.US swift run MacStaticLanguage
```

## Install At Login

```bash
chmod +x Scripts/install-launch-agent.sh Scripts/uninstall-launch-agent.sh
./Scripts/install-launch-agent.sh
```

The install script builds the project in release mode and installs `~/Library/LaunchAgents/com.macstaticlanguage.agent.plist`.

To install with a different English layout:

```bash
MACSTATICLANGUAGE_INPUT_SOURCE_ID=com.apple.keylayout.US ./Scripts/install-launch-agent.sh
```

## Uninstall

```bash
./Scripts/uninstall-launch-agent.sh
```

## Accessibility Permission

The first run opens the macOS accessibility prompt. After that, approve `MacStaticLanguage` in:

`System Settings > Privacy & Security > Accessibility`

If the prompt does not appear, run:

```bash
swift run MacStaticLanguage
```

and then add the built executable manually from:

`/Users/.../macstaticlanguage/.build/debug/MacStaticLanguage`

## Notes

- This utility is designed for your exact case: force English again when app focus changes, window focus changes, or Spotlight becomes active.
- If macOS `Automatically switch to a document's input source` is enabled, this utility should still push the layout back to English after the focus change happens.
