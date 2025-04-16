const { ipcRenderer } = require('electron');

// DOM Elements
const editor = document.getElementById('editor');
const placeholder = document.getElementById('placeholder');
const fontButton = document.getElementById('font-btn');
const fontSizeButton = document.getElementById('font-size-btn');
const systemFontButton = document.getElementById('system-font-btn');
const serifFontButton = document.getElementById('serif-font-btn');
const randomFontButton = document.getElementById('random-font-btn');
const timerButton = document.getElementById('timer-btn');
const themeButton = document.getElementById('theme-btn');
const fullscreenButton = document.getElementById('fullscreen-btn');
const newEntryButton = document.getElementById('new-entry-btn');
const chatButton = document.getElementById('chat-btn');
const historyButton = document.getElementById('history-btn');
const entriesList = document.getElementById('entries-list');
const fontSizePopup = document.getElementById('font-size-popup');
const sidebar = document.getElementById('sidebar');
const closeSidebarButton = document.getElementById('close-sidebar-btn');

// Create audio object for button click sound
const buttonSound = new Audio('https://pomofocus.io/audios/general/button.wav');

// State variables
let selectedFont = 'Lato-Regular';
let fontSize = 18;
let timeRemaining = 900; // 15 minutes in seconds
let timerIsRunning = false;
let timerInterval = null;
let entries = [];
let selectedEntry = null;
let showingChatMenu = false;
let placeholderOptions = [
    "Begin writing",
    "Pick a thought and go",
    "Start typing",
    "What's on your mind",
    "Just start",
    "Type your first thought",
    "Start with one sentence",
    "Just say it"
];

// AI Chat prompts
const aiChatPrompt = `below is my journal entry. wyt? talk through it with me like a friend. don't therpaize me and give me a whole breakdown, don't repeat my thoughts with headings. really take all of this, and tell me back stuff truly as if you're an old homie.

Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot. format with markdown headings if needed.

do not just go through every single thing i say, and say it back to me. you need to proccess everythikng is say, make connections i don't see it, and deliver it all back to me as a story that makes me feel what you think i wanna feel. thats what the best therapists do.

ideally, you're style/tone should sound like the user themselves. it's as if the user is hearing their own tone but it should still feel different, because you have different things to say and don't just repeat back they say.

else, start by saying, "hey, thanks for showing me this. my thoughts:"
    
my entry:`;

const claudePrompt = `Take a look at my journal entry below. I'd like you to analyze it and respond with deep insight that feels personal, not clinical.
Imagine you're not just a friend, but a mentor who truly gets both my tech background and my psychological patterns. I want you to uncover the deeper meaning and emotional undercurrents behind my scattered thoughts.
Keep it casual, dont say yo, help me make new connections i don't see, comfort, validate, challenge, all of it. dont be afraid to say a lot. format with markdown headings if needed.
Use vivid metaphors and powerful imagery to help me see what I'm really building. Organize your thoughts with meaningful headings that create a narrative journey through my ideas.
Don't just validate my thoughts - reframe them in a way that shows me what I'm really seeking beneath the surface. Go beyond the product concepts to the emotional core of what I'm trying to solve.
Be willing to be profound and philosophical without sounding like you're giving therapy. I want someone who can see the patterns I can't see myself and articulate them in a way that feels like an epiphany.
Start with 'hey, thanks for showing me this. my thoughts:' and then use markdown headings to structure your response.

Here's my journal entry:`;

// Available fonts
const fonts = {
    lato: 'Lato-Regular',
    system: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
    serif: 'Times New Roman, serif',
    random: [
        'Noto Serif Kannada',
        'Georgia',
        'Palatino',
        'Garamond', 
        'Bookman',
        'Courier New'
    ]
};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    loadEntries();
    initializeEventListeners();
    initializeTheme();
    
    // Set random placeholder
    placeholder.textContent = placeholderOptions[Math.floor(Math.random() * placeholderOptions.length)];
    
    // Apply initial font and size
    setFont('random'); // Set to random initially to match screenshot
    setFontSize(18);
    
    // Hide placeholder since we have initial text
    updatePlaceholderVisibility();
    
    // Get initial fullscreen state
    ipcRenderer.send('get-fullscreen-state');
});

