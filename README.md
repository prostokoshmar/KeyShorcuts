# Key Shortcuts

A macOS menu bar utility with four productivity features: keyboard shortcut viewer, radial app switcher, clipboard history, and keep-awake mode.

## Features

### Keyboard Shortcut Overlay
- Hold a trigger key (default: ⌘ Command) to see all shortcuts for the frontmost app
- Shortcuts organized by menu category in a floating overlay
- Live reading via Accessibility APIs — works across all macOS apps
- Trigger key and mode (hold / double-press) are configurable

### Radial App Switcher
- Press a hotkey (default: ⌥ Space) to show all running apps as icons around the mouse cursor
- Hover over an app with multiple windows to see a window list — click any window to raise it
- Single-window apps switch instantly on click with no extra popup
- Hotkey is configurable in Preferences

### Clipboard History
- Maintains a history of recent clipboard items (text and images)
- Press a hotkey (default: ⌘⇧V) to open the history overlay and paste any item
- Optional auto-copy: adds selected text to history without needing ⌘C
- Configurable history limit (5 / 10 / 20 / 50 items)

### Keep Awake
- Prevents the display from sleeping while active
- Toggle via the menu bar or a configurable hotkey (default: ⌘K)

## Usage

1. Launch the app and grant Accessibility permission when prompted
2. Hold ⌘ for 0.5 s in any app to see its keyboard shortcuts
3. Press ⌥Space anywhere to open the radial app switcher
4. Press ⌘⇧V to open clipboard history
5. All hotkeys and settings are configurable in **Preferences** (menu bar icon → Preferences…)

## Building

```bash
cd KeyShortcuts
chmod +x build.sh
./build.sh
```

This produces `KeyShortcuts.app` and `KeyShortcuts.dmg`.

## Requirements
- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools with Swift
