import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Card, Button, Title, Chip } from 'react-native-paper';
import { MaterialCommunityIcons as Icon } from '@expo/vector-icons';
import * as Clipboard from 'expo-clipboard';
import useGameStore from '../store/gameStore';
import { showAlert, confirmAction } from '../utils/dialogs';
import { TURN_TIMEOUT } from '../utils/constants';

const GameLobbyScreen = ({ navigation }) => {
  const [copied, setCopied] = useState(false);
  const [isStarting, setIsStarting] = useState(false);

  const {
    gameId,
    gameState,
    roomCode,
    playerId,
    players,
    gameStatus,
    startGame,
    leaveGame,
    notifications,
    clearNotifications,
  } = useGameStore();

  useEffect(() => {
    if (!gameId) {
      // Left the lobby, or it was closed
      navigation.popToTop();
    } else if (gameStatus && gameStatus !== 'waiting') {
      navigation.replace('Game');
    }
  }, [gameId, gameStatus, navigation]);

  const copyRoomCode = async () => {
    try {
      await Clipboard.setStringAsync(roomCode);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (error) {
      showAlert('Error', 'Failed to copy room code');
    }
  };

  const handleLeaveLobby = () => {
    confirmAction('Leave Lobby', 'Are you sure you want to leave the game?', 'Leave', leaveGame);
  };

  const handleStartGame = async () => {
    setIsStarting(true);
    try {
      await startGame();
    } catch (error) {
      showAlert('Error', error.message);
    } finally {
      setIsStarting(false);
    }
  };

  const maxPlayers = gameState?.maxPlayers || 2;
  const isHost = gameState?.hostId === playerId;
  const currentPlayer = players.find(p => p.id === playerId);
  const otherPlayers = players.filter(p => p.id !== playerId);
  const seatsLeft = Math.max(0, maxPlayers - players.length);

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContent}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={handleLeaveLobby} style={styles.backButton}>
          <Icon name="arrow-left" size={24} color="#333" />
        </TouchableOpacity>
        <Title style={styles.title}>Game Lobby</Title>
        <View style={styles.placeholder} />
      </View>

      {/* Room Code */}
      <Card style={styles.roomCard}>
        <Card.Content style={styles.roomContent}>
          <View style={styles.roomInfo}>
            <Icon name="key" size={24} color="#4CAF50" />
            <View style={styles.roomDetails}>
              <Text style={styles.roomLabel}>Room Code</Text>
              <Text style={styles.roomCode}>{roomCode}</Text>
            </View>
          </View>
          <TouchableOpacity onPress={copyRoomCode} style={styles.copyButton}>
            <Icon
              name={copied ? "check" : "content-copy"}
              size={20}
              color={copied ? "#4CAF50" : "#666"}
            />
            <Text style={[styles.copyText, copied && styles.copyTextSuccess]}>
              {copied ? 'Copied!' : 'Copy'}
            </Text>
          </TouchableOpacity>
        </Card.Content>
      </Card>

      {/* Current Player */}
      <Card style={styles.playerCard}>
        <Card.Content>
          <View style={styles.playerHeader}>
            <Icon name="account" size={24} color="#4CAF50" />
            <Text style={styles.playerTitle}>You</Text>
            {isHost && <Chip icon="crown" style={styles.hostChip}>Host</Chip>}
          </View>
          <Text style={styles.playerName}>{currentPlayer?.username}</Text>
          <Text style={styles.playerStatus}>
            {gameState?.gameType === 'pool' ? `Pool ${gameState.poolLimit}` : 'Points'} rummy · {maxPlayers} players
          </Text>
        </Card.Content>
      </Card>

      {/* Other Players */}
      <Card style={styles.playersCard}>
        <Card.Content>
          <View style={styles.playersHeader}>
            <Icon name="account-group" size={24} color="#2196F3" />
            <Text style={styles.playersTitle}>
              Players ({players.length}/{maxPlayers})
            </Text>
          </View>

          {otherPlayers.length === 0 ? (
            <View style={styles.emptyPlayers}>
              <Icon name="account-plus" size={48} color="#ccc" />
              <Text style={styles.emptyText}>Waiting for players to join...</Text>
              <Text style={styles.shareText}>
                Share the room code with friends to start playing!
              </Text>
            </View>
          ) : (
            <View style={styles.playersList}>
              {otherPlayers.map((player) => (
                <View key={player.id} style={styles.playerItem}>
                  <View style={styles.playerAvatar}>
                    <Icon name="account" size={20} color="#666" />
                  </View>
                  <View style={styles.playerInfo}>
                    <Text style={styles.playerName}>{player.username}</Text>
                    <Text style={styles.playerStatus}>
                      {player.connected ? 'Joined' : 'Offline'}
                    </Text>
                  </View>
                  {player.id === gameState?.hostId && (
                    <Chip icon="crown" style={styles.hostChip}>Host</Chip>
                  )}
                </View>
              ))}
            </View>
          )}

          <Text style={styles.waitingText}>
            {seatsLeft > 0
              ? `The game starts automatically when ${seatsLeft} more ${seatsLeft === 1 ? 'player joins' : 'players join'}.`
              : 'Starting...'}
          </Text>
          {isHost && players.length >= 2 && seatsLeft > 0 && (
            <Button
              mode="contained"
              onPress={handleStartGame}
              loading={isStarting}
              disabled={isStarting}
              style={styles.startButton}
              icon="play"
            >
              Start with {players.length} players
            </Button>
          )}
        </Card.Content>
      </Card>

      {/* Game Info */}
      <Card style={styles.infoCard}>
        <Card.Content>
          <Title style={styles.infoTitle}>Game Rules</Title>
          <View style={styles.rulesList}>
            <View style={styles.ruleItem}>
              <Icon name="cards" size={20} color="#4CAF50" />
              <Text style={styles.ruleText}>
                Each player gets 13 cards
              </Text>
            </View>
            <View style={styles.ruleItem}>
              <Icon name="timeline" size={20} color="#4CAF50" />
              <Text style={styles.ruleText}>
                Form sequences and sets to win
              </Text>
            </View>
            <View style={styles.ruleItem}>
              <Icon name="timer" size={20} color="#4CAF50" />
              <Text style={styles.ruleText}>
                {TURN_TIMEOUT} seconds per turn
              </Text>
            </View>
          </View>
        </Card.Content>
      </Card>
      </ScrollView>

      {/* Notifications */}
      {notifications.length > 0 && (
        <View style={styles.notifications}>
          {notifications.slice(-3).map((notification) => (
            <View
              key={notification.id}
              style={[
                styles.notification,
                notification.type === 'error' && styles.errorNotification,
                notification.type === 'success' && styles.successNotification,
                notification.type === 'warning' && styles.warningNotification,
              ]}
            >
              <Text style={styles.notificationText}>{notification.message}</Text>
            </View>
          ))}
          <TouchableOpacity
            onPress={clearNotifications}
            style={styles.clearButton}
          >
            <Icon name="close" size={16} color="#666" />
          </TouchableOpacity>
        </View>
      )}

      {/* Bottom Actions */}
      <View style={styles.bottomActions}>
        <Button
          mode="outlined"
          onPress={handleLeaveLobby}
          style={styles.leaveButton}
          icon="exit-to-app"
        >
          Leave Lobby
        </Button>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollContent: {
    paddingBottom: 10,
  },
  waitingText: {
    fontSize: 14,
    color: '#666',
    textAlign: 'center',
    marginTop: 10,
  },
  startButton: {
    marginTop: 15,
    backgroundColor: '#4CAF50',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 20,
    backgroundColor: 'white',
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  backButton: {
    padding: 5,
  },
  title: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333',
  },
  placeholder: {
    width: 34,
  },
  roomCard: {
    margin: 20,
    marginBottom: 10,
    elevation: 4,
  },
  roomContent: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  roomInfo: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  roomDetails: {
    marginLeft: 10,
  },
  roomLabel: {
    fontSize: 12,
    color: '#666',
    textTransform: 'uppercase',
  },
  roomCode: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#333',
    letterSpacing: 2,
  },
  copyButton: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 8,
  },
  copyText: {
    marginLeft: 5,
    fontSize: 14,
    color: '#666',
  },
  copyTextSuccess: {
    color: '#4CAF50',
  },
  playerCard: {
    margin: 20,
    marginBottom: 10,
    elevation: 4,
  },
  playerHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
  },
  playerTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#333',
    marginLeft: 10,
    flex: 1,
  },
  hostChip: {
    backgroundColor: '#FFF3E0',
  },
  playerName: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
  },
  playerStatus: {
    fontSize: 14,
    color: '#666',
    marginTop: 2,
  },
  playersCard: {
    margin: 20,
    marginBottom: 10,
    elevation: 4,
  },
  playersHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 15,
  },
  playersTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#333',
    marginLeft: 10,
  },
  emptyPlayers: {
    alignItems: 'center',
    padding: 30,
  },
  emptyText: {
    fontSize: 16,
    color: '#666',
    marginTop: 10,
    textAlign: 'center',
  },
  shareText: {
    fontSize: 14,
    color: '#999',
    marginTop: 5,
    textAlign: 'center',
  },
  playersList: {
    marginTop: 10,
  },
  playerItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 5,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  playerAvatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#f0f0f0',
    alignItems: 'center',
    justifyContent: 'center',
  },
  playerInfo: {
    flex: 1,
    marginLeft: 15,
  },
  infoCard: {
    margin: 20,
    marginBottom: 10,
    elevation: 4,
  },
  infoTitle: {
    fontSize: 16,
    marginBottom: 15,
    color: '#333',
  },
  rulesList: {
    marginTop: 5,
  },
  ruleItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 10,
  },
  ruleText: {
    marginLeft: 10,
    fontSize: 14,
    color: '#555',
  },
  notifications: {
    position: 'absolute',
    top: 80,
    left: 20,
    right: 20,
    zIndex: 1000,
  },
  notification: {
    backgroundColor: '#333',
    padding: 12,
    borderRadius: 8,
    marginBottom: 8,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  errorNotification: {
    backgroundColor: '#F44336',
  },
  successNotification: {
    backgroundColor: '#4CAF50',
  },
  warningNotification: {
    backgroundColor: '#FF9800',
  },
  notificationText: {
    color: 'white',
    fontSize: 14,
    flex: 1,
  },
  clearButton: {
    marginLeft: 10,
  },
  bottomActions: {
    padding: 20,
    backgroundColor: 'white',
    borderTopWidth: 1,
    borderTopColor: '#e0e0e0',
  },
  leaveButton: {
    borderColor: '#F44336',
  },
});

export default GameLobbyScreen;
