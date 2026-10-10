import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';
import api from '../services/api';

const useAuthStore = create((set, get) => ({
  user: null,
  token: null,
  loading: false,
  error: null,

  loadFromStorage: async () => {
    try {
      const token = await AsyncStorage.getItem('token');
      const userString = await AsyncStorage.getItem('user');
      if (token && userString) {
        const user = JSON.parse(userString);
        api.setToken(token);
        set({ token, user });
      }
    } catch (e) {
      console.error('Failed to load auth from storage', e);
    }
  },

  login: async ({ identifier, password }) => {
    set({ loading: true, error: null });
    try {
      const data = await api.login({ identifier, password });
      api.setToken(data.token);
      await AsyncStorage.setItem('token', data.token);
      await AsyncStorage.setItem('user', JSON.stringify(data.user));
      set({ user: data.user, token: data.token, loading: false });
      return data.user;
    } catch (e) {
      set({ loading: false, error: e.message || 'Login failed' });
      throw e;
    }
  },

  register: async ({ username, email, phone, password }) => {
    set({ loading: true, error: null });
    try {
      const data = await api.register({ username, email, phone, password });
      api.setToken(data.token);
      await AsyncStorage.setItem('token', data.token);
      await AsyncStorage.setItem('user', JSON.stringify(data.user));
      set({ user: data.user, token: data.token, loading: false });
      return data.user;
    } catch (e) {
      set({ loading: false, error: e.message || 'Registration failed' });
      throw e;
    }
  },

  logout: async () => {
    try {
      await AsyncStorage.removeItem('token');
      await AsyncStorage.removeItem('user');
      api.setToken(null);
      set({ user: null, token: null });
    } catch (e) {
      console.error('Logout error', e);
    }
  },

  fetchProfile: async () => {
    const { token } = get();
    if (!token) return;
    try {
      const data = await api.getProfile();
      set({ user: data.user });
    } catch (e) {
      // The profile screen falls back to what is already stored
      console.log('Failed to fetch profile:', e.message);
    }
  },

  updateProfile: async ({ username, email }) => {
    const data = await api.updateProfile({ username, email });
    const user = { ...get().user, ...data.user };
    await AsyncStorage.setItem('user', JSON.stringify(user));
    set({ user });
    return user;
  },
}));

export default useAuthStore;
