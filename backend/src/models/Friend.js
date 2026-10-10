const db = require('../database/db');
const User = require('./User');

const MAX_WAITING_REQUESTS = 30;
const RECENT_PLAYERS = 5;
const PLAY_AGAIN_MINUTES = 15;

// Friendships: one row per pair of players. `status` is
//   pending   the requester asked, the addressee has not answered yet
//   accepted  they are friends
//   blocked   the requester of the row wants no more requests from the addressee
class Friend {
  // The one row between two players, whichever of them asked
  static async between(a, b) {
    const result = await db.query(
      `SELECT * FROM friendships
       WHERE (requester_id = $1 AND addressee_id = $2) OR (requester_id = $2 AND addressee_id = $1)`,
      [a, b]
    );
    return result.rows[0];
  }

  // Asks the player called `username` to be friends. If that player had already asked us,
  // this accepts. Returns { user, accepted, silent }; `silent` means the other player
  // must not be told (they blocked us).
  static async request(userId, username) {
    const name = typeof username === 'string' ? username.trim() : '';
    if (!name) throw new Error("Enter your friend's username");

    const other = await User.findByUsername(name);
    if (!other) throw new Error(`No player is called "${name}". Check the spelling.`);
    if (other.id === userId) throw new Error('That is your own username');

    const row = await Friend.between(userId, other.id);
    if (!row) {
      const waiting = await db.query(
        `SELECT COUNT(*)::int AS count FROM friendships WHERE requester_id = $1 AND status = 'pending'`,
        [userId]
      );
      if (waiting.rows[0].count >= MAX_WAITING_REQUESTS) {
        throw new Error('You have too many requests waiting for an answer');
      }
      await db.query(
        `INSERT INTO friendships (requester_id, addressee_id) VALUES ($1, $2)`,
        [userId, other.id]
      );
      return { user: other, accepted: false, silent: false };
    }

    if (row.status === 'accepted') {
      throw new Error(`You and ${other.username} are already friends`);
    }
    if (row.status === 'pending') {
      if (row.requester_id === userId) throw new Error(`You have already asked ${other.username}`);
      await db.query(`UPDATE friendships SET status = 'accepted' WHERE id = $1`, [row.id]);
      return { user: other, accepted: true, silent: false };
    }

    // Blocked. Our own block is lifted by asking; theirs makes the request vanish
    if (row.requester_id === userId) {
      await db.query(`UPDATE friendships SET status = 'pending' WHERE id = $1`, [row.id]);
      return { user: other, accepted: false, silent: false };
    }
    return { user: other, accepted: false, silent: true };
  }

  // Answers a request that `otherId` sent us: 'accept', 'decline' or 'block'
  static async respond(userId, otherId, action) {
    const row = await Friend.between(userId, otherId);
    if (!row || row.status !== 'pending' || row.addressee_id !== userId) {
      throw new Error('That request is no longer there');
    }

    if (action === 'accept') {
      await db.query(`UPDATE friendships SET status = 'accepted' WHERE id = $1`, [row.id]);
    } else if (action === 'decline') {
      await db.query(`DELETE FROM friendships WHERE id = $1`, [row.id]);
    } else if (action === 'block') {
      await db.query(
        `UPDATE friendships SET requester_id = $1, addressee_id = $2, status = 'blocked' WHERE id = $3`,
        [userId, otherId, row.id]
      );
    } else {
      throw new Error('Unknown answer');
    }
  }

  // Ends a friendship, or takes back a request we sent
  static async remove(userId, otherId) {
    const row = await Friend.between(userId, otherId);
    const ours = row && (row.status === 'accepted' || (row.status === 'pending' && row.requester_id === userId));
    if (!ours) throw new Error('That player is not in your list');
    await db.query(`DELETE FROM friendships WHERE id = $1`, [row.id]);
  }

  // Everyone a player is connected to, in three lists of { id, username }
  static async list(userId) {
    const result = await db.query(
      `SELECT f.status, f.requester_id, u.id, u.username
       FROM friendships f
       JOIN users u ON u.id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
       WHERE (f.requester_id = $1 OR f.addressee_id = $1) AND f.status <> 'blocked'
       ORDER BY LOWER(u.username)`,
      [userId]
    );

    const lists = { friends: [], incoming: [], outgoing: [] };
    for (const row of result.rows) {
      const entry = { id: row.id, username: row.username };
      if (row.status === 'accepted') lists.friends.push(entry);
      else if (row.requester_id === userId) lists.outgoing.push(entry);
      else lists.incoming.push(entry);
    }
    return lists;
  }

  // The friend's { id, username }, or undefined when the two are not friends
  static async friendOf(userId, otherId) {
    const result = await db.query(
      `SELECT u.id, u.username
       FROM friendships f JOIN users u ON u.id = $2
       WHERE f.status = 'accepted'
         AND ((f.requester_id = $1 AND f.addressee_id = $2) OR (f.requester_id = $2 AND f.addressee_id = $1))`,
      [userId, otherId]
    );
    return result.rows[0];
  }

  // The other player's { id, username } if the two finished a game at the same table in the
  // last few minutes, whether or not they are friends. Lets them call each other to play again.
  static async tableMate(userId, otherId) {
    const result = await db.query(
      `SELECT u.id, u.username
       FROM player_games mine
       JOIN player_games theirs ON theirs.game_id = mine.game_id
       JOIN users u ON u.id = theirs.user_id
       WHERE mine.user_id = $1 AND theirs.user_id = $2 AND mine.user_id <> theirs.user_id
         AND mine.joined_at > CURRENT_TIMESTAMP - ($3 * INTERVAL '1 minute')
       LIMIT 1`,
      [userId, otherId, PLAY_AGAIN_MINUTES]
    );
    return result.rows[0];
  }

  static async friendIds(userId) {
    return (await Friend.list(userId)).friends.map((friend) => friend.id);
  }

  // Everyone whose lists mention this player: friends and requests in either direction
  static async contactIds(userId) {
    const lists = await Friend.list(userId);
    return [...lists.friends, ...lists.incoming, ...lists.outgoing].map((entry) => entry.id);
  }

  // The players last met at a table who are not in any of our lists yet
  static async recentPlayers(userId) {
    const result = await db.query(
      `SELECT u.id, u.username
       FROM player_games mine
       JOIN player_games theirs ON theirs.game_id = mine.game_id AND theirs.user_id <> mine.user_id
       JOIN users u ON u.id = theirs.user_id
       WHERE mine.user_id = $1
         AND NOT EXISTS (
           SELECT 1 FROM friendships f
           WHERE (f.requester_id = $1 AND f.addressee_id = u.id) OR (f.requester_id = u.id AND f.addressee_id = $1)
         )
       GROUP BY u.id, u.username
       ORDER BY MAX(theirs.joined_at) DESC
       LIMIT $2`,
      [userId, RECENT_PLAYERS]
    );
    return result.rows;
  }
}

module.exports = Friend;
