import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Card, Button, Title, Paragraph } from 'react-native-paper';
import { MaterialCommunityIcons as Icon } from '@expo/vector-icons';
import useGameStore from '../store/gameStore';
import useAuthStore from '../store/authStore';
import { showAlert } from '../utils/dialogs';
import { SOCKET_URL } from '../utils/constants';

// The server answers "Invalid credentials" both for an unknown account and for a wrong password
const WRONG_LOGIN_MESSAGE =
  'That email, phone or username and password do not match an account.\n\n' +
  'New here? Tap "Don\'t have an account? Register" below.';

const HomeScreen = ({ navigation }) => {
  const [username, setUsername] = useState('');
  const [gameType, setGameType] = useState('points');
  const [maxPlayers, setMaxPlayers] = useState(2);
  const [isCreating, setIsCreating] = useState(false);
  const [isJoining, setIsJoining] = useState(false);
  const [roomCode, setRoomCode] = useState('');

  // authentication state
  const [loginMode, setLoginMode] = useState('login');
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [regUsername, setRegUsername] = useState('');
  const [regEmail, setRegEmail] = useState('');
  const [regPhone, setRegPhone] = useState('');

  const {
    createGame,
    joinGameByRoomCode,
    connected,
    gameId: activeGameId,
    gameStatus: activeGameStatus,
    roomCode: activeRoomCode,
  } = useGameStore();

  const { user, loading: authLoading, login, register, logout } = useAuthStore();

  // The server puts us back in a game we are still part of as soon as the socket connects
  const hasActiveGame =
    !!activeGameId && ['waiting', 'playing', 'round_over'].includes(activeGameStatus);

  const openGame = (status) => {
    navigation.navigate(status === 'waiting' ? 'Lobby' : 'Game');
  };

  const handleCreateGame = async () => {
    if (!username.trim()) {
      showAlert('Error', 'Please enter a username');
      return;
    }
    if (!user) {
      showAlert('Authentication required', 'Please log in first');
      return;
    }

    setIsCreating(true);
    try {
      const data = await createGame(username.trim(), gameType, maxPlayers);
      openGame(data.status);
    } catch (error) {
      showAlert('Error', error.message || 'Failed to create game');
    } finally {
      setIsCreating(false);
    }
  };

  const handleJoinGame = async () => {
    if (!username.trim()) {
      showAlert('Error', 'Please enter a username');
      return;
    }
    if (!user) {
      showAlert('Authentication required', 'Please log in first');
      return;
    }

    if (!roomCode.trim()) {
      showAlert('Error', 'Please enter a room code');
      return;
    }

    setIsJoining(true);
    try {
      // Join by roomCode; backend resolves the real gameId.
      const data = await joinGameByRoomCode(roomCode.trim().toUpperCase(), username.trim());
      setRoomCode('');
      openGame(data.status);
    } catch (error) {
      showAlert('Error', error.message || 'Failed to join game');
    } finally {
      setIsJoining(false);
    }
  };

  useEffect(() => {
    // Default the table name to the account name
    if (user?.username) {
      setUsername((current) => current || user.username);
    }
  }, [user]);

  const renderAuthSection = () => {
    if (authLoading) {
      return <ActivityIndicator size="large" color="#4CAF50" />;
    }
    if (user) {
      return (
        <View style={styles.loggedInContainer}>
          <Text style={styles.welcomeText}>Welcome, {user.username}!</Text>
          <Button
            mode="outlined"
            onPress={() => navigation.navigate('Profile')}
            style={styles.profileButton}
          >
            View Profile
          </Button>
          <Button
            mode="text"
            onPress={logout}
            style={styles.logoutButton}
          >
            Logout
          </Button>
        </View>
      );
    }

    return (
      <Card style={styles.authCard}>
        <Card.Content>
          <Title style={styles.cardTitle}>
            {loginMode === 'login' ? 'Login' : 'Register'}
          </Title>

          {loginMode === 'register' && (
            <>
              <TextInput
                style={styles.input}
                placeholder="Username"
                value={regUsername}
                onChangeText={setRegUsername}
              />
              <TextInput
                style={styles.input}
                placeholder="Email (optional)"
                value={regEmail}
                onChangeText={setRegEmail}
                keyboardType="email-address"
                autoCapitalize="none"
              />
              <TextInput
                style={styles.input}
                placeholder="Phone (optional)"
                value={regPhone}
                onChangeText={setRegPhone}
                keyboardType="phone-pad"
              />
            </>
          )}

          {loginMode === 'login' && (
            <TextInput
              style={styles.input}
              placeholder="Email, phone or username"
              value={identifier}
              onChangeText={setIdentifier}
              keyboardType="email-address"
              autoCapitalize="none"
            />
          )}

          <TextInput
            style={styles.input}
            placeholder="Password"
            secureTextEntry
            value={password}
            onChangeText={setPassword}
          />

          {loginMode === 'login' ? (
            <Button
              mode="contained"
              onPress={async () => {
                if (!identifier.trim() || !password) {
                  showAlert('Error', 'Enter your email, phone or username, and your password');
                  return;
                }
                try {
                  await login({ identifier: identifier.trim(), password });
                  setIdentifier('');
                  setPassword('');
                } catch (e) {
                  showAlert(
                    'Login failed',
                    e.message === 'Invalid credentials' ? WRONG_LOGIN_MESSAGE : e.message
                  );
                }
              }}
              style={styles.authButton}
            >
              Login
            </Button>
          ) : (
            <Button
              mode="contained"
              onPress={async () => {
                try {
                  if (!regUsername.trim() || !password) {
                    showAlert('Error', 'Username and password required');
                    return;
                  }
                  if (!regEmail.trim() && !regPhone.trim()) {
                    showAlert('Error', 'Provide email or phone');
                    return;
                  }
                  await register({
                    username: regUsername.trim(),
                    email: regEmail.trim() || undefined,
                    phone: regPhone.trim() || undefined,
                    password,
                  });
                  setRegUsername('');
                  setRegEmail('');
                  setRegPhone('');
                  setPassword('');
                } catch (e) {
                  showAlert('Registration failed', e.message);
                }
              }}
              style={styles.authButton}
            >
              Sign up
            </Button>
          )}

          <TouchableOpacity
            onPress={() => {
              setLoginMode(loginMode === 'login' ? 'register' : 'login');
            }}
            style={styles.switchLink}
          >
            <Text style={styles.switchText}>
              {loginMode === 'login'
                ? "Don't have an account? Register"
                : 'Already have an account? Login'}
            </Text>
          </TouchableOpacity>
        </Card.Content>
      </Card>
    );
  };

  return (
    <SafeAreaView style={styles.container} edges={['bottom', 'left', 'right']}>
      <ScrollView contentContainerStyle={styles.scrollContent} keyboardShouldPersistTaps="handled">
        {/* Header */}
        <View style={styles.header}>
          <Icon name="cards-playing" size={60} color="#4CAF50" />
          <Title style={styles.title}>Rummy Multiplayer</Title>
          <Paragraph style={styles.subtitle}>
            Play classic rummy with friends online
          </Paragraph>
        </View>

        {renderAuthSection()}

        {/* Game server status */}
        {user && (
          <View style={styles.serverStatus}>
            <View style={[styles.statusDot, connected ? styles.statusOnline : styles.statusOffline]} />
            <Text style={styles.statusText}>
              {connected ? 'Connected to game server' : `Connecting to game server (${SOCKET_URL})...`}
            </Text>
          </View>
        )}

        {/* Game in progress */}
        {hasActiveGame && (
          <Card style={styles.card}>
            <Card.Content>
              <Title style={styles.cardTitle}>Game in progress</Title>
              <Paragraph>You are still in room {activeRoomCode}.</Paragraph>
              <Button
                mode="contained"
                onPress={() => openGame(activeGameStatus)}
                style={styles.createButton}
                icon="play"
              >
                Return to game
              </Button>
            </Card.Content>
          </Card>
        )}

        {/* Username Input */}
        <Card style={styles.card}>
          <Card.Content>
            <Title style={styles.cardTitle}>Enter Your Name</Title>
            <TextInput
              style={styles.input}
              placeholder="Username"
              value={username}
              onChangeText={setUsername}
              maxLength={20}
            />
          </Card.Content>
        </Card>

        {/* Create Game Section */}
        <Card style={styles.card}>
          <Card.Content>
            <Title style={styles.cardTitle}>Create New Game</Title>

            <View style={styles.gameOptions}>
              <View style={styles.optionRow}>
                <Text style={styles.optionLabel}>Game Type:</Text>
                <View style={styles.optionButtons}>
                  <TouchableOpacity
                    style={[
                      styles.optionButton,
                      gameType === 'points' && styles.optionButtonActive,
                    ]}
                    onPress={() => setGameType('points')}
                  >
                    <Text
                      style={[
                        styles.optionButtonText,
                        gameType === 'points' && styles.optionButtonTextActive,
                      ]}
                    >
                      Points
                    </Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={[
                      styles.optionButton,
                      gameType === 'pool' && styles.optionButtonActive,
                    ]}
                    onPress={() => setGameType('pool')}
                  >
                    <Text
                      style={[
                        styles.optionButtonText,
                        gameType === 'pool' && styles.optionButtonTextActive,
                      ]}
                    >
                      Pool
                    </Text>
                  </TouchableOpacity>
                </View>
              </View>

              <View style={styles.optionRow}>
                <Text style={styles.optionLabel}>Players:</Text>
                <View style={styles.optionButtons}>
                  {[2, 3, 4, 6].map((num) => (
                    <TouchableOpacity
                      key={num}
                      style={[
                        styles.optionButton,
                        maxPlayers === num && styles.optionButtonActive,
                      ]}
                      onPress={() => setMaxPlayers(num)}
                    >
                      <Text
                        style={[
                          styles.optionButtonText,
                          maxPlayers === num && styles.optionButtonTextActive,
                        ]}
                      >
                        {num}
                      </Text>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>
            </View>

            <Button
              mode="contained"
              onPress={handleCreateGame}
              loading={isCreating}
              disabled={isCreating}
              style={styles.createButton}
              icon="plus"
            >
              {isCreating ? 'Creating...' : 'Create Game'}
            </Button>
          </Card.Content>
        </Card>

        {/* Join Game Section */}
        <Card style={styles.card}>
          <Card.Content>
            <Title style={styles.cardTitle}>Join Existing Game</Title>
            <TextInput
              style={styles.input}
              placeholder="Enter Room Code"
              value={roomCode}
              onChangeText={setRoomCode}
              maxLength={6}
              autoCapitalize="characters"
            />
            <Button
              mode="outlined"
              onPress={handleJoinGame}
              loading={isJoining}
              disabled={isJoining}
              style={styles.joinButton}
              icon="login"
            >
              {isJoining ? 'Joining...' : 'Join Game'}
            </Button>
          </Card.Content>
        </Card>

        {/* Game Rules */}
        <Card style={styles.card}>
          <Card.Content>
            <Title style={styles.cardTitle}>How to Play</Title>
            <View style={styles.rulesList}>
              <View style={styles.ruleItem}>
                <Icon name="numeric-1-circle" size={20} color="#4CAF50" />
                <Text style={styles.ruleText}>
                  Form sequences (pure/impure) and sets of 3+ cards
                </Text>
              </View>
              <View style={styles.ruleItem}>
                <Icon name="numeric-2-circle" size={20} color="#4CAF50" />
                <Text style={styles.ruleText}>
                  Draw from deck or discard pile, then discard one card
                </Text>
              </View>
              <View style={styles.ruleItem}>
                <Icon name="numeric-3-circle" size={20} color="#4CAF50" />
                <Text style={styles.ruleText}>
                  First to meld all cards and declare wins!
                </Text>
              </View>
            </View>
          </Card.Content>
        </Card>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollContent: {
    padding: 20,
  },
  header: {
    alignItems: 'center',
    marginBottom: 30,
    paddingTop: 20,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#333',
    marginTop: 10,
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
    marginTop: 5,
  },
  card: {
    marginBottom: 20,
    elevation: 4,
  },
  cardTitle: {
    fontSize: 18,
    marginBottom: 15,
    color: '#333',
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    marginBottom: 15,
  },
  gameOptions: {
    marginBottom: 20,
  },
  optionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 15,
  },
  optionLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
  },
  optionButtons: {
    flexDirection: 'row',
  },
  optionButton: {
    paddingHorizontal: 15,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: '#4CAF50',
    marginLeft: 10,
    backgroundColor: 'white',
  },
  optionButtonActive: {
    backgroundColor: '#4CAF50',
  },
  optionButtonText: {
    color: '#4CAF50',
    fontWeight: '600',
  },
  optionButtonTextActive: {
    color: 'white',
  },
  createButton: {
    marginTop: 10,
    backgroundColor: '#4CAF50',
  },
  joinButton: {
    marginTop: 10,
    borderColor: '#2196F3',
  },
  rulesList: {
    marginTop: 10,
  },
  ruleItem: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: 10,
  },
  ruleText: {
    marginLeft: 10,
    fontSize: 14,
    color: '#555',
    flex: 1,
    lineHeight: 20,
  },
  serverStatus: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 20,
  },
  statusDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginRight: 8,
  },
  statusOnline: {
    backgroundColor: '#4CAF50',
  },
  statusOffline: {
    backgroundColor: '#F44336',
  },
  statusText: {
    fontSize: 13,
    color: '#666',
    flexShrink: 1,
  },
  /* auth styles */
  loggedInContainer: {
    alignItems: 'center',
    marginBottom: 20,
  },
  welcomeText: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
  },
  profileButton: {
    marginBottom: 5,
  },
  logoutButton: {
    marginTop: 5,
  },
  authCard: {
    marginBottom: 20,
    elevation: 4,
  },
  authButton: {
    marginTop: 10,
  },
  switchLink: {
    marginTop: 10,
    alignSelf: 'center',
  },
  switchText: {
    color: '#4CAF50',
    textDecorationLine: 'underline',
  },
});

export default HomeScreen;
