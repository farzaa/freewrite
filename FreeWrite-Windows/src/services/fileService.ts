export type { Entry } from '../electron.d.ts';
import type { Entry } from '../electron.d.ts';

class FileService {
  private generatePreview(content: string): string {
    const plainText = content.replace(/[#*`]/g, '').trim();
    return plainText.length > 150 ? plainText.slice(0, 147) + '...' : plainText;
  }

  async createEntry(content: string): Promise<Entry> {
    const entryData: Omit<Entry, 'id'> = {
      content,
      preview: this.generatePreview(content),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    return window.electron.fileStore.createEntry(entryData);
  }

  async updateEntry(id: string, content: string): Promise<Entry | null> {
    const updateData = {
      id,
      content,
      preview: this.generatePreview(content)
    };
    return window.electron.fileStore.updateEntry(updateData);
  }

  async getEntry(id: string): Promise<Entry | null> {
    return window.electron.fileStore.getEntry(id);
  }

  async getCurrentEntry(): Promise<Entry | null> {
    const id = await window.electron.fileStore.getCurrentEntryId();
    return id ? this.getEntry(id) : null;
  }

  async setCurrentEntry(id: string | null): Promise<void> {
    return window.electron.fileStore.setCurrentEntryId(id);
  }

  async getAllEntries(): Promise<Entry[]> {
    return window.electron.fileStore.getAllEntries();
  }

  async getEntriesByDate(date: Date): Promise<Entry[]> {
    const allEntries = await this.getAllEntries();
    const startOfDay = new Date(date);
    startOfDay.setHours(0, 0, 0, 0);
    
    const endOfDay = new Date(date);
    endOfDay.setHours(23, 59, 59, 999);

    return allEntries.filter(entry => {
      const entryDate = new Date(entry.createdAt);
      return entryDate >= startOfDay && entryDate <= endOfDay;
    });
  }

  async deleteEntry(id: string): Promise<boolean> {
    return window.electron.fileStore.deleteEntry(id);
  }

  async exportToMarkdown(id: string): Promise<string> {
    const entry = await this.getEntry(id);
    if (!entry) return '';
    
    const date = new Date(entry.createdAt);
    const header = `# Entry from ${date.toLocaleDateString()}\n\n`;
    return header + entry.content;
  }
}

export const fileService = new FileService();