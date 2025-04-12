# Featherwrite for Windows

A minimalist writing application designed for distraction-free freewriting. Features a clean interface, automatic saving, and AI-powered writing assistance.

<iframe width="560" height="315" src="https://www.youtube.com/embed/vIPzU16fdrs?si=05Z_aqEWWQu_0-mg" frameborder="0" allowfullscreen></iframe>


## Features

- Distraction-free writing environment
- 15-minute countdown timer with visual fade effects
- Font customization (Lato, Arial, System, Serif, Random)
- Font size adjustment (16px - 26px)
- Line spacing adjustments
- Automatic saving
- Entry history with date-based organization
- AI-powered writing feedback (supports ChatGPT and Claude)
- Fullscreen mode
- Keyboard shortcuts

## Installation

1. Download the latest installer from the [releases page](https://github.com/GxAditya/freewrite-win/releases)
2. Run the installer and follow the prompts
3. Launch Freewrite from the Start menu or desktop shortcut

## Development Setup

### Prerequisites

- Node.js 18+ and npm
- Git

### Installation Steps

1. Clone the repository:
```bash
git clone https://github.com/GxAditya/freewrite-win.git
cd freewrite-win
```

2. Install dependencies:
```bash
npm install
```

3. Start the development server:
```bash
npm start
```

### Building

To create a production build:
```bash
npm run dist
```

The installer will be created in the `release` directory.

## Keyboard Shortcuts

- `Ctrl + F` - Toggle fullscreen mode
- `Ctrl + S` - Open settings
- `Ctrl + H` - Toggle history sidebar
- `Ctrl + Enter` - Request AI feedback (when enough text is present)
- `Escape` - Close dialogs / Exit fullscreen

## Configuration

Settings are stored in `%APPDATA%/freewrite-settings/config.json` and can be configured through the Settings interface (Ctrl+S).

### AI Integration

To use AI features:
1. Open Settings (Ctrl+S)
2. Go to the "AI Integration" tab
3. Select your preferred provider (ChatGPT or Claude)
4. Enter your API key
5. Adjust the minimum character count if desired

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Credits

- Lato font used under the SIL Open Font License 1.1
- Icons and UI elements inspired by Windows 11 design guidelines

## Contributing

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin feature/my-new-feature`
5. Submit a pull request

## Support

For support, please [open an issue](https://github.com/your-username/freewrite-win/issues/new) on GitHub.
