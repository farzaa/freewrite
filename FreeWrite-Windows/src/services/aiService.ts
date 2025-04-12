import axios from 'axios';
import { settingsService } from './settingsService';

interface AIResponse {
  feedback: string;
  suggestions: string[];
  error?: string;
}

class AIService {
  private readonly OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions';
  private readonly ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
  private readonly GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';
  private isOnline: boolean = true;

  constructor() {
    // Monitor online status
    window.addEventListener('online', () => this.isOnline = true);
    window.addEventListener('offline', () => this.isOnline = false);
    this.isOnline = navigator.onLine;
  }

  async getAIFeedback(text: string, provider: 'chatgpt' | 'claude' | 'gemini' = 'chatgpt'): Promise<AIResponse> {
    if (!this.isOnline) {
      return {
        feedback: this.getOfflineFeedback(text),
        suggestions: this.getOfflineSuggestions(text),
        error: 'Working in offline mode'
      };
    }

    const apiKey = await settingsService.get('aiApiKey');
    const minCharCount = await settingsService.get('aiMinCharCount');

    if (!apiKey) {
      return {
        feedback: '',
        suggestions: [],
        error: 'AI API key not configured'
      };
    }

    if (text.length < minCharCount) {
      return {
        feedback: '',
        suggestions: [],
        error: `Text must be at least ${minCharCount} characters long`
      };
    }

    try {
      if (provider === 'chatgpt') {
        return await this.getOpenAIFeedback(text, apiKey);
      } else if (provider === 'claude') {
        return await this.getClaudeFeedback(text, apiKey);
      } else {
        return await this.getGeminiFeedback(text, apiKey);
      }
    } catch (error) {
      if (axios.isAxiosError(error)) {
        console.error('API Error Details:', error.response?.data);
        if (!error.response) {
          this.isOnline = false;
          return {
            feedback: this.getOfflineFeedback(text),
            suggestions: this.getOfflineSuggestions(text),
            error: 'Network error - switching to offline mode'
          };
        }
        return {
          feedback: '',
          suggestions: [],
          error: `API Error: ${error.response.status} - ${error.response.statusText || 'See console for details'}`
        };
      }
      console.error('Unexpected error:', error);
      return {
        feedback: '',
        suggestions: [],
        error: 'An unexpected error occurred'
      };
    }
  }

