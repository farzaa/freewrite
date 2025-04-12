import React, { useEffect, useRef, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import '../styles/Chat.css';

interface ChatMessage {
  id: string;
  content: string;
  suggestions: string[];
  timestamp: Date;
}

interface ChatProps {
  isVisible: boolean;
  toggleVisibility: () => void;
  addMessage: (content: string, suggestions: string[]) => void;
  messages: ChatMessage[];
  clearMessages: () => void;
}

const Chat: React.FC<ChatProps> = ({ 
  isVisible, 
  toggleVisibility, 
  messages, 
  clearMessages 
}) => {
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const [isMinimized, setIsMinimized] = useState(false);

  // Scroll to bottom when new messages are added
  useEffect(() => {
    if (isVisible && !isMinimized) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages, isVisible, isMinimized]);

  // Ensure chat is expanded when new messages arrive
  useEffect(() => {
    if (messages.length > 0 && isVisible) {
      setIsMinimized(false);
    }
  }, [messages, isVisible]);

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  // Function to format text with proper line breaks
  const formatText = (text: string): string => {
    // Convert double line breaks to paragraphs
    // Ensure single line breaks are preserved
    return text
      .replace(/\n\n+/g, '\n\n')
      .trim();
  };

  type MessageProps = {
    message: ChatMessage;
  };

  const MessageItem: React.FC<MessageProps> = ({ message }) => {
    return (
      <div className="message">
        <div className="message-header">
          <span className="message-time">{formatTime(message.timestamp)}</span>
        </div>
        <div className="message-content">
          <div className="markdown-content">
            <ReactMarkdown>{formatText(message.content)}</ReactMarkdown>
          </div>
          {message.suggestions.length > 0 && (
            <div className="message-suggestions">
              <h4>Suggestions:</h4>
              <ul>
                {message.suggestions.map((suggestion, index) => (
                  <li key={index}>{suggestion}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
      </div>
    );
  };

  if (!isVisible) return null;

  return (
    <div className={`chat-container ${isMinimized ? 'minimized' : ''}`}>
      <div className="chat-header">
        <h3>AI Chat</h3>
        <div className="chat-controls">
          <button 
            className="minimize-button" 
            onClick={() => setIsMinimized(!isMinimized)}
            title={isMinimized ? "Expand" : "Minimize"}
          >
            {isMinimized ? '□' : '–'}
          </button>
          <button 
            className="close-button" 
            onClick={toggleVisibility}
            title="Close Chat"
          >
            ×
          </button>
        </div>
      </div>
      
      {!isMinimized && (
        <>
          <div className="chat-messages">
            {messages.length === 0 ? (
              <div className="empty-chat">
                <p>No AI feedback yet. Write some text and press Ctrl+Enter to get feedback.</p>
              </div>
            ) : (
              messages.map((message) => (
                <MessageItem key={message.id} message={message} />
              ))
            )}
            <div ref={messagesEndRef} />
          </div>
          
          <div className="chat-actions">
            <button 
              className="clear-button" 
              onClick={clearMessages}
              disabled={messages.length === 0}
            >
              Clear History
            </button>
          </div>
        </>
      )}
    </div>
  );
};

export default Chat; 