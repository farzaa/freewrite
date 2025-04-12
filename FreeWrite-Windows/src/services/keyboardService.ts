type KeyboardShortcut = {
  key: string;
  altKey?: boolean;
  ctrlKey?: boolean;
  shiftKey?: boolean;
  metaKey?: boolean;
  preventDefault?: boolean;
  action: () => void;
};

class KeyboardService {
  private shortcuts: KeyboardShortcut[] = [];

  registerShortcut(shortcut: KeyboardShortcut) {
    this.shortcuts.push(shortcut);
  }

  private matchesShortcut(event: KeyboardEvent, shortcut: KeyboardShortcut): boolean {
    return (
      event.key.toLowerCase() === shortcut.key.toLowerCase() &&
      !!event.altKey === !!shortcut.altKey &&
      !!event.ctrlKey === !!shortcut.ctrlKey &&
      !!event.shiftKey === !!shortcut.shiftKey &&
      !!event.metaKey === !!shortcut.metaKey
    );
  }

  handleKeyDown = (event: KeyboardEvent) => {
    for (const shortcut of this.shortcuts) {
      if (this.matchesShortcut(event, shortcut)) {
        if (shortcut.preventDefault) {
          event.preventDefault();
        }
        shortcut.action();
        break;
      }
    }
  };

  start() {
    document.addEventListener('keydown', this.handleKeyDown);
  }

  stop() {
    document.removeEventListener('keydown', this.handleKeyDown);
  }
}

export const keyboardService = new KeyboardService();

// Default shortcuts
document.addEventListener('DOMContentLoaded', () => {
  keyboardService.start();
});