import { 
  app, 
  BrowserWindow, 
  ipcMain, 
  session, 
  Notification,
  IpcMainEvent,
  IpcMainInvokeEvent,
  OnHeadersReceivedListenerDetails, 
  HeadersReceivedResponse 
} from 'electron';
import path from 'path';
import Store from 'electron-store';
import { v4 as uuidv4 } from 'uuid';

// Define types for store data (can be shared with renderer if needed)
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

interface NotificationOptions {
  title: string;
  body: string;
}

// Initialize stores with proper types
interface FileStoreSchema {
  [key: string]: Entry;
}

const fileStore = new Store<FileStoreSchema>({ name: 'freewrite-entries' });
const settingsStore = new Store<Settings>({
  name: 'freewrite-settings',
  defaults: {
    font: 'Lato',
    fontSize: 18,
    lineSpacing: 1.6,
    timerDuration: 15,
    autoSaveInterval: 10,
    aiMinCharCount: 350,
    aiProvider: 'chatgpt',
  },
  encryptionKey: 'freewrite-secret',
});

let mainWindow: BrowserWindow | null = null;
let currentEntryId: string | null = null; // Keep track of the current entry ID in main

function createWindow() {
  // Set up content security policy
  session.defaultSession.webRequest.onHeadersReceived((details: OnHeadersReceivedListenerDetails, callback: (response: HeadersReceivedResponse) => void) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        'Content-Security-Policy': [
          "default-src 'self'",
          "script-src 'self' 'unsafe-inline' 'unsafe-eval' http://localhost:5173",
          "style-src 'self' 'unsafe-inline'",
          "font-src 'self' data: https://fonts.gstatic.com",
          "img-src 'self' data: https:",
          "connect-src 'self' ws://localhost:5173 http://localhost:5173 ws: wss: https:",
          "worker-src 'self' blob:",
          "frame-src 'self'"
        ].join('; ')
      }
    });
  });

  mainWindow = new BrowserWindow({
    width: 1100,
    height: 600,
    minWidth: 1100,
    minHeight: 600,
    title: 'freewrite',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      preload: path.join(__dirname, 'preload.js')
    },
    frame: false,
  });

  if (process.env.NODE_ENV === 'development') {
    mainWindow.loadURL('http://localhost:5173');
    mainWindow.webContents.openDevTools();
  } else {
    mainWindow.loadFile(path.join(__dirname, '../dist/index.html'));
  }

  // --- IPC Handlers for File Store ---

  ipcMain.handle('file:createEntry', (_: IpcMainInvokeEvent, entryData: Omit<Entry, 'id'>) => {
    const id = uuidv4();
    const newEntry = { ...entryData, id };
    fileStore.set(id, newEntry);
    currentEntryId = id;
    return newEntry;
  });

  ipcMain.handle('file:updateEntry', (_: IpcMainInvokeEvent, { id, content, preview }: { id: string; content: string; preview: string }) => {
    const entry = fileStore.get(id) as Entry | undefined;
    if (!entry) return null;
    const updatedEntry = { ...entry, content, preview, updatedAt: new Date().toISOString() };
    fileStore.set(id, updatedEntry);
    return updatedEntry;
  });

  ipcMain.handle('file:getEntry', (_: IpcMainInvokeEvent, id: string) => {
    return fileStore.get(id) || null;
  });

  ipcMain.handle('file:getAllEntries', (_: IpcMainInvokeEvent) => {
    const entries = Object.values(fileStore.store) as Entry[];
    return entries.sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime());
  });

  ipcMain.handle('file:deleteEntry', (_: IpcMainInvokeEvent, id: string) => {
    if (fileStore.has(id)) {
      fileStore.delete(id);
      if (currentEntryId === id) {
        currentEntryId = null;
      }
      return true;
    }
    return false;
  });

  ipcMain.handle('file:getCurrentEntryId', (_: IpcMainInvokeEvent) => {
    // Attempt to load the last known entry ID if not set
    if (!currentEntryId) {
        const entries = Object.values(fileStore.store) as Entry[];
        const sortedEntries = entries.sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime());
        if (sortedEntries.length > 0) {
            currentEntryId = sortedEntries[0].id;
        }
    }
    return currentEntryId;
  });

  ipcMain.handle('file:setCurrentEntryId', (_: IpcMainInvokeEvent, id: string | null) => {
    currentEntryId = id;
    return id;
  });

  // --- IPC Handlers for Settings Store ---

  ipcMain.handle('settings:getAll', (_: IpcMainInvokeEvent) => {
    return settingsStore.store;
  });

  ipcMain.handle('settings:get', (_: IpcMainInvokeEvent, key: keyof Settings) => {
    return settingsStore.get(key);
  });

  ipcMain.handle('settings:set', (_: IpcMainInvokeEvent, { key, value }: { key: keyof Settings; value: any }) => {
    settingsStore.set(key, value);
    return true;
  });

  ipcMain.handle('settings:update', (_: IpcMainInvokeEvent, settings: Partial<Settings>) => {
    settingsStore.set(settings);
    return true;
  });

  ipcMain.handle('settings:reset', (_: IpcMainInvokeEvent) => {
    settingsStore.clear(); // Resets to defaults defined in constructor
    return settingsStore.store;
  });

  // Window control handlers
  ipcMain.on('minimize-window', () => {
    mainWindow?.minimize();
  });

  ipcMain.on('maximize-window', () => {
    if (mainWindow?.isMaximized()) {
      mainWindow.unmaximize();
    } else {
      mainWindow?.maximize();
    }
  });

  ipcMain.on('close-window', () => {
    mainWindow?.close();
  });

  // Add fullscreen handlers
  ipcMain.on('toggle-fullscreen', () => {
    if (mainWindow) {
      const isFullScreen = mainWindow.isFullScreen();
      mainWindow.setFullScreen(!isFullScreen);
    }
  });

  ipcMain.on('get-fullscreen-state', (event: IpcMainEvent) => {
    event.reply('fullscreen-state', mainWindow?.isFullScreen() || false);
  });

  // Listen for fullscreen changes
  mainWindow?.on('enter-full-screen', () => {
    mainWindow?.webContents.send('fullscreen-changed', true);
  });

  mainWindow?.on('leave-full-screen', () => {
    mainWindow?.webContents.send('fullscreen-changed', false);
  });

  // Add notification handler
  ipcMain.on('show-notification', (_: IpcMainEvent, options: NotificationOptions) => {
    new Notification({
      title: options.title,
      body: options.body,
      icon: path.join(__dirname, '../public/icon.png'),
      silent: false
    }).show();
  });
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});