// Listen for fullscreen state response
ipcRenderer.on('fullscreen-state', (event, isFullScreen) => {
    if (isFullScreen) {
        document.body.classList.add('fullscreen');
        fullscreenButton.textContent = 'Exit Fullscreen';
    } else {
        document.body.classList.remove('fullscreen');
        fullscreenButton.textContent = 'Fullscreen';
    }
});

// Initialize event listeners
function initializeEventListeners() {
    // Editor events
    editor.addEventListener('input', () => {
        updatePlaceholderVisibility();
        saveCurrentEntry();
    });
    
    editor.addEventListener('focus', () => {
        updatePlaceholderVisibility();
    });
    
    editor.addEventListener('blur', () => {
        saveCurrentEntry(); // Save when editor loses focus
    });
    
    // Font size button
    fontSizeButton.addEventListener('click', (e) => {
        togglePopup(fontSizePopup);
    });
    
    // Font buttons
    fontButton.addEventListener('click', () => setFont('lato'));
    systemFontButton.addEventListener('click', () => setFont('system'));
    serifFontButton.addEventListener('click', () => setFont('serif'));
    randomFontButton.addEventListener('click', () => setFont('random'));
    
    // Font size options
    document.querySelectorAll('.size-option').forEach(option => {
        option.addEventListener('click', () => {
            const size = parseInt(option.getAttribute('data-size'));
            setFontSize(size);
            fontSizePopup.classList.remove('show');
        });
    });
    
    // Timer button
    timerButton.addEventListener('click', toggleTimer);
    
    // Fullscreen button
    fullscreenButton.addEventListener('click', toggleFullscreen);
    
    // New entry button
    newEntryButton.addEventListener('click', createNewEntry);
    
    // History button
    historyButton.addEventListener('click', toggleSidebar);
    
    // Close sidebar button
    closeSidebarButton.addEventListener('click', toggleSidebar);
    
    // Chat button
    chatButton.addEventListener('click', () => {
        // Toggle chat menu popup
        toggleChatMenu();
    });
    
    // Click outside popups to close
    document.addEventListener('click', (e) => {
        if (!fontSizeButton.contains(e.target) && !fontSizePopup.contains(e.target)) {
            fontSizePopup.classList.remove('show');
        }
    });
    
    // Add escape key handler
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            // Close any open popups first
            const chatPopup = document.querySelector('.chat-popup');
            if (chatPopup) {
                document.body.removeChild(chatPopup);
                return;
            }
            
            if (fontSizePopup.classList.contains('show')) {
                fontSizePopup.classList.remove('show');
                return;
            }
            
            if (!sidebar.classList.contains('hidden')) {
                sidebar.classList.add('hidden');
                return;
            }
            
            // Let the main process handle exiting fullscreen or closing the app
            ipcRenderer.send('handle-escape');
        }
    });
    
    // Theme button
    themeButton.addEventListener('click', toggleTheme);
    
    // Add window unload handler to save before closing
    window.addEventListener('beforeunload', () => {
        saveCurrentEntry();
    });
    
    // Save periodically (every 30 seconds)
    setInterval(saveCurrentEntry, 30000);
}

// Update placeholder visibility
function updatePlaceholderVisibility() {
    if (editor.value.trim() === '') {
        placeholder.style.display = 'block';
    } else {
        placeholder.style.display = 'none';
    }
}

// Toggle popup display
function togglePopup(popup) {
    popup.classList.toggle('show');
}

// Set font
function setFont(fontType) {
    // Deselect previous font
    fontButton.style.fontWeight = 'normal';
    systemFontButton.style.fontWeight = 'normal';
    serifFontButton.style.fontWeight = 'normal';
    randomFontButton.style.fontWeight = 'normal';
    
    if (fontType === 'lato') {
        selectedFont = fonts.lato;
        fontButton.style.fontWeight = 'bold';
    } else if (fontType === 'system') {
        selectedFont = fonts.system;
        systemFontButton.style.fontWeight = 'bold';
    } else if (fontType === 'serif') {
        selectedFont = fonts.serif;
        serifFontButton.style.fontWeight = 'bold';
    } else if (fontType === 'random') {
        const randomFont = fonts.random[Math.floor(Math.random() * fonts.random.length)];
        selectedFont = randomFont;
        randomFontButton.style.fontWeight = 'bold';
        randomFontButton.textContent = `Random [${randomFont}]`;
    }
    
    editor.style.fontFamily = selectedFont;
    placeholder.style.fontFamily = selectedFont;
}

