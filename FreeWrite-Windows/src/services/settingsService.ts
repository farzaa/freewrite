// Re-export types (consider moving to a shared types file)
export type { Settings } from '../electron.d.ts';
import type { Settings } from '../electron.d.ts';

class SettingsService {
  // No local store needed anymore

  async getAll(): Promise<Settings> {
    return window.electron.settingsStore.getAll();
  }

  async get<K extends keyof Settings>(key: K): Promise<Settings[K]> {
    // Use type assertion on the key and cast the result to the specific generic type
    const value = await window.electron.settingsStore.get(key as keyof Settings);
    // Cast the potentially broader type from IPC to the specific expected type
    return value as Settings[K];
  }

  async set<K extends keyof Settings>(key: K, value: Settings[K]): Promise<void> {
    // Use type assertion to resolve the type mismatch
    return window.electron.settingsStore.set(key as keyof Settings, value);
  }

  async update(settings: Partial<Settings>): Promise<void> {
    return window.electron.settingsStore.update(settings);
  }

  async reset(): Promise<Settings> {
    return window.electron.settingsStore.reset();
  }
}

// Export an instance
export const settingsService = new SettingsService();