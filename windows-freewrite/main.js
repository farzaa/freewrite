const { app, BrowserWindow, Menu, ipcMain, dialog, shell, globalShortcut } = require('electron');
const path = require('path');
const fs = require('fs');

// Handle creating/removing shortcuts on Windows when installing/uninstalling
if (require('electron-squirrel-startup')) {
  app.quit();
}

let mainWindow;

function createWindow() {
  // Create the browser window.
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 600,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      enableRemoteModule: true,
    },
    frame: false,
    titleBarStyle: 'hidden',
    backgroundColor: '#FFFFFF',
    show: false,
    roundedCorners: false,
    icon: path.join(__dirname, 'assets/icon.png')
  });

  // and load the index.html of the app.
  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  
  // Wait until the content is ready, then show window
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });
  
  // Create application menu (empty)
  const template = [];
  const menu = Menu.buildFromTemplate(template);
  Menu.setApplicationMenu(menu);
  
  // Register a global shortcut listener for Escape key to exit the app
  mainWindow.on('focus', () => {
    globalShortcut.register('Escape', () => {
      if (mainWindow) {
        if (mainWindow.isFullScreen()) {
          // If in fullscreen, first exit fullscreen
          mainWindow.setFullScreen(false);
        } else {
          // If not in fullscreen, quit the app
          app.quit();
        }
      }
    });
  });
  
  // Unregister the shortcut when the window loses focus
  mainWindow.on('blur', () => {
    globalShortcut.unregisterAll();
  });
  
  // Unregister shortcuts when window is closed
  mainWindow.on('closed', () => {
    globalShortcut.unregisterAll();
    mainWindow = null;
  });
}

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
app.whenReady().then(() => {
  createWindow();
  
  app.on('activate', function () {
    // On macOS it's common to re-create a window in the app when the
    // dock icon is clicked and there are no other windows open.
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

// Quit when all windows are closed, except on macOS.
app.on('window-all-closed', function () {
  if (process.platform !== 'darwin') app.quit();
});

// Listen for save entry event
ipcMain.on('save-entry', (event, data) => {
  const { content, filename } = data;
  
  // Get documents directory
  const documentsPath = path.join(app.getPath('documents'), 'Freewrite');
  
  // Create directory if it doesn't exist
  if (!fs.existsSync(documentsPath)) {
    fs.mkdirSync(documentsPath, { recursive: true });
  }
  
  const filePath = path.join(documentsPath, filename);
  
  // Save the file
  fs.writeFileSync(filePath, content, 'utf-8');
  event.reply('save-complete', { success: true, path: filePath });
});

// Listen for load entries event
ipcMain.on('load-entries', (event) => {
  const documentsPath = path.join(app.getPath('documents'), 'Freewrite');
  
  // Create directory if it doesn't exist
  if (!fs.existsSync(documentsPath)) {
    fs.mkdirSync(documentsPath, { recursive: true });
    event.reply('entries-loaded', { entries: [] });
    return;
  }
  
  // Read all markdown files
  fs.readdir(documentsPath, (err, files) => {
    if (err) {
      event.reply('entries-loaded', { entries: [], error: err.message });
      return;
    }
    
    const mdFiles = files.filter(file => file.endsWith('.md'));
    const entries = [];
    
    mdFiles.forEach(filename => {
      const filePath = path.join(documentsPath, filename);
      const content = fs.readFileSync(filePath, 'utf-8');
      const previewText = content.replace(/\n/g, ' ').trim().substring(0, 30) + (content.length > 30 ? '...' : '');
      
      // Extract UUID and date from filename - pattern [uuid]-[yyyy-MM-dd-HH-mm-ss].md
      const uuidMatch = filename.match(/\[(.*?)\]/);
      const dateMatch = filename.match(/\[(\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2})\]/);
      
      if (uuidMatch && dateMatch) {
        const uuid = uuidMatch[1];
        const dateString = dateMatch[1];
        
        // Parse date for display
        const [year, month, day] = dateString.split('-');
        const date = new Date(year, month - 1, day);
        const displayDate = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        
        entries.push({
          id: uuid,
          date: displayDate,
          filename: filename,
          previewText: previewText,
          content: content
        });
      }
    });
    
    // Sort entries by date (newest first)
    entries.sort((a, b) => {
      const dateA = new Date(a.filename.match(/\[(\d{4}-\d{2}-\d{2})/)[1]);
      const dateB = new Date(b.filename.match(/\[(\d{4}-\d{2}-\d{2})/)[1]);
      return dateB - dateA;
    });
    
    event.reply('entries-loaded', { entries });
  });
});

// Listen for load entry event
ipcMain.on('load-entry', (event, data) => {
  const { filename } = data;
  const documentsPath = path.join(app.getPath('documents'), 'Freewrite');
  const filePath = path.join(documentsPath, filename);
  
  fs.readFile(filePath, 'utf-8', (err, content) => {
    if (err) {
      event.reply('entry-loaded', { success: false, error: err.message });
      return;
    }
    
    event.reply('entry-loaded', { success: true, content });
  });
});

// Listen for fullscreen toggle event
ipcMain.on('toggle-fullscreen', (event) => {
  if (mainWindow) {
    const isFullScreen = mainWindow.isFullScreen();
    mainWindow.setFullScreen(!isFullScreen);
  }
});

// Listen for request to get fullscreen state
ipcMain.on('get-fullscreen-state', (event) => {
  if (mainWindow) {
    event.reply('fullscreen-state', mainWindow.isFullScreen());
  }
});

// Handle opening external URLs
ipcMain.on('open-external-url', (event, data) => {
  const { url } = data;
  shell.openExternal(url);
});

// Listen for handle-escape event from renderer
ipcMain.on('handle-escape', (event) => {
  if (mainWindow) {
    if (mainWindow.isFullScreen()) {
      // If in fullscreen, first exit fullscreen
      mainWindow.setFullScreen(false);
    } else {
      // If not in fullscreen, quit the app
      app.quit();
    }
  }
});

// Listen for load-welcome-message event
ipcMain.on('load-welcome-message', (event) => {
  const defaultMdPath = path.join(__dirname, 'default.md');
  
  fs.readFile(defaultMdPath, 'utf-8', (err, content) => {
    if (err) {
      console.error('Error loading welcome message:', err);
      event.reply('welcome-message-loaded', { success: false, error: err.message });
      return;
    }
    
    event.reply('welcome-message-loaded', { success: true, content });
  });
}); 
