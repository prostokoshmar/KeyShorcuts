# Key Shortcuts

A macOS app that shows keyboard shortcuts for the frontmost application when you hold the Command key.

## Features
- Works across all macOS apps
- Shows shortcuts organized by menu category
- Live shortcut reading via Accessibility APIs
- Lives in the menu bar (no dock icon)
- Smooth overlay animation

## Usage
1. Launch the app
2. Grant Accessibility permission when prompted
3. Hold Command for 0.5 seconds in any app
4. The shortcut overlay appears — release Command to dismiss

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
