# Development Prompt: Freewrite for Windows (Electron.js)

## Overview
Create a Windows version of "Freewrite" - a minimalist writing application designed for distraction-free freewriting. The app should replicate the macOS version's core functionality and aesthetic while adapting appropriately to the Windows environment using Electron.js.

## Core Requirements

### Functionality
- Implement a distraction-free writing environment focused on continuous writing
- 15-minute countdown timer with visual fade effects
- Adjustable timer duration via scroll while hovering
- Font selection (Lato, Arial, System, Serif, Random)
- Font size adjustment (16px - 26px)
- Line spacing adjustments
- Fullscreen mode
- Entry management system with automatic saving
- AI integration with ChatGPT and Claude

### User Interface
- Clean, minimalist design with hidden or minimal window decorations
- Centered text area with maximum width of 650px
- Light theme with carefully selected text/background colors
- History sidebar with entry previews organized by date
- Hover effects for interactive elements
- Smooth animations for UI transitions

## Technical Specifications

### Core Technology Stack
- **Framework**: Electron.js
- **Frontend**: HTML, CSS, JavaScript
- **Recommended UI Framework**: React or Vue.js
- **Build System**: Webpack or Vite
- **Minimum Window Size**: 1100x600
- **Target Platform**: Windows 10/11

### Architecture Components
1. **Main Process**
   - Window management
   - Application lifecycle
   - Native OS integration
   - File system operations

2. **Renderer Process**
   - UI components and logic
   - Text input handling
   - Timer functionality
   - AI integration

3. **Data Management**
   - Store entries as .md files with UUID-based filenames
   - Implement automatic file creation and management
   - Generate preview text for sidebar
   - Create date-based organization system

### Required Dependencies
- `electron` - Application framework
- `react` or `vue` - UI framework
- `electron-store` - For persistent settings
- `uuid` - For generating unique IDs
- `marked` - For markdown processing
- `codemirror` or similar for the text editing component
- `lato-font` - Include the Lato font family under OFL license
- `axios` or similar for API communication with AI services

## Detailed Feature Implementation

### Writing Interface
- Implement a clean text editor component with:
  - Proper cursor management
  - No spell check by default
  - No visible formatting options unless requested
  - Intelligent placeholder text system

### Timer System
- Create a 15-minute countdown timer with:
  - Visual indication of remaining time
  - Fading effect as time depletes
  - Ability to adjust duration by scrolling when hovering
  - Optional notification when timer completes

### Entry Management
- Implement a file-based storage system:
  - Auto-save entries at regular intervals (every 5-10 seconds)
  - Store as markdown files in a user-accessible location
  - Create history sidebar showing entry previews
  - Implement date-based organization
  - Add entry deletion functionality

### AI Integration
- Create integration points for AI services:
  - Set minimum character count (350) before allowing AI interaction
  - Design a smart prompting system for meaningful responses
  - Implement custom conversation starters
  - Handle API authentication securely
  - Create fallback behavior when offline

### Settings & Customization
- Create a settings interface for:
  - Font selection and size
  - Line spacing adjustment
  - Timer duration defaults
  - AI service configuration
  - Theme preferences (if implementing dark mode)

## UI/UX Guidelines

### Visual Design
- Clean, minimalist interface with maximum focus on text
- Light color scheme with carefully selected text colors
- Hidden or minimal window decorations
- Consistent spacing and alignment
- Subtle animations and transitions

### Interaction Design
- Intuitive hover effects for interactive elements
- Minimal clicks required for core functionality
- Keyboard shortcuts for common actions
- Smooth transitions between screens/states
- Clear visual feedback for all user actions

## File Structure Recommendation
```
freewrite-electron/
├── package.json
├── main.js                # Main process entry point
├── src/
│   ├── index.html         # Main HTML template
│   ├── renderer.js        # Renderer process entry
│   ├── components/        # UI components
│   ├── styles/            # CSS/SCSS files
│   ├── utils/             # Utility functions
│   └── services/          # Core functionality services
├── assets/
│   ├── fonts/             # Lato and other fonts
│   └── images/            # App icons and images
└── build/                 # Build configuration
```

## Packaging Requirements
- Create Windows installer with appropriate icons
- Set up automatic updates mechanism
- Configure proper app identification
- Include appropriate licenses for all dependencies
- Implement crash reporting

## Testing Requirements
- Unit tests for core functionality
- Integration tests for file operations
- UI tests for critical user flows
- Performance testing, especially for large files

## Documentation
- Include clear installation instructions
- Document all keyboard shortcuts
- Provide user guide for first-time users
- Add developer documentation for future maintenance

## Licensing
- Application should be released under MIT License
- Include appropriate attribution for all dependencies
- Ensure Lato font is properly licensed under SIL Open Font License 1.1