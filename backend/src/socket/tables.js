// Which table a player sits at, in either game: a rummy table (SocketManager's GameEngine) or
// a Donkey Master table (DonkeyManager's DonkeyEngine). For what happens at any table alike,
// whatever is played there: voice chat (VoiceRelay), the table chat and the things thrown.
//
// A table is { id, game: 'rummy' | 'donkey', players, engine }: `id` is what the app knows the
// table by (gameId at rummy, roomId at Donkey Master), `players` the engine's own Map of
// user id -> player, each with `left` true once they got up. `manager` is the SocketManager.

function tableOf(manager, userId) {
  const game = manager.getUserGame(userId);
  if (game) return { id: game.gameId, game: 'rummy', players: game.players, engine: game };
  const room = manager.donkey ? manager.donkey.roomOf(userId) : null;
  if (room) return { id: room.roomId, game: 'donkey', players: room.players, engine: room };
  return null;
}

// The same, for a request that needs a table: throws the error the apps know for "no table"
function requireTable(manager, userId) {
  const table = tableOf(manager, userId);
  if (!table) throw new Error('Game not found');
  return table;
}

// Whether a table with this id still exists, in either game
function tableExists(manager, id) {
  return manager.games.has(id) || Boolean(manager.donkey && manager.donkey.rooms.has(id));
}

// How many tables there are, in both games
function tableCount(manager) {
  return manager.games.size + (manager.donkey ? manager.donkey.rooms.size : 0);
}

module.exports = { tableOf, requireTable, tableExists, tableCount };
