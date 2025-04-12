import React, { useState, useEffect } from 'react';
import { settingsService } from '../services/settingsService'; // Import the refactored service
import type { Settings as SettingsConfig } from '../electron.d.ts'; // Use shared types
import { availableFonts } from '../fonts';
import '../styles/Settings.css';
import '../styles/fonts.css';

interface SettingsProps {
  config: SettingsConfig;
  onConfigChange: (newConfig: SettingsConfig) => void; // Keep this prop for App state update
  onClose: () => void;
}

const Settings: React.FC<SettingsProps> = ({ config, onConfigChange, onClose }) => {
  // Local state still useful for immediate UI feedback
  const [localConfig, setLocalConfig] = useState<SettingsConfig>(config);
  const [activeTab, setActiveTab] = useState<'general' | 'shortcuts' | 'ai'>('general');

  // Update local state if the config prop changes from App.tsx (e.g., after reset)
  useEffect(() => {
    setLocalConfig(config);
  }, [config]);

  const fontSizes = Array.from({ length: 11 }, (_, i) => i + 16); // 16-26px
  const lineSpacings = [1, 1.2, 1.4, 1.6, 1.8, 2];

  const shortcuts = [
    { key: 'Ctrl + S', description: 'Save current entry' },
    { key: 'Alt + S', description: 'Open settings' },
    { key: 'Ctrl + H', description: 'Toggle history sidebar' },
    { key: 'Ctrl + Enter', description: 'Request AI feedback' },
    { key: 'Ctrl + R', description: 'Reset timer' },
    { key: 'Escape', description: 'Close dialogs' },
  ];

  // Handle change locally and then call the async service update
  const handleChange = async (key: keyof SettingsConfig, value: string | number | boolean) => {
    const updatedConfig = { ...localConfig, [key]: value };
    setLocalConfig(updatedConfig); // Update local state immediately

    try {
      // Persist the change using the async service
      await settingsService.update({ [key]: value });
      // Optionally call onConfigChange to update App state if needed immediately after save
      // onConfigChange(updatedConfig); // Or fetch fresh config from main process
    } catch (error) {
      console.error("Failed to update setting:", key, error);
      // Handle error - maybe revert local state or show message
    }
  };

  // Handle closing - ensure App state reflects the latest persisted state
  const handleClose = async () => {
      try {
          const latestConfig = await settingsService.getAll();
          onConfigChange(latestConfig); // Update App state with latest from main process
      } catch (error) {
          console.error("Failed to fetch latest settings on close:", error);
          // Fallback to local state if fetch fails?
          onConfigChange(localConfig);
      }
      onClose();
  };

  // Helper to convert font name to CSS class name
  const getFontClass = (fontName: string): string => {
    return fontName.toLowerCase().replace(/\s+/g, '-');
  };

  return (
    <div className="settings-overlay">
      <div className="settings-panel">
        {/* Use handleClose instead of onClose directly */}
        <button className="close-button" onClick={handleClose}>×</button>
        <h2>Settings</h2>

        <div className="settings-tabs">
          <button 
            className={activeTab === 'general' ? 'active' : ''} 
            onClick={() => setActiveTab('general')}
          >
            General
          </button>
          <button 
            className={activeTab === 'ai' ? 'active' : ''} 
            onClick={() => setActiveTab('ai')}
          >
            AI Integration
          </button>
          <button 
            className={activeTab === 'shortcuts' ? 'active' : ''} 
            onClick={() => setActiveTab('shortcuts')}
          >
            Keyboard Shortcuts
          </button>
        </div>

        {activeTab === 'general' ? (
          <>
            <div className="setting-group">
              <label>
                Font
                <select 
                  value={localConfig.font}
                  onChange={(e) => handleChange('font', e.target.value)}
                >
                  {availableFonts.map(font => (
                    <option key={font} value={font}>
                      {font}
                    </option>
                  ))}
                </select>
              </label>
              <div className="font-preview-container">
                {localConfig.font !== 'Random' ? (
                  <div className={`font-preview ${getFontClass(localConfig.font)}`}>
                    Sample text in {localConfig.font}
                  </div>
                ) : (
                  <div className="font-preview">
                    A random font will be chosen each time
                  </div>
                )}
              </div>
            </div>

            <div className="setting-group">
              <label>
                Font Size
                <select 
                  value={localConfig.fontSize}
                  onChange={(e) => handleChange('fontSize', Number(e.target.value))}
                >
                  {fontSizes.map(size => (
                    <option key={size} value={size}>{size}px</option>
                  ))}
                </select>
              </label>
            </div>

            <div className="setting-group">
              <label>
                Line Spacing
                <select 
                  value={localConfig.lineSpacing}
                  onChange={(e) => handleChange('lineSpacing', Number(e.target.value))}
                >
                  {lineSpacings.map(spacing => (
                    <option key={spacing} value={spacing}>{spacing}</option>
                  ))}
                </select>
              </label>
            </div>

            <div className="setting-group">
              <label>
                Timer Duration (minutes)
                <input 
                  type="number"
                  min="1"
                  max="60"
                  value={localConfig.timerDuration}
                  onChange={(e) => handleChange('timerDuration', Number(e.target.value))}
                />
              </label>
            </div>

            <div className="setting-group">
              <label>
                Auto-save Interval (seconds)
                <input 
                  type="number"
                  min="5"
                  max="60"
                  value={localConfig.autoSaveInterval}
                  onChange={(e) => handleChange('autoSaveInterval', Number(e.target.value))}
                />
              </label>
            </div>
          </>
        ) : activeTab === 'shortcuts' ? (
          <div className="shortcuts-list">
            {shortcuts.map(({ key, description }) => (
              <div key={key} className="shortcut-item">
                <kbd>{key}</kbd>
                <span>{description}</span>
              </div>
            ))}
          </div>
        ) : (
          <div className="ai-settings">
            <div className="setting-group">
              <label>
                AI Provider
                <select
                  value={localConfig.aiProvider}
                  onChange={(e) => handleChange('aiProvider', e.target.value as 'chatgpt' | 'claude' | 'gemini')}
                >
                  <option value="chatgpt">GPT-4o Mini (OpenAI)</option>
                  <option value="claude">Claude 3.5 Sonnet (Anthropic)</option>
                  <option value="gemini">Gemini 2.0 Flash (Google)</option>
                </select>
              </label>
            </div>

            <div className="setting-group">
              <label>
                API Key
                <input
                  type="password"
                  value={localConfig.aiApiKey || ''}
                  onChange={(e) => handleChange('aiApiKey', e.target.value)}
                  placeholder={localConfig.aiApiKey ? '••••••••' : 'Enter API key'}
                />
              </label>
            </div>

            <div className="setting-group">
              <label>
                Minimum Character Count
                <input
                  type="number"
                  min="100"
                  max="1000"
                  value={localConfig.aiMinCharCount}
                  onChange={(e) => handleChange('aiMinCharCount', Number(e.target.value))}
                />
              </label>
              <small className="setting-description">
                Minimum number of characters required before AI feedback is available
              </small>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default Settings;