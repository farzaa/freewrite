# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FreeJournal is a macOS SwiftUI app for freewriting - a writing strategy where you write continuously for a set time without worrying about grammar or spelling. This is a remix of the original freewrite app by farza.

## Architecture

- **SwiftUI App**: Native macOS application targeting macOS 14.0+
- **Single Window**: Uses hidden title bar with customizable window styling
- **Main Components**:
  - `ContentView.swift`: Main interface containing the editor, timer, and all UI logic
  - `freewriteApp.swift`: App entry point with window configuration and font registration
  - `default.md`: Default welcome/instruction content loaded on first run

## Key Features

- **Freewriting Editor**: Text editor with no backspace/editing allowed during sessions
- **Timer System**: Configurable timer (5m, 10m, 15m, 25m) with scroll-to-adjust functionality
- **File Management**: Automatic saving of sessions with date-based filenames
- **AI Integration**: ChatGPT/Claude integration via URL schemes for reflection
- **History**: Local file storage with history browser
- **Customization**: Font selection, size adjustment, and color scheme support
- **Fullscreen Mode**: Distraction-free writing environment

## Build Commands

This is a standard Xcode project. To build and run:

1. **Open in Xcode**: `open freewrite.xcodeproj`
2. **Build**: Use Xcode's build system (⌘+B)
3. **Run**: Use Xcode's run command (⌘+R)
4. **Test**: Run unit tests with ⌘+U

## Development Notes

- **Bundle ID**: `app.humansongs.freewrite`
- **Deployment Target**: macOS 14.0
- **Swift Version**: 5.0
- **Custom Font**: Lato font family is bundled and registered at app launch
- **File Structure**: Sessions are saved as Markdown files with naming pattern `[Daily]-[MM-dd-yyyy]-[HH-mm-ss].md`
- **Settings**: Uses `@AppStorage` for persistence (color scheme, API keys, etc.)

## Key Data Structures

- `HumanEntry`: Represents a writing session with ID, date, filename, and preview text
- `SettingsTab`: Enum for settings navigation (Reflections, API Keys, Transcription)
- File storage uses the user's Documents directory with automatic directory creation

## Testing

- Unit tests in `freewriteTests/`
- UI tests in `freewriteUITests/`
- No specific test commands beyond Xcode's standard test runner

## Third-Party Dependencies

- **AVFoundation**: For audio recording functionality
- **PDFKit**: For document handling
- **Network**: For connectivity checks
- **Security**: For keychain operations
- No external package dependencies via Swift Package Manager