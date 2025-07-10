# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Freewrite is a minimalist macOS app for freewriting - uninterrupted, stream-of-consciousness writing. Built with SwiftUI, it enforces continuous writing for 15-minute sessions without editing.

## Build and Development Commands

- **Build and run**: Open `freewrite.xcodeproj` in Xcode and click Build (⌘+R)
- **Test**: Run tests in Xcode (⌘+U) 
- **Clean build**: Product → Clean Build Folder (⌘+Shift+K)

## Code Architecture

### Main Structure
- `freewriteApp.swift`: App entry point, font registration, window configuration
- `ContentView.swift`: Core app logic (1,415 lines) - timer, text editor, file management, AI integration
- File storage: `~/Documents/Freewrite/` with pattern `[UUID]-[yyyy-MM-dd-HH-mm-ss].md`

### Key Components
- **Timer system**: 15-minute default (5-45 min range), scroll-to-adjust
- **Text editor**: Custom SwiftUI TextEditor with enforced leading newlines
- **Entry management**: Auto-save every second, individual markdown files per session
- **AI integration**: Direct ChatGPT/Claude links with custom prompts
- **PDF export**: Custom Core Text implementation

### State Management
Uses 25+ `@State` variables in ContentView for UI state, preferences, and entry management. The large ContentView could benefit from architectural refactoring into separate components.

### Dependencies
No external packages - uses only Apple frameworks (SwiftUI, AppKit, PDFKit, Core Text).

## Development Notes

- App uses sandbox with user-selected file permissions
- Custom Lato fonts registered at startup
- Current branch: `timeline-story` suggests timeline/story features in development
- No spell check or markdown rendering - intentionally minimal for freewriting flow
- Dark/light theme support via `@AppStorage`