// Set font size
function setFontSize(size) {
    fontSize = size;
    fontSizeButton.textContent = `${size}px`;
    editor.style.fontSize = `${size}px`;
    editor.style.lineHeight = '1.6';
    placeholder.style.fontSize = `${size}px`;
}

// Toggle timer
function toggleTimer() {
    // Play button sound
    buttonSound.play().catch(err => console.log('Error playing sound:', err));
    
    if (timerIsRunning) {
        // Stop timer
        clearInterval(timerInterval);
        timerIsRunning = false;
        document.body.classList.remove('timer-running');
        timerButton.textContent = formatTime(timeRemaining);
    } else {
        // Start timer
        timerIsRunning = true;
        document.body.classList.add('timer-running');
        
        timerInterval = setInterval(() => {
            timeRemaining--;
            timerButton.textContent = formatTime(timeRemaining);
            
            if (timeRemaining <= 0) {
                clearInterval(timerInterval);
                timerIsRunning = false;
                document.body.classList.remove('timer-running');
                document.body.classList.add('timer-complete');
                
                // Reset timer after 5 seconds
                setTimeout(() => {
                    timeRemaining = 900;
                    timerButton.textContent = '15:00';
                    document.body.classList.remove('timer-complete');
                }, 5000);
            }
        }, 1000);
    }
}

// Format time for display
function formatTime(seconds) {
    const minutes = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${minutes}:${secs.toString().padStart(2, '0')}`;
}

// Toggle fullscreen
function toggleFullscreen() {
    ipcRenderer.send('toggle-fullscreen');
    
    document.body.classList.toggle('fullscreen');
    if (document.body.classList.contains('fullscreen')) {
        fullscreenButton.textContent = 'Exit Fullscreen';
    } else {
        fullscreenButton.textContent = 'Fullscreen';
    }
}

// Toggle sidebar
function toggleSidebar() {
    sidebar.classList.toggle('hidden');
}

// Load entries from main process
function loadEntries() {
    ipcRenderer.send('load-entries');
    
    ipcRenderer.on('entries-loaded', (event, data) => {
        entries = data.entries || [];
        renderEntries();
        
        // If there are entries, load the first one
        if (entries.length > 0) {
            loadEntry(entries[0]);
        } else {
            // Create a new entry if there are none
            createNewEntry();
        }
    });
}

// Render entries in the sidebar
function renderEntries() {
    entriesList.innerHTML = '';
    
    entries.forEach(entry => {
        const entryItem = document.createElement('div');
        entryItem.className = 'entry-item';
        if (selectedEntry && entry.id === selectedEntry.id) {
            entryItem.classList.add('selected');
        }
        
        entryItem.innerHTML = `
            <div class="entry-date">${entry.date}</div>
            <div class="entry-preview">${entry.previewText || 'Empty entry'}</div>
            <div class="entry-delete">×</div>
        `;
        
        entryItem.addEventListener('click', (e) => {
            if (!e.target.classList.contains('entry-delete')) {
                loadEntry(entry);
                sidebar.classList.add('hidden');
            }
        });
        
        // Delete button
        const deleteButton = entryItem.querySelector('.entry-delete');
        deleteButton.addEventListener('click', (e) => {
            e.stopPropagation();
            // Implement delete functionality
            if (confirm('Are you sure you want to delete this entry?')) {
                // Delete entry logic
                entries = entries.filter(e => e.id !== entry.id);
                renderEntries();
                
                if (selectedEntry && selectedEntry.id === entry.id) {
                    if (entries.length > 0) {
                        loadEntry(entries[0]);
                    } else {
                        createNewEntry();
                    }
                }
            }
        });
        
        entriesList.appendChild(entryItem);
    });
}

// Load an entry into the editor
function loadEntry(entry) {
    // Save current entry before loading new one
    if (selectedEntry && selectedEntry.id !== entry.id) {
        saveCurrentEntry();
    }
    
    selectedEntry = entry;
    
    // Load content
    if (entry.content) {
        editor.value = entry.content;
    } else {
        ipcRenderer.send('load-entry', { filename: entry.filename });
    }
    
    // Update UI
    updatePlaceholderVisibility();
    renderEntries();
}

// Receive loaded entry from main process
ipcRenderer.on('entry-loaded', (event, data) => {
    if (data.success) {
        editor.value = data.content;
        updatePlaceholderVisibility();
    }
});

// Create a new entry
function createNewEntry() {
    // Generate ID
    const id = generateUUID();
    
    // Generate filename with date
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');
    
    const dateString = `${year}-${month}-${day}-${hours}-${minutes}-${seconds}`;
    const filename = `[${id}]-[${dateString}].md`;
    
    // Create entry object
    const entry = {
        id: id,
        date: now.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
        filename: filename,
        previewText: '',
        content: '\n\n' // Start with two newlines
    };
    
    // Add to entries list
    entries.unshift(entry);
    
    // Load the new entry
    loadEntry(entry);
    
    // If this is the first entry, load the welcome message from default.md
    if (entries.length === 1) {
        // Request the welcome message from main process
        ipcRenderer.send('load-welcome-message');
    } else {
        // Clear editor
        editor.value = '\n\n';
    }
    
    updatePlaceholderVisibility();
    
    // Set focus to editor
    editor.focus();
}

// Receive welcome message from main process
ipcRenderer.on('welcome-message-loaded', (event, data) => {
    if (data.success) {
        editor.value = '\n\n' + data.content;
        updatePlaceholderVisibility();
        
        // Save the entry with welcome message
        saveCurrentEntry();
    }
});

// Save current entry
function saveCurrentEntry() {
    if (!selectedEntry) return;
    
    console.log('Saving entry:', selectedEntry.filename); // Debug log
    
    // Update preview text
    const content = editor.value;
    const preview = content.replace(/\n/g, ' ').trim();
    const truncated = preview.length > 30 ? preview.substring(0, 30) + '...' : preview;
    
    selectedEntry.previewText = truncated;
    selectedEntry.content = content; // Cache the content
    
    // Save to file
    ipcRenderer.send('save-entry', {
        content: content,
        filename: selectedEntry.filename
    });
    
    // Update UI
    renderEntries();
}

// Generate UUID
function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        const r = Math.random() * 16 | 0;
        const v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

// Show custom alert
function showCustomAlert(message, callback) {
    const overlay = document.createElement('div');
    overlay.className = 'custom-alert-overlay';
    
    const alertBox = document.createElement('div');
    alertBox.className = 'custom-alert';
    
    alertBox.innerHTML = `
        <div class="custom-alert-message">${message}</div>
        <button class="custom-alert-button">OK</button>
    `;
    
    document.body.appendChild(overlay);
    document.body.appendChild(alertBox);
    
    const okButton = alertBox.querySelector('.custom-alert-button');
    
    const closeAlert = () => {
        document.body.removeChild(overlay);
        document.body.removeChild(alertBox);
        if (callback) callback();
    };
    
    okButton.addEventListener('click', closeAlert);
    okButton.focus();
    
    // Also close on Enter or Escape
    alertBox.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === 'Escape') {
            e.preventDefault();
            closeAlert();
        }
    });
}

// Toggle chat menu
function toggleChatMenu() {
    console.log('Chat menu toggled');
    
    // Check if popup already exists and remove it if it does
    const existingPopup = document.querySelector('.chat-popup');
    if (existingPopup) {
        console.log('Removing existing popup');
        document.body.removeChild(existingPopup);
        console.log('Setting focus to editor after removing popup');
        editor.focus();
        return; // Exit function to toggle off
    }
    
    // Check if entry is suitable for chat
    const entryText = editor.value.trim();
    
    if (entryText.startsWith("Hi. My name is Farza.") || 
        entryText.startsWith("hi. my name is farza.")) {
        showCustomAlert("Sorry, you can't chat with the guide. Please write your own entry.", () => {
            console.log('Setting focus after Farza alert');
            editor.focus();
            // Force cursor to end
            const len = editor.value.length;
            editor.setSelectionRange(len, len);
        });
        return;
    }
    
    if (entryText.length < 350) {
        showCustomAlert("Please free write for at minimum 5 minutes first. Then click this. Trust.", () => {
            console.log('Setting focus after length alert');
            editor.focus();
            // Force cursor to end
            const len = editor.value.length;
            editor.setSelectionRange(len, len);
        });
        return;
    }
    
    // Create and show popup
    const popup = document.createElement('div');
    popup.className = 'chat-popup';
    popup.setAttribute('tabindex', '-1'); // Prevent popup from being focusable
    popup.innerHTML = `
        <div class="chat-popup-content">
            <button id="chatgpt-btn" class="chat-option" tabindex="0">ChatGPT</button>
            <div class="chat-divider"></div>
            <button id="claude-btn" class="chat-option" tabindex="0">Claude</button>
        </div>
    `;
    
    // Position popup above the chat button
    const rect = chatButton.getBoundingClientRect();
    popup.style.position = 'absolute';
    
    // Add to DOM first so we can measure it
    document.body.appendChild(popup);
    console.log('Popup added to DOM');
    
    // Always position popup above the button
    popup.style.top = `${rect.top - popup.offsetHeight - 10}px`;
    popup.style.left = `${rect.left}px`;
    
    // Add event listeners
    document.getElementById('chatgpt-btn').addEventListener('click', (e) => {
        console.log('ChatGPT button clicked');
        e.preventDefault();
        e.stopPropagation();
        document.body.removeChild(popup);
        editor.focus();
        openChatGPT();
    });
    
    document.getElementById('claude-btn').addEventListener('click', (e) => {
        console.log('Claude button clicked');
        e.preventDefault();
        e.stopPropagation();
        document.body.removeChild(popup);
        editor.focus();
        openClaude();
    });
    
    // Close when clicking outside
    const closePopup = (e) => {
        if (!popup.contains(e.target) && e.target !== chatButton) {
            console.log('Closing popup from outside click');
            e.preventDefault();
            e.stopPropagation();
            document.body.removeChild(popup);
            document.removeEventListener('click', closePopup);
            
            requestAnimationFrame(() => {
                console.log('Attempting to restore focus after popup close');
                editor.focus();
                // Force the cursor to the end
                const len = editor.value.length;
                editor.setSelectionRange(len, len);
            });
        }
    };
    
    // Delay adding the event listener to prevent immediate closure
    setTimeout(() => {
        document.addEventListener('click', closePopup);
    }, 100);
    
    // Ensure editor maintains focus
    console.log('Setting initial focus to editor');
    editor.focus();
}

// Open ChatGPT with the journal entry
function openChatGPT() {
    const trimmedText = editor.value.trim();
    const fullText = aiChatPrompt + "\n\n" + trimmedText;
    
    // Use Electron's shell to open the URL
    ipcRenderer.send('open-external-url', {
        url: 'https://chat.openai.com/?m=' + encodeURIComponent(fullText)
    });
}

// Open Claude with the journal entry
function openClaude() {
    const trimmedText = editor.value.trim();
    const fullText = claudePrompt + "\n\n" + trimmedText;
    
    // Use Electron's shell to open the URL
    ipcRenderer.send('open-external-url', {
        url: 'https://claude.ai/new?q=' + encodeURIComponent(fullText)
    });
}

// Theme functions
function initializeTheme() {
    const savedTheme = localStorage.getItem('theme') || 'light';
    document.documentElement.setAttribute('data-theme', savedTheme);
    updateThemeButton(savedTheme);
}

function toggleTheme() {
    const currentTheme = document.documentElement.getAttribute('data-theme');
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    
    document.documentElement.setAttribute('data-theme', newTheme);
    localStorage.setItem('theme', newTheme);
    updateThemeButton(newTheme);
}

function updateThemeButton(theme) {
    themeButton.textContent = theme === 'dark' ? 'Light Mode' : 'Dark Mode';
}

// Also add focus tracking to the editor globally
editor.addEventListener('focus', () => {
    console.log('Editor focused (global)');
});

editor.addEventListener('blur', () => {
    console.log('Editor lost focus (global)');
    console.log('Active element:', document.activeElement);
}); 