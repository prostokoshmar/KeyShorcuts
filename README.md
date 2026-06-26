# Key Shortcuts

A macOS menu bar utility with five productivity features: keyboard shortcut viewer, radial app switcher, clipboard history, keep-awake mode, and **file converter** (rename-to-convert).

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

### Convert (Rename to Convert)
Watches folders you choose. When a file's extension doesn't match its actual content (e.g. a HEIC file renamed to `.jpg`), it proposes converting it — no separate converter app needed.

**How it works:**
1. Pick one or more **watched folders** in Preferences → Convert
2. Rename any file's extension in a watched folder
3. A notification appears and the menu bar icon gets a badge — "photo.jpg looks like HEIC — convert?"
4. **Approve** in the menu or the queue overlay → the converted file is written atomically alongside the original (both are kept by default; no data is ever deleted)
5. Completion notification confirms success

**Supported formats (81 total):**

| Category | Formats |
|---|---|
| Images | JPEG, PNG, GIF, WebP, HEIC, AVIF, TIFF, BMP, ICO, ICNS, PSD, SVG, EPS, CR2, NEF, ARW, DNG, RAF, ORF, RW2, PEF *(RAW = read only)* |
| Audio | MP3, AAC, M4A, WAV, AIFF, FLAC, ALAC, OGG, Opus, WMA, CAF, AC-3, E-AC-3 |
| Video | MP4, MOV, WebM, MKV, AVI, 3GP, MXF, MPEG, M2TS, VOB, WMV, FLV, TS |
| Documents | PDF, PS, DOCX, PPTX, RTF, DOC, ODT, HTML, Markdown, TXT, RST, LaTeX |
| E-Books | EPUB, MOBI, AZW, AZW3 |
| Email | EML, EMLX *(MSG unsupported — needs external parser)* |
| Config | JSON, YAML, TOML, Plist, XML |
| Spreadsheets | CSV, TSV, XLSX, XLS |
| Archives | ZIP, TAR, TGZ, GZIP, 7z |

**Engine tiers:**
- **Built-in (zero extra installs):** Images, PDF, Config/CSV/TSV/YAML/TOML/Plist, Archives (ZIP/TAR/TGZ/GZIP), Email (EML/EMLX)
- **ffmpeg** *(audio + video)*: auto-detected from `Contents/Helpers/ffmpeg` or Homebrew. Install with `brew install ffmpeg`. ffmpeg is GPL-licensed; see [ffmpeg.org](https://ffmpeg.org) for source and license.
- **LibreOffice** *(DOCX/PPTX/XLS/ODT)*: auto-detected if installed. [Download](https://www.libreoffice.org)
- **pandoc** *(Markdown/HTML/RST/LaTeX/EPUB/RTF)*: `brew install pandoc`
- **Calibre** *(MOBI/AZW/AZW3)*: install [Calibre](https://calibre-ebook.com)

The Preferences → Convert tab shows which engines are available and links to install missing ones.

**Settings:**
- **Watched folders** — add/remove via folder picker
- **Auto-approve** (default off) — skip the approval prompt and convert silently
- **Notifications** — toggle detection and completion alerts
- **Output mode** — Keep both (default) / Replace original / Append suffix

## Usage

1. Launch the app and grant Accessibility permission when prompted
2. Hold ⌘ for 0.5 s in any app to see its keyboard shortcuts
3. Press ⌥Space anywhere to open the radial app switcher
4. Press ⌘⇧V to open clipboard history
5. Open **Preferences → Convert** to add watched folders
6. All hotkeys and settings are configurable in **Preferences** (menu bar icon → Preferences…)

**Hotkeys:** each feature hotkey (Clipboard, Keep Awake, App Switcher) accepts either a modifier chord (e.g. ⌘⇧V) or a **single function key** (F1–F20) as a one-press trigger — click the recorder and press it. Any non-function key must include a modifier, so ordinary typing is never intercepted. Tick **Double-tap to trigger** to require two quick presses instead of one.

**Launch at login:** toggle in **Preferences → General → Startup** to start Key Shortcuts automatically when you log in.

## Building

```bash
cd KeyShortcuts
chmod +x build.sh
./build.sh
```

This produces `KeyShortcuts.app` and `KeyShortcuts.dmg`.

**To bundle ffmpeg for audio/video conversion (Phase 2):**
```bash
# Place a static ffmpeg binary next to build.sh, then build:
cp /path/to/ffmpeg .
cp /path/to/ffmpeg-LICENSE.txt .
./build.sh
```
ffmpeg will be codesigned and placed in `Contents/Helpers/ffmpeg`. The GPL license file is required.

## Requirements
- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools with Swift
- Optional: ffmpeg, LibreOffice, pandoc, Calibre (for additional format support)
