import React, { useState, useEffect, useCallback, useRef } from 'react';
import { fileService } from '../services/fileService';
import type { Settings, Entry } from '../electron.d.ts'; // Use shared types
import { fontFamilies, availableFonts } from '../fonts';
import '../styles/TextEditor.css';

interface TextEditorProps {
  onTextChange?: (text: string) => void;
  initialText?: string;
  settings: Settings;
}

const TextEditor: React.FC<TextEditorProps> = ({ onTextChange, initialText = '', settings }) => {
  const [text, setText] = useState(initialText);
  const currentEntryRef = useRef<Entry | null>(null);
  const saveTimeoutRef = useRef<number | null>(null);
  const intervalRef = useRef<number | null>(null);
  const [randomFont, setRandomFont] = useState<string>('');

  // Fetch current entry when component mounts or initialText changes
  useEffect(() => {
    const fetchCurrentEntry = async () => {
      currentEntryRef.current = await fileService.getCurrentEntry();
      // If initialText is provided but doesn't match the fetched entry, update the state
      if (initialText !== text && currentEntryRef.current?.content === initialText) {
          setText(initialText);
      }
    };
    fetchCurrentEntry();
  }, [initialText]); // Rerun if initialText prop changes (e.g., loading a different entry)

  const saveText = useCallback(async () => {
    if (!text.trim()) return;

    try {
      const entryToSave = currentEntryRef.current;
      if (entryToSave) {
        const updatedEntry = await fileService.updateEntry(entryToSave.id, text);
        if (updatedEntry) currentEntryRef.current = updatedEntry; // Update ref if needed
      } else {
        const newEntry = await fileService.createEntry(text);
        currentEntryRef.current = newEntry; // Store the newly created entry
      }
    } catch (error) {
        console.error("Failed to save entry:", error);
    }
  }, [text]);

  // Auto-save on interval
  useEffect(() => {
    if (intervalRef.current) clearInterval(intervalRef.current);
    intervalRef.current = window.setInterval(saveText, settings.autoSaveInterval * 1000);
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [saveText, settings.autoSaveInterval]);

  // Debounced save on text change
  useEffect(() => {
    if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current);
    saveTimeoutRef.current = window.setTimeout(() => {
      saveText();
    }, 1500); // Slightly longer debounce

    return () => {
      if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current);
    };
  }, [text, saveText]);

  // Set a random font when font setting is 'Random' or component mounts
  useEffect(() => {
    if (settings.font === 'Random') {
      // Filter out 'Random' and select a random font from the remaining options
      const fontsWithoutRandom = availableFonts.filter(font => font !== 'Random');
      const randomIndex = Math.floor(Math.random() * fontsWithoutRandom.length);
      setRandomFont(fontsWithoutRandom[randomIndex]);
    }
  }, [settings.font]);

  const getFontFamily = () => {
    if (settings.font === 'Random') {
      return fontFamilies[randomFont] || fontFamilies['Lato']; // Fallback to Lato
    }
    return fontFamilies[settings.font] || fontFamilies['Lato']; // Fallback to Lato
  };

  return (
    <div className="text-editor-container">
      <textarea
        className="text-editor"
        value={text}
        onChange={(e) => {
          setText(e.target.value);
          onTextChange?.(e.target.value);
        }}
        placeholder="Start writing..."
        spellCheck="false"
        autoFocus
        style={{
          fontFamily: getFontFamily(),
          fontSize: `${settings.fontSize}px`,
          lineHeight: settings.lineSpacing,
        }}
      />
    </div>
  );
};

export default TextEditor;