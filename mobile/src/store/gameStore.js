import { create } from 'zustand';
import io from 'socket.io-client';
import { SOCKET_URL } from '../utils/constants';
import { sortIntoGroups } from '../utils/rummy';

const REQUEST_TIMEOUT = 8000;
const NOTIFICATION_LIFETIME = 4000;

const emptyGame = {
  gameId: null,
  roomCode: null,
  gameState: null,
  players: [],
  hand: [],
  groups: [], // own arrangement of the hand: arrays of card ids
  joker: null,
  currentTurn: null,
  isMyTurn: false,
  gameStatus: null,
  turnEndsAt: null,
  nextRoundAt: null,
  lastResult: null,
};

// Keep the player's arrangement across updates: cards that left the hand are removed,
// a newly drawn card sits on its own at the right.
const reconcileGroups = (previousGroups, gameState, isNewDeal) => {
  const hand = gameState.hand || [];
  if (hand.length === 0) return [];

  let base = previousGroups;
  if (isNewDeal) {
    // After a reconnect the server still has the arrangement; a fresh deal is sorted by suit
    const saved = gameState.groups || [];
    base = saved.length > 0 ? saved : sortIntoGroups(hand);
  }

  const inHand = new Set(hand.map((card) => card.id));
  const groups = base
    .map((group) => group.filter((id) => inHand.has(id)))
    .filter((group) => group.length > 0);

  const placed = new Set(groups.flat());
  const added = hand.filter((card) => !placed.has(card.id)).map((card) => card.id);
  if (added.length > 0) groups.push(added);

  return groups;
};

const useGameStore = create((set, get) => ({
  // State
  socket: null,
  connected: false,
  connectionError: null,
  playerId: null,
  notifications: [],
  ...emptyGame,

  // Actions
  notify: (type, message) => {
    const id = `${Date.now()}-${Math.random()}`;
    set({ notifications: [...get().notifications, { id, type, message }] });
    setTimeout(() => {
      set({ notifications: get().notifications.filter((n) => n.id !== id) });
    }, NOTIFICATION_LIFETIME);
  },

  // Opens the game socket for a logged-in user. The server reads who we are from the token.
  connect: (token, userId) => {
    get().disconnect();

    const socket = io(SOCKET_URL, {
      transports: ['websocket'],
      auth: { token },
      reconnection: true,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 5000,
    });

    socket.on('connect', () => {
      console.log('Socket connected:', socket.id);
      set({ connected: true, connectionError: null });
    });

    socket.on('disconnect', () => {
      set({ connected: false });
    });

    socket.on('connect_error', (error) => {
      set({ connected: false, connectionError: error.message });
    });

    // The server sends the whole table after every change, with only our own hand in it.
    // It also sends it on (re)connect when we are still seated in a game.
    socket.on('gameState', (gameState) => {
      const previous = get().gameState;
      const isNewDeal =
        !previous ||
        previous.gameId !== gameState.gameId ||
        previous.round !== gameState.round ||
        get().groups.length === 0;
      const groups = reconcileGroups(get().groups, gameState, isNewDeal);

      // The server scores a losing hand by its arrangement, so it must always hold the one
      // shown on screen, including the automatic sort of a fresh deal.
      if (gameState.status === 'playing' && JSON.stringify(groups) !== JSON.stringify(gameState.groups || [])) {
        get().syncGroups(groups);
      }

      set({
        gameState,
        gameId: gameState.gameId,
        roomCode: gameState.roomCode,
        players: gameState.players || [],
        hand: gameState.hand || [],
        groups,
        joker: gameState.joker,
        currentTurn: gameState.currentPlayer,
        isMyTurn: gameState.currentPlayer === get().playerId,
        gameStatus: gameState.status,
        turnEndsAt: gameState.turnTimeLeft != null ? Date.now() + gameState.turnTimeLeft : null,
        nextRoundAt: gameState.nextRoundIn != null ? Date.now() + gameState.nextRoundIn : null,
        lastResult: gameState.lastResult,
      });
    });

    socket.on('playerJoined', (data) => {
      get().notify('info', `${data.username} joined the game`);
    });

    socket.on('playerLeft', (data) => {
      get().notify('warning', `${data.username} left the game`);
    });

    socket.on('playerDisconnected', (data) => {
      get().notify('warning', `${data.username} lost connection`);
    });

    socket.on('playerReconnected', (data) => {
      get().notify('info', `${data.username} is back`);
    });

    socket.on('playerDropped', (data) => {
      const who = data.userId === get().playerId ? 'You were' : `${data.username} was`;
      get().notify(
        'info',
        data.timedOut ? `${who} dropped for inactivity` : `${data.username} dropped out of the round`
      );
    });

    socket.on('wrongDeclaration', (data) => {
      get().notify('warning', `${data.username} made a wrong declaration`);
    });

    socket.on('gameError', (data) => {
      get().notify('error', data.message);
    });

    set({ socket, playerId: userId, connectionError: null });
  },

  disconnect: () => {
    const { socket } = get();
    if (socket) {
      socket.removeAllListeners();
      socket.disconnect();
    }
    set({ socket: null, connected: false, playerId: null, notifications: [], ...emptyGame });
  },

  // Sends an event and resolves with the server's reply, or rejects with its error message
  request: (event, payload = {}) =>
    new Promise((resolve, reject) => {
      const { socket } = get();
      if (!socket || !socket.connected) {
        reject(new Error('Not connected to the game server'));
        return;
      }

      socket.timeout(REQUEST_TIMEOUT).emit(event, payload, (timeoutError, response) => {
        if (timeoutError) {
          reject(new Error('The game server did not respond'));
        } else if (!response || !response.ok) {
          reject(new Error((response && response.error) || 'Request failed'));
        } else {
          resolve(response);
        }
      });
    }),

  createGame: (username, gameType = 'points', maxPlayers = 2) =>
    get().request('createGame', { username, gameType, maxPlayers }),

  joinGameByRoomCode: (roomCode, username) =>
    get().request('joinGameByRoomCode', { roomCode, username }),

  startGame: () => get().request('startGame'),

  drawCard: (fromDiscard = false) => get().request('drawCard', { fromDiscard }),

  discardCard: (cardId) => get().request('discardCard', { cardId }),

  // The card is discarded to finish; the rest of the hand is judged as currently grouped
  declareWin: (cardId) => {
    const groups = get()
      .groups.map((group) => group.filter((id) => id !== cardId))
      .filter((group) => group.length > 0);
    return get().request('declare', { cardId, groups });
  },

  dropRound: () => get().request('drop'),

  syncGroups: (groups) => {
    get()
      .request('arrangeHand', { groups })
      .catch(() => {});
  },

  setGroups: (groups) => {
    const clean = groups.filter((group) => group.length > 0);
    set({ groups: clean });
    get().syncGroups(clean);
  },

  sortHand: () => {
    get().setGroups(sortIntoGroups(get().hand));
  },

  leaveGame: async () => {
    try {
      await get().request('leaveGame');
    } catch (error) {
      // Offline or already gone: nothing more to tell the server
    }
    set({ ...emptyGame });
  },

  clearNotifications: () => {
    set({ notifications: [] });
  },
}));

export default useGameStore;
