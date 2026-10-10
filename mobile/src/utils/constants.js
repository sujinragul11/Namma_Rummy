import { Platform } from 'react-native';
import Constants from 'expo-constants';

// Game constants
export const GAME_TYPES = {
  POINTS: 'points',
  POOL: 'pool',
};

export const MAX_PLAYERS = {
  MIN: 2,
  MAX: 6,
};

export const TURN_TIMEOUT = 30; // seconds

// Card suits and values
export const SUITS = ['♠', '♥', '♦', '♣'];
export const VALUES = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];

// Colors
export const COLORS = {
  primary: '#4CAF50',
  secondary: '#2196F3',
  accent: '#FFC107',
  error: '#F44336',
  warning: '#FF9800',
  success: '#4CAF50',
  background: '#f5f5f5',
  surface: '#ffffff',
  text: '#333333',
  textSecondary: '#666666',
  table: '#1B5E20',
  tableDark: '#144A18',
};

// API endpoints (for future use)
export const API_ENDPOINTS = {
  GAMES: '/api/games',
  USERS: '/api/auth',
};

const BACKEND_PORT = 3001;

// In development the backend runs on the same machine as the Expo dev server, so its
// address is read from where this bundle was loaded. That keeps working when the PC's
// IP changes; `localhost` would point at the phone itself.
const getDevHost = () => {
  if (Platform.OS === 'web') {
    return typeof window !== 'undefined' ? window.location.hostname : 'localhost';
  }
  const hostUri = Constants.expoConfig?.hostUri;
  return hostUri ? hostUri.split(':')[0] : 'localhost';
};

const DEFAULT_URL = `http://${getDevHost()}:${BACKEND_PORT}`;

// API and Socket URLs
// Set EXPO_PUBLIC_API_URL / EXPO_PUBLIC_SOCKET_URL in mobile/.env to use a server elsewhere.
export const API_URL = process.env.EXPO_PUBLIC_API_URL || DEFAULT_URL;
export const SOCKET_URL = process.env.EXPO_PUBLIC_SOCKET_URL || DEFAULT_URL;
