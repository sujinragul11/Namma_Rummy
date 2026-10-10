import React, { useEffect } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import { StatusBar } from 'expo-status-bar';
import * as ScreenOrientation from 'expo-screen-orientation';
import useAuthStore from './src/store/authStore';
import useGameStore from './src/store/gameStore';
import { showAlert } from './src/utils/dialogs';

// Import screens
import HomeScreen from './src/screens/HomeScreen';
import GameLobbyScreen from './src/screens/GameLobbyScreen';
import GameScreen from './src/screens/GameScreen';
import ProfileScreen from './src/screens/ProfileScreen';

const Stack = createStackNavigator();

export default function App() {
  const loadAuth = useAuthStore((state) => state.loadFromStorage);
  const logout = useAuthStore((state) => state.logout);
  const token = useAuthStore((state) => state.token);
  const userId = useAuthStore((state) => state.user?.id);
  const connect = useGameStore((state) => state.connect);
  const disconnect = useGameStore((state) => state.disconnect);
  const connectionError = useGameStore((state) => state.connectionError);

  useEffect(() => {
    loadAuth();
    // Everything except the game table is laid out for portrait
    ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP).catch(() => {});
  }, []);

  useEffect(() => {
    // The game socket lives exactly as long as the login
    if (!token || userId == null) return undefined;
    connect(token, String(userId));
    return () => disconnect();
  }, [token, userId]);

  useEffect(() => {
    // The server refused the saved login, e.g. the token has expired
    if (connectionError === 'Authentication required') {
      logout();
      showAlert('Session expired', 'Please log in again.');
    }
  }, [connectionError]);

  return (
    <NavigationContainer>
      <StatusBar style="auto" />
      <Stack.Navigator
        initialRouteName="Home"
        screenOptions={{
          headerStyle: {
            backgroundColor: '#4CAF50',
          },
          headerTintColor: '#fff',
          headerTitleStyle: {
            fontWeight: 'bold',
          },
        }}
      >
        <Stack.Screen
          name="Home"
          component={HomeScreen}
          options={{ title: 'Rummy Multiplayer' }}
        />
        {/* Lobby, Game and Profile draw their own headers */}
        <Stack.Screen
          name="Lobby"
          component={GameLobbyScreen}
          options={{ headerShown: false, gestureEnabled: false }}
        />
        <Stack.Screen
          name="Game"
          component={GameScreen}
          options={{ headerShown: false, gestureEnabled: false }}
        />
        <Stack.Screen
          name="Profile"
          component={ProfileScreen}
          options={{ headerShown: false }}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
