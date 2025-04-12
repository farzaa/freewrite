import { useState, useEffect, useCallback, useRef } from 'react';
import TextEditor from './components/TextEditor';
import Timer, { TimerHandle } from './components/Timer';
import Settings from './components/Settings';
import Sidebar from './components/Sidebar';
import Chat from './components/Chat';
import { fileService } from './services/fileService';
import { settingsService } from './services/settingsService';
import { aiService } from './services/aiService';
import { keyboardService } from './services/keyboardService';
import type { Entry, Settings as SettingsConfig } from './electron.d.ts'; // Use shared types
// Import fonts
import './fonts';
import './App.css';
import { v4 as uuidv4 } from 'uuid';

// Interface for chat messages
interface ChatMessage {
  id: string;
  content: string;
  suggestions: string[];
  timestamp: Date;
}

const App = () => {
  const [text, setText] = useState('');
  const [currentEntry, setCurrentEntry] = useState<Entry | null>(null);
  const [settings, setSettings] = useState<SettingsConfig | null>(null); // Initialize as null
  const [isLoading, setIsLoading] = useState(true); // Add loading state
  const [showSettings, setShowSettings] = useState(false);
  const [showSidebar, setShowSidebar] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [aiFeedback, setAiFeedback] = useState<{ feedback: string; suggestions: string[] }>({ feedback: '', suggestions: [] });
  const [aiError, setAiError] = useState<string>('');
  const [showChat, setShowChat] = useState(false);
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([]);
  
  const timerRef = useRef<TimerHandle>(null);

  // Load initial data asynchronously
  useEffect(() => {
    const loadInitialData = async () => {
      try {
        const initialSettings = await settingsService.getAll();
        setSettings(initialSettings);

        const entry = await fileService.getCurrentEntry();
        if (entry) {
          setCurrentEntry(entry);
          setText(entry.content);
        }
      } catch (error) {
        console.error("Failed to load initial data:", error);
        // Handle error appropriately, maybe show an error message
      } finally {
        setIsLoading(false);
      }
    };
    loadInitialData();
  }, []);

  const handleTextChange = (newText: string) => {
    setText(newText);
    // Auto-save is handled in TextEditor component
  };

  const addChatMessage = (content: string, suggestions: string[]) => {
    const newMessage: ChatMessage = {
      id: uuidv4(),
      content,
      suggestions,
      timestamp: new Date()
    };
    
    setChatMessages(prevMessages => [...prevMessages, newMessage]);
    
    // Show chat if it's not already visible
    if (!showChat) {
      setShowChat(true);
    }
  };

  const clearChatMessages = () => {
    setChatMessages([]);
  };

  const handleTimerEnd = () => {
    if (settings && text.length >= settings.aiMinCharCount) {
      requestAiFeedback();
    }
  };

  const requestAiFeedback = async () => {
    if (!settings) return; // Ensure settings are loaded
    const response = await aiService.getAIFeedback(text, settings.aiProvider);
    if (response.error) {
      setAiError(response.error);
    } else {
      // Add message to chat instead of showing in a popup
      addChatMessage(response.feedback, response.suggestions);
      
      // Also update the aiFeedback state for backward compatibility
      setAiFeedback({
        feedback: response.feedback,
        suggestions: response.suggestions
      });
      
      setAiError(''); // Clear previous errors
    }
  };

  const handleSettingsChange = async (newSettings: SettingsConfig) => {
    await settingsService.update(newSettings);
    setSettings(newSettings);
  };

  const handleEntrySelect = async (entry: Entry) => {
    await fileService.setCurrentEntry(entry.id);
    setCurrentEntry(entry);
    setText(entry.content);
    setShowSidebar(false);
  };

  const handleWindowControls = (action: 'minimize' | 'maximize' | 'close') => {
    const { minimize, maximize, close } = window.electron || {};
    
    switch (action) {
      case 'minimize':
        minimize?.();
        break;
      case 'maximize':
        maximize?.();
        break;
      case 'close':
        close?.();
        // Clear chat messages when app is closed
        clearChatMessages();
        break;
    }
  };

  const toggleFullscreen = useCallback(() => {
    window.electron?.toggleFullscreen();
  }, []);

  // Setup keyboard shortcuts and fullscreen listener
  useEffect(() => {
    if (isLoading) return; // Don't setup listeners until loaded

    // First, stop any previous keyboard service to avoid duplicates
    keyboardService.stop();
    
    // Start keyboard service
    keyboardService.start();

    // Register keyboard shortcuts
    keyboardService.registerShortcut({
      key: 'f',
      ctrlKey: true,
      preventDefault: true,
      action: toggleFullscreen
    });

    keyboardService.registerShortcut({
      key: 'Escape',
      preventDefault: true,
      action: () => {
        if (showSettings) setShowSettings(false);
        else if (showSidebar) setShowSidebar(false);
        else if (aiFeedback.feedback) setAiFeedback({ feedback: '', suggestions: [] });
        else if (aiError) setAiError('');
        else if (isFullscreen) toggleFullscreen();
      }
    });

    // Changed to save the current entry
    keyboardService.registerShortcut({
      key: 's',
      ctrlKey: true,
      preventDefault: true,
      action: async () => {
        if (currentEntry?.id && text) {
          try {
            await fileService.updateEntry(currentEntry.id, text);
            // Optionally show quick save confirmation
            window.electron?.showNotification('Entry Saved', 'Your entry has been saved successfully.');
          } catch (error) {
            console.error('Failed to save entry:', error);
          }
        } else if (text) {
          // Create new entry if there's text but no current entry
          try {
            const newEntry = await fileService.createEntry(text);
            setCurrentEntry(newEntry);
            // Optionally show save confirmation
            window.electron?.showNotification('New Entry Created', 'Your new entry has been saved.');
          } catch (error) {
            console.error('Failed to create new entry:', error);
          }
        }
      }
    });

    // Use Alt+S for settings instead of Ctrl+S
    keyboardService.registerShortcut({
      key: 's',
      altKey: true,
      preventDefault: true,
      action: () => setShowSettings(true)
    });

    keyboardService.registerShortcut({
      key: 'h',
      ctrlKey: true,
      preventDefault: true,
      action: () => setShowSidebar(true)
    });

    keyboardService.registerShortcut({
      key: 'Enter',
      ctrlKey: true,
      preventDefault: true,
      action: () => {
        if (settings && text.length >= settings.aiMinCharCount) {
          requestAiFeedback();
        }
      }
    });
    
    // Add shortcut for toggling chat visibility
    keyboardService.registerShortcut({
      key: 'c',
      ctrlKey: true,
      preventDefault: true,
      action: () => {
        setShowChat(prev => !prev);
      }
    });

    keyboardService.registerShortcut({
      key: 'r',
      ctrlKey: true,
      preventDefault: true,
      action: () => {
        timerRef.current?.resetTimer();
      }
    });

    window.electron?.getFullscreenState();
    window.electron?.onFullscreenChange((fullscreen) => {
      setIsFullscreen(fullscreen);
    });

    return () => {
      keyboardService.stop();
    };
  }, [isLoading, toggleFullscreen, showSettings, showSidebar, aiFeedback.feedback, aiError, text, settings, isFullscreen, currentEntry]);

  if (isLoading || !settings) {
    return <div className="loading-screen">Loading FeatherWrite...</div>;
  }

  return (
    <div className={`app ${isFullscreen ? 'fullscreen' : ''}`}>
      <div className="window-controls">
        <div className="window-controls-left">
          {isFullscreen && <button onClick={toggleFullscreen}>Exit Fullscreen</button>}
        </div>
        <div className="window-controls-right">
          <button onClick={() => handleWindowControls('minimize')} title="Minimize">─</button>
          <button onClick={() => handleWindowControls('maximize')} title="Maximize">□</button>
          <button onClick={() => handleWindowControls('close')} title="Close">×</button>
        </div>
      </div>

      <div className="toolbar">
        <button onClick={() => setShowSettings(true)} title="Settings (Alt+S)">Settings</button>
        <button onClick={() => setShowSidebar(true)} title="History (Ctrl+H)">History</button>
        <button onClick={() => setShowChat(prev => !prev)} title="AI Chat (Ctrl+C)">Chat</button>
      </div>

      <Timer
        ref={timerRef}
        initialMinutes={settings.timerDuration}
        onTimerEnd={handleTimerEnd}
      />

      <TextEditor
        key={currentEntry?.id || 'new'}
        onTextChange={handleTextChange}
        initialText={text}
        settings={settings}
      />

      {showSettings && (
        <Settings
          config={settings}
          onConfigChange={handleSettingsChange}
          onClose={() => setShowSettings(false)}
        />
      )}

      <Sidebar
        visible={showSidebar}
        onEntrySelect={handleEntrySelect}
        onClose={() => setShowSidebar(false)}
      />

      <Chat 
        isVisible={showChat}
        toggleVisibility={() => setShowChat(false)}
        messages={chatMessages}
        addMessage={addChatMessage}
        clearMessages={clearChatMessages}
      />

      {aiError && (
        <div className="ai-error">
          {aiError}
          <button onClick={() => setAiError('')}>×</button>
        </div>
      )}
    </div>
  );
};

export default App;
