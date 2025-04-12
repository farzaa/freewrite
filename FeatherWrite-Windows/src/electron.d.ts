// Define and export types
export interface Entry {
  id: string;
  content: string;
  preview: string;
  createdAt: string;
  updatedAt: string;
}

export interface Settings {
  font: string;
  fontSize: number;
  lineSpacing: number;
  timerDuration: number;
  autoSaveInterval: number;
  aiApiKey?: string;
  aiMinCharCount: number;
  aiProvider: 'chatgpt' | 'claude' | 'gemini';
}

export interface FileStoreAPI {
  createEntry: (entryData: Omit<Entry, 'id'>) => Promise<Entry>;
  updateEntry: (updateData: { id: string; content: string; preview: string }) => Promise<Entry | null>;
  getEntry: (id: string) => Promise<Entry | null>;
  getAllEntries: () => Promise<Entry[]>;
  deleteEntry: (id: string) => Promise<boolean>;
  getCurrentEntryId: () => Promise<string | null>;
  setCurrentEntryId: (id: string | null) => Promise<void>;
}

export interface SettingsStoreAPI {
  getAll: () => Promise<Settings>;
  get: <K extends keyof Settings>(key: K) => Promise<Settings[K]>;
  set: <K extends keyof Settings>(key: K, value: Settings[K]) => Promise<void>;
  update: (settings: Partial<Settings>) => Promise<void>;
  reset: () => Promise<Settings>;
}

export interface ElectronWindow {
  // --- Window Controls & Notifications ---
  minimize: () => void;
  maximize: () => void;
  close: () => void;
  toggleFullscreen: () => void;
  getFullscreenState: () => void;
  onFullscreenChange: (callback: (isFullscreen: boolean) => void) => void;
  showNotification: (title: string, body: string) => void;

  // --- Store APIs ---
  fileStore: FileStoreAPI;
  settingsStore: SettingsStoreAPI;
}

declare global {
  interface Window {
    electron: ElectronWindow;
  }
}