  private async getOpenAIFeedback(text: string, apiKey: string): Promise<AIResponse> {
    const response = await axios.post(
      this.OPENAI_API_URL,
      {
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: 'You are a helpful writing assistant. Provide constructive feedback and suggestions for improvement. Focus on clarity, structure, and engagement. Offer specific, actionable suggestions.'
          },
          {
            role: 'user',
            content: text
          }
        ],
        temperature: 0.7,
        max_tokens: 500
      },
      {
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        }
      }
    );

    const feedback = response.data.choices[0]?.message?.content || '';
    const suggestions = this.parseSuggestions(feedback);

    return { feedback, suggestions };
  }

  private async getClaudeFeedback(text: string, apiKey: string): Promise<AIResponse> {
    const response = await axios.post(
      this.ANTHROPIC_API_URL,
      {
        model: 'claude-3-5-sonnet-20240620',
        messages: [
          {
            role: 'user',
            content: `As a writing assistant, please analyze the following text and provide constructive feedback focused on clarity, structure, and engagement. Include specific, actionable suggestions for improvement:\n\n${text}`
          }
        ],
        temperature: 0.7,
        max_tokens: 500
      },
      {
        headers: {
          'X-API-Key': apiKey,
          'Content-Type': 'application/json',
          'anthropic-version': '2023-06-01'
        }
      }
    );

    const feedback = response.data.content[0]?.text || '';
    const suggestions = this.parseSuggestions(feedback);

    return { feedback, suggestions };
  }

  private async getGeminiFeedback(text: string, apiKey: string): Promise<AIResponse> {
    // Use the correct format for Gemini API
    const response = await axios.post(
      `${this.GEMINI_API_URL}?key=${apiKey}`,
      {
        contents: [
          {
            parts: [
              {
                text: `As a writing assistant, please analyze the following text and provide constructive feedback focused on clarity, structure, and engagement. Include specific, actionable suggestions for improvement:\n\n${text}`
              }
            ]
          }
        ],
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 500
        }
      },
      {
        headers: {
          'Content-Type': 'application/json'
        }
      }
    );

    try {
      // Handle Gemini response format
      const feedback = response.data.candidates?.[0]?.content?.parts?.[0]?.text || '';
      const suggestions = this.parseSuggestions(feedback);
      return { feedback, suggestions };
    } catch (error) {
      console.error('Error parsing Gemini response:', error, response.data);
      return {
        feedback: 'Error parsing Gemini response',
        suggestions: [],
        error: 'Failed to process Gemini response'
      };
    }
  }

  private parseSuggestions(feedback: string): string[] {
    const suggestions: string[] = [];
    const lines = feedback.split('\n');
    
    for (const line of lines) {
      // Match numbered lists (1., 2., etc.) or bullet points (-, *, •, ·, ◦, ▪, ▫)
      // Also match format where numbers/bullets might be surrounded by parentheses or followed by )
      if (
        line.match(/^\s*\d+[\.\)]\s+/) || 
        line.match(/^\s*[\(\[]?\d+[\)\]]\.?\s+/) || 
        line.match(/^\s*[-*•·◦▪▫]\s+/) ||
        line.match(/^\s*[a-z][\.\)]\s+/) || // Match a., b., c., etc.
        line.match(/^\s*[\(\[]?[a-z][\)\]]\.?\s+/) // Match (a), [a], etc.
      ) {
        // Clean up the suggestion by removing the list marker
        const cleanSuggestion = line.replace(/^\s*[\(\[]\d+[\)\]]\.?\s+|^\s*\d+[\.\)]\s+|^\s*[-*•·◦▪▫]\s+|^\s*[\(\[]?[a-z][\)\]]\.?\s+|^\s*[a-z][\.\)]\s+/, '').trim();
        if (cleanSuggestion.length > 0) {
          suggestions.push(cleanSuggestion);
        }
      }
    }

    // If no suggestions were parsed but feedback is substantial, create a single suggestion
    if (suggestions.length === 0 && feedback.length > 50) {
      // Look for paragraphs starting with words like "Consider", "Try", "I recommend", etc.
      const recommendationMatches = feedback.match(/(?:Consider|Try|I recommend|You should|You could|You might|It would be better to|I suggest)[^.!?]*[.!?]/g);
      
      if (recommendationMatches && recommendationMatches.length > 0) {
        suggestions.push(...recommendationMatches.map(s => s.trim()));
      }
    }

    return suggestions;
  }

  private getOfflineFeedback(text: string): string {
    const wordCount = text.trim().split(/\s+/).length;
    const sentenceCount = text.split(/[.!?]+/).filter(Boolean).length;
    const avgWordsPerSentence = wordCount / sentenceCount;

    let feedback = 'Offline Analysis:\n\n';
    feedback += `Your text contains ${wordCount} words in ${sentenceCount} sentences, `;
    feedback += `with an average of ${Math.round(avgWordsPerSentence)} words per sentence.\n\n`;

    if (avgWordsPerSentence > 25) {
      feedback += 'Consider breaking down some longer sentences for better readability.\n';
    }

    if (text.includes('  ')) {
      feedback += 'There are some double spaces in your text that could be corrected.\n';
    }

    const repeatedWords = this.findRepeatedWords(text);
    if (repeatedWords.length > 0) {
      feedback += `\nConsider varying your word choice. Frequently used words: ${repeatedWords.join(', ')}`;
    }

    return feedback;
  }

  private getOfflineSuggestions(text: string): string[] {
    const suggestions: string[] = [];
    const paragraphs = text.split('\n\n');

    if (paragraphs.length === 1) {
      suggestions.push('Consider breaking your text into smaller paragraphs for better readability');
    }

    if (text.split('\n').some(line => line.length > 100)) {
      suggestions.push('Some lines are quite long. Consider adding line breaks to improve readability');
    }

    return suggestions;
  }

  private findRepeatedWords(text: string): string[] {
    const words = text.toLowerCase().match(/\b\w+\b/g) || [];
    const wordCount: { [key: string]: number } = {};
    const commonWords = new Set(['the', 'be', 'to', 'of', 'and', 'a', 'in', 'that', 'have', 'i', 'it', 'for', 'not', 'on', 'with', 'he', 'as', 'you', 'do', 'at']);

    words.forEach(word => {
      if (!commonWords.has(word)) {
        wordCount[word] = (wordCount[word] || 0) + 1;
      }
    });

    return Object.entries(wordCount)
      .filter(([_, count]) => count > 3)
      .map(([word]) => word)
      .slice(0, 5);
  }
}

export const aiService = new AIService();