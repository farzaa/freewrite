// Import Google Fonts
import '@fontsource/lato'; // Default font
import '@fontsource/dancing-script';
import '@fontsource/courier-prime';
import '@fontsource/zen-loop';
import '@fontsource/cormorant-garamond';
import '@fontsource/amatic-sc';
import '@fontsource/ibm-plex-mono';
import '@fontsource/great-vibes';
import '@fontsource/crimson-pro';
import '@fontsource/unifrakturcook';
import '@fontsource/indie-flower';

// Font family mapping
export const fontFamilies: Record<string, string> = {
  'Random': 'var(--random-font)', // Special case handled in CSS
  'Lato': '"Lato", Arial, sans-serif',
  'Dancing Script': '"Dancing Script", cursive',
  'Courier Prime': '"Courier Prime", monospace',
  'Zen Loop': '"Zen Loop", cursive',
  'Cormorant Garamond': '"Cormorant Garamond", serif',
  'Amatic SC': '"Amatic SC", cursive',
  'IBM Plex Mono': '"IBM Plex Mono", monospace',
  'Great Vibes': '"Great Vibes", cursive',
  'Crimson Pro': '"Crimson Pro", serif',
  'UnifrakturCook': '"UnifrakturCook", fantasy',
  'Indie Flower': '"Indie Flower", cursive',
  'Arial': 'Arial, sans-serif',
  'System': 'system-ui, -apple-system, BlinkMacSystemFont, sans-serif',
  'Serif': 'Georgia, Times, serif'
};

// List of all available fonts for the dropdown
export const availableFonts = [
  'Random',
  'Dancing Script',
  'Courier Prime',
  'Zen Loop',
  'Cormorant Garamond',
  'Amatic SC',
  'IBM Plex Mono',
  'Great Vibes',
  'Crimson Pro',
  'UnifrakturCook',
  'Indie Flower',
  'Lato',
  'Arial',
  'System',
  'Serif'
]; 