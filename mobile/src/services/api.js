import { API_URL } from '../utils/constants';

// API service for HTTP requests
class ApiService {
  constructor() {
    // Resolved in utils/constants.js: EXPO_PUBLIC_API_URL if set, otherwise the PC running Expo.
    this.baseURL = API_URL;
    this.token = null;

    // Helpful diagnostics for “Network request failed” issues.
    // Note: We do NOT log token.
    if (__DEV__) {
      console.log('[ApiService] baseURL =', this.baseURL);
    }
  }


  setToken(token) {
    this.token = token;
  }

  async request(endpoint, options = {}) {
    if (!this.baseURL) {
      throw new Error('API base URL is not set. Define EXPO_PUBLIC_API_URL in mobile/.env');
    }

    // Ensure endpoint starts with a slash.
    const normalizedEndpoint = endpoint.startsWith('/') ? endpoint : `/${endpoint}`;

    // Basic URL validation to prevent hard-to-debug “Network request failed”.
    let url;
    try {
      url = new URL(`${this.baseURL}${normalizedEndpoint}`);
    } catch (e) {
      throw new Error(`Invalid API URL: ${this.baseURL}${normalizedEndpoint}`);
    }

    // Force string in case URL object is returned.
    const finalUrl = url.toString();
    const headers = {
      'Content-Type': 'application/json',
      ...options.headers,
    };
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const config = {
      headers,
      ...options,
    };

    // Failures are thrown, not logged with console.error: the screen that made the call
    // shows them to the user, and console.error would raise Expo's red developer overlay
    // for ordinary cases such as a wrong password.
    let response;
    try {
      response = await fetch(finalUrl, config);
    } catch (error) {
      if (__DEV__) {
        console.log('[ApiService] no response from', finalUrl, error?.message);
      }
      throw new Error(
        `Cannot reach the game server at ${this.baseURL}. Check that the backend is running and that this phone is on the same network as the PC.`
      );
    }

    const text = await response.text();
    if (__DEV__) {
      console.log('[ApiService] response status=', response.status, 'url=', finalUrl);
    }
    let data = {};
    if (text) {
      try {
        data = JSON.parse(text);
      } catch (e) {
        data = { raw: text };
      }
    }

    if (!response.ok) {
      throw new Error(data?.error || `API request failed: ${response.status} ${finalUrl}`);
    }

    return data;
  }

  // Game related API calls
  async getActiveGames() {
    return this.request('/api/games/active');
  }

  async createGame(gameData) {
    return this.request('/api/games/create', {
      method: 'POST',
      body: JSON.stringify(gameData),
    });
  }

  // User related API calls
  async register(userData) {
    return this.request('/api/auth/register', {
      method: 'POST',
      body: JSON.stringify(userData),
    });
  }

  async login(credentials) {
    return this.request('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify(credentials),
    });
  }

  async getProfile() {
    return this.request('/api/user/profile');
  }

  async updateProfile(profile) {
    return this.request('/api/user/profile', {
      method: 'PATCH',
      body: JSON.stringify(profile),
    });
  }

  async updateStats(statsPayload) {
    return this.request('/api/user/stats', {
      method: 'POST',
      body: JSON.stringify(statsPayload),
    });
  }

  // Health check
  async healthCheck() {
    return this.request('/health');
  }
}

export default new ApiService();
