# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Freewrite is a macOS SwiftUI application designed for freewriting - continuous, uninterrupted writing sessions. It's intentionally minimal, focusing on the writing experience without traditional note-taking features like organization or folders. All entries are saved as individual markdown files with UUID-based filenames in `~/Documents/Freewrite/`.

## Building & Running

```bash
# Open project in Xcode
open freewrite.xcodeproj

# Build and run from Xcode
# Use Cmd+R to build and run
# Use Cmd+B to build only
```

The app requires Xcode and macOS SDK. There are no external dependencies or package managers used.

## Testing

```bash
# Run tests in Xcode
# Use Cmd+U to run all tests
```

Tests are currently minimal scaffolding in `freewriteTests/` and `freewriteUITests/`.

## Architecture

### Single-View Application

The entire app is contained in one main view (`ContentView.swift`) with approximately 1,400 lines. This is intentional - the app is simple enough that splitting into multiple files would add unnecessary complexity.

### File Storage System

- **Location**: `~/Documents/Freewrite/`
- **Format**: Each entry is saved as `[UUID]-[yyyy-MM-dd-HH-mm-ss].md`
- **Auto-save**: Content is automatically saved every time text changes (1-second debounce via timer)
- **No database**: Everything is file-based markdown files

### Entry Management

The `HumanEntry` struct represents each writing session:
- `id`: UUID for tracking
- `date`: Display date string (e.g. "Feb 8")
- `filename`: Full filename with UUID and timestamp
- `previewText`: First 30 characters for sidebar display

On app launch, the system:
1. Loads all existing `.md` files from the Freewrite directory
2. Sorts by file date (newest first)
3. Checks if there's an empty entry from today
4. If first launch, creates welcome entry with content from `default.md`
5. Otherwise, loads most recent entry or creates new one

### Timer System

The countdown timer is implemented with:
- Default 15-minute duration (900 seconds)
- Scroll on timer text to adjust in 5-minute increments (0-45 minutes)
- Double-click to reset
- When running, the bottom navigation fades out after 1 second
- When timer hits zero, navigation fades back in

### Backspace Toggle

The app includes a feature to disable backspace/delete keys:
- Controlled by `backspaceDisabled` state
- Uses `NSEvent.addLocalMonitorForEvents` to intercept keyboard events
- Blocks key codes 51 (delete) and 117 (forward delete)
- Toggle button shows "Backspace is On/Off"

### AI Chat Integration

The "Chat" button opens a menu to send the current entry to ChatGPT or Claude with a custom prompt. The prompt is baked into the code (see `aiChatPrompt` and `claudePrompt` constants in ContentView.swift:129-153):
- Minimum 350 characters required to use
- URL length limited to 6000 characters
- If too long, offers "Copy Prompt" option instead
- Opens AI with entry text via URL query parameters

### PDF Export

Each entry can be exported as PDF:
- Uses CoreText with CTFramesetter for text layout
- Respects current font selection and size
- Maintains line spacing from editor
- Multi-page support with automatic pagination
- Filename suggestions based on first 4 words of entry
- Letter size (612x792 points) with 1-inch margins

### Theme System

- Light/dark mode toggle (sun/moon icon)
- Preference saved in UserDefaults with key "colorScheme"
- Affects text color, background, and all UI elements
- Applied via `.preferredColorScheme()` modifier

### Font System

Five built-in fonts:
- Lato (custom font, loaded from `fonts/Lato-Regular.ttf`)
- Arial
- System (.AppleSystemUIFont)
- Serif (Times New Roman)
- Random (picks from all available system fonts)

Font registration happens in `freewriteApp.init()` using `CTFontManagerRegisterFontsForURL`.

## Key Behavioral Details

### Text Initialization
- All text must start with `\n\n` (enforced in TextEditor binding)
- Placeholder text is randomized from 8 options on new entry creation
- First entry gets welcome message from `default.md` bundle resource

### Fullscreen Mode
- Window starts in windowed mode (1100x600 default size)
- AppDelegate ensures no fullscreen on launch
- Fullscreen button in bottom navigation
- Bottom nav auto-hides when timer is running

### History Sidebar
- 200px wide right panel
- Toggles with clock icon button
- Shows all entries sorted by date (newest first)
- Click entry to load it (auto-saves current entry first)
- Hover to reveal trash and export icons
- Click path at top to open Freewrite folder in Finder

## Important Implementation Notes

- The TextEditor is wrapped in a Binding that enforces the `\n\n` prefix requirement
- The view uses `.id("\(selectedFont)-\(fontSize)-\(colorScheme)")` to force TextEditor recreation when these change
- Preview text updates happen via `updatePreviewText(for:)` after saving
- Entry selection is tracked via `selectedEntryId` UUID rather than array index
- The timer uses `Timer.publish(every: 1, ...)` received via `.onReceive(timer)`

## Common File Locations

- Main app code: `freewrite/ContentView.swift`, `freewrite/freewriteApp.swift`
- Welcome message: `freewrite/default.md`
- Custom fonts: `freewrite/fonts/*.ttf`
- Assets: `freewrite/Assets.xcassets/`
- Tests: `freewriteTests/`, `freewriteUITests/`

## Project Philosophy

This app is intentionally simple and minimal. It's not meant to be a full-featured writing tool or note-taking app. The focus is on:
- Uninterrupted freewriting sessions
- No organization, folders, or tags
- Simple file-based storage
- Minimal UI that fades away during writing

When making changes, preserve this simplicity and avoid adding features that would complicate the core freewriting experience.
