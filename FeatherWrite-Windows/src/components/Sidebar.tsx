import React, { useState, useEffect, useCallback } from 'react';
import { fileService } from '../services/fileService';
import type { Entry } from '../electron.d.ts'; // Use shared types
import '../styles/Sidebar.css';

interface SidebarProps {
  visible: boolean;
  onEntrySelect: (entry: Entry) => void;
  onClose: () => void;
}

const Sidebar: React.FC<SidebarProps> = ({ visible, onEntrySelect, onClose }) => {
  const [entries, setEntries] = useState<Entry[]>([]);
  const [selectedDate, setSelectedDate] = useState<Date>(new Date());
  const [isLoading, setIsLoading] = useState(false);

  const loadEntries = useCallback(async () => {
    setIsLoading(true);
    try {
      const dateEntries = await fileService.getEntriesByDate(selectedDate);
      setEntries(dateEntries);
    } catch (error) {
      console.error("Failed to load entries:", error);
      setEntries([]); // Clear entries on error
    } finally {
      setIsLoading(false);
    }
  }, [selectedDate]);

  useEffect(() => {
    if (visible) { // Only load when visible
      loadEntries();
      // Optional: Refresh entries periodically while visible
      // const interval = setInterval(loadEntries, 30000);
      // return () => clearInterval(interval);
    }
  }, [selectedDate, visible, loadEntries]);

  const handleDeleteEntry = async (e: React.MouseEvent, entryId: string) => {
    e.stopPropagation();
    if (window.confirm('Are you sure you want to delete this entry?')) {
      try {
        const success = await fileService.deleteEntry(entryId);
        if (success) {
          setEntries(prevEntries => prevEntries.filter(e => e.id !== entryId));
        }
      } catch (error) {
        console.error("Failed to delete entry:", error);
        // Show error to user?
      }
    }
  };

  const formatDate = (date: string) => {
    return new Date(date).toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  const changeDate = (days: number) => {
    const newDate = new Date(selectedDate);
    newDate.setDate(selectedDate.getDate() + days);
    setSelectedDate(newDate);
  };

  return (
    <div className={`sidebar ${visible ? 'visible' : ''}`}>
      <button className="close-sidebar" onClick={onClose}>×</button>
      
      <div className="date-navigation">
        <button onClick={() => changeDate(-1)} disabled={isLoading}>&lt;</button>
        <span>{selectedDate.toLocaleDateString()}</span>
        <button onClick={() => changeDate(1)} disabled={isLoading}>&gt;</button>
      </div>

      <div className="entries-list">
        {isLoading ? (
          <div className="loading-entries">Loading entries...</div>
        ) : entries.length === 0 ? (
          <div className="no-entries">No entries for this date</div>
        ) : (
          entries.map(entry => (
            <div
              key={entry.id}
              className="entry-preview"
              onClick={() => onEntrySelect(entry)}
            >
              <div className="entry-time">{formatDate(entry.createdAt)}</div>
              <div className="entry-text">{entry.preview}</div>
              <button 
                className="delete-entry"
                onClick={(e) => handleDeleteEntry(e, entry.id)}
              >
                Delete
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
};

export default Sidebar;