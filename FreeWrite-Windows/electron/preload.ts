import { IpcRendererEvent } from 'electron';
const { contextBridge, ipcRenderer } = require('electron');

// Define types (consider sharing from a common types file)
interface Entry {
  id: string;
  content: string;
  preview: string;
  createdAt: string;
  updatedAt: string;
}

interface Settings {
  font: string;
  fontSize: number;
  lineSpacing: number;
  timerDuration: number;
  autoSaveInterval: number;
  aiApiKey?: string;
  aiMinCharCount: number;
  aiProvider: 'chatgpt' | 'claude';
}

contextBridge.exposeInMainWorld('electron', {
  // --- Window Controls & Notifications ---
  minimize: () => ipcRenderer.send('minimize-window'),
  maximize: () => ipcRenderer.send('maximize-window'),
  close: () => ipcRenderer.send('close-window'),
  toggleFullscreen: () => ipcRenderer.send('toggle-fullscreen'),
  getFullscreenState: () => ipcRenderer.send('get-fullscreen-state'),
  onFullscreenChange: (callback: (isFullscreen: boolean) => void) => {
    ipcRenderer.on('fullscreen-changed', (_: IpcRendererEvent, isFullscreen: boolean) => callback(isFullscreen));
    ipcRenderer.on('fullscreen-state', (_: IpcRendererEvent, isFullscreen: boolean) => callback(isFullscreen));
  },
  showNotification: (title: string, body: string) => {
    ipcRenderer.send('show-notification', { title, body });
  },

  // --- File Store API ---
  fileStore: {
    createEntry: (entryData: Omit<Entry, 'id'>): Promise<Entry> => ipcRenderer.invoke('file:createEntry', entryData),
    updateEntry: (updateData: { id: string; content: string; preview: string }): Promise<Entry | null> => ipcRenderer.invoke('file:updateEntry', updateData),
    getEntry: (id: string): Promise<Entry | null> => ipcRenderer.invoke('file:getEntry', id),
    getAllEntries: (): Promise<Entry[]> => ipcRenderer.invoke('file:getAllEntries'),
    deleteEntry: (id: string): Promise<boolean> => ipcRenderer.invoke('file:deleteEntry', id),
    getCurrentEntryId: (): Promise<string | null> => ipcRenderer.invoke('file:getCurrentEntryId'),
    setCurrentEntryId: (id: string | null): Promise<void> => ipcRenderer.invoke('file:setCurrentEntryId', id),
  },

  // --- Settings Store API ---
  settingsStore: {
    getAll: (): Promise<Settings> => ipcRenderer.invoke('settings:getAll'),
    get: <K extends keyof Settings>(key: K): Promise<Settings[K]> => ipcRenderer.invoke('settings:get', key),
    set: <K extends keyof Settings>(key: K, value: Settings[K]): Promise<void> => ipcRenderer.invoke('settings:set', { key, value }),
    update: (settings: Partial<Settings>): Promise<void> => ipcRenderer.invoke('settings:update', settings),
    reset: (): Promise<Settings> => ipcRenderer.invoke('settings:reset'),
  },
});