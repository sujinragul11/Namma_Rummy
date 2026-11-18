// Voice chat at the table. What a player says into the microphone reaches the other players
// seated at the same table as it is spoken, and nobody else: each piece of sound is passed on
// to that table's players and forgotten. Nothing is recorded, written to the database or kept
// in memory. Turns, cards and the clock are never touched, and the game is not saved because
// of it. A player who blocked someone in the chat does not hear them either.
//
// The app sends a piece of sound every 40 ms while its player speaks: { level, data }, with
// data the sound compressed (IMA ADPCM, 16 kHz) and written as base64, and level how loud it
// was (0 to 100), for the ring round the speaker's picture. The server does not open it.

const MAX_PACKET_CHARS = 4000; // one piece of sound, written out (about 0.1 s at most)
const PACKETS_PER_SECOND = 40; // more than this from one player in a second is not passed on...
const CHARS_PER_SECOND = 24000; // ...and neither is more sound than this, about twice normal speech
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;
// A listener whose connection already has this much waiting to go out misses a piece of sound
// rather than receiving it late, and rather than holding up the moves of the game behind it
const BACKLOG_PACKETS = 8;
const BACKLOG_BYTES = 32 * 1024;

class VoiceRelay {
  constructor(manager) {
    this.manager = manager; // the SocketManager: who sits at which table
    this.mics = new Map(); // gameId -> Set of the players there whose microphone is on
    this.pace = new Map(); // userId -> { second, packets, chars }: what they sent this second
  }

  // The players at this table with their microphone on, as a list of ids
  micsOf(gameEngine) {
    const on = this.mics.get(gameEngine.gameId);
    if (!on) return [];
    return [...on].filter((id) => {
      const player = gameEngine.players.get(id);
      return player && !player.left;
    });
  }

  setMic(gameEngine, userId, on) {
    let set = this.mics.get(gameEngine.gameId);
    if (on) {
      if (!set) this.mics.set(gameEngine.gameId, (set = new Set()));
      set.add(userId);
    } else if (set) {
      set.delete(userId);
      if (set.size === 0) this.mics.delete(gameEngine.gameId);
    }

    // The microphones of tables that are over go with them
    if (this.mics.size > this.manager.games.size) {
      for (const id of this.mics.keys()) {
        if (!this.manager.games.has(id)) this.mics.delete(id);
      }
    }

    // Everyone at the table sees who can be heard: a microphone, or a struck-out one, on each picture
    const update = { gameId: gameEngine.gameId, mics: this.micsOf(gameEngine) };
    for (const [playerId, player] of gameEngine.players) {
      if (player.left) continue;
      this.manager.io.to(this.manager.userRoom(playerId)).emit('voiceMics', update);
    }
  }

  isOn(gameEngine, userId) {
    const set = this.mics.get(gameEngine.gameId);
    return Boolean(set && set.has(userId));
  }

  // False when the player has sent too much this second
  withinPace(userId, chars) {
    const second = Math.floor(Date.now() / 1000);
    let pace = this.pace.get(userId);
    if (!pace || pace.second !== second) {
      pace = { second, packets: 0, chars: 0 };
      this.pace.set(userId, pace);
    }
    pace.packets += 1;
    pace.chars += chars;
    if (this.pace.size > 500) {
      for (const [id, entry] of this.pace) {
        if (entry.second !== second) this.pace.delete(id);
      }
    }
    return pace.packets <= PACKETS_PER_SECOND && pace.chars <= CHARS_PER_SECOND;
  }

  // A player who has blocked someone in the chat does not hear them
  hides(listenerId, speakerId) {
    const chat = this.manager.chat;
    return Boolean(chat && typeof chat.isBlocked === 'function' && chat.isBlocked(listenerId, speakerId));
  }

  // True when this connection is already behind with what it has to receive
  static congested(socket) {
    const conn = socket.conn;
    if (!conn || conn.readyState !== 'open') return true;
    if (conn.writeBuffer && conn.writeBuffer.length > BACKLOG_PACKETS) return true;
    const ws = conn.transport && conn.transport.socket;
    return Boolean(ws && ws.bufferedAmount > BACKLOG_BYTES);
  }

  // Passes a piece of sound on to the other players at the speaker's table
  relay(userId, data) {
    if (!data || typeof data.data !== 'string') return;
    const sound = data.data;
    if (sound.length === 0 || sound.length > MAX_PACKET_CHARS || !BASE64.test(sound)) return;
    const gameEngine = this.manager.getUserGame(userId);
    if (!gameEngine) return;
    const speaker = gameEngine.players.get(userId);
    if (!speaker || speaker.left || !this.isOn(gameEngine, userId)) return;
    if (!this.withinPace(userId, sound.length)) return;

    const level = Math.max(0, Math.min(100, Math.round(Number(data.level) || 0)));
    const packet = { gameId: gameEngine.gameId, from: userId, level, data: sound };
    const sockets = this.manager.io.sockets;
    for (const [playerId, player] of gameEngine.players) {
      if (playerId === userId || player.left || this.hides(playerId, userId)) continue;
      const room = sockets.adapter.rooms.get(this.manager.userRoom(playerId));
      if (!room) continue;
      for (const socketId of room) {
        const listener = sockets.sockets.get(socketId);
        if (listener && !VoiceRelay.congested(listener)) listener.emit('voice', packet);
      }
    }
  }

  // Called for every new connection, with SocketManager's `handle` for replies
  attach(socket, handle) {
    const { userId } = socket.data;

    // { on: true or false }: the player switched their microphone on or off
    handle('voiceMic', async (data) => {
      const gameEngine = this.manager.requireGame(userId);
      const player = gameEngine.players.get(userId);
      if (!player || player.left) throw new Error('You are not at this table');
      this.setMic(gameEngine, userId, data.on === true);
      return { mics: this.micsOf(gameEngine) };
    });

    // Whose microphone is on at the player's table, asked when the table opens
    handle('voiceMics', async () => {
      const gameEngine = this.manager.requireGame(userId);
      return { gameId: gameEngine.gameId, mics: this.micsOf(gameEngine) };
    });

    // Sound comes many times a second and wants no reply
    socket.on('voice', (data) => {
      try {
        this.relay(userId, data);
      } catch (error) {
        console.error('Voice relay failed:', error.message);
      }
    });

    // A player whose last connection is gone cannot be heard any more: their microphone is off
    socket.on('disconnect', () => {
      const remaining = this.manager.io.sockets.adapter.rooms.get(this.manager.userRoom(userId));
      if (remaining && remaining.size > 0) return;
      this.pace.delete(userId);
      const gameEngine = this.manager.getUserGame(userId);
      if (gameEngine && this.isOn(gameEngine, userId)) this.setMic(gameEngine, userId, false);
    });
  }
}

module.exports = VoiceRelay;
