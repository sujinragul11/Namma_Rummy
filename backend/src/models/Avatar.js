const db = require('../database/db');

// A player's profile photo, shown in the round picture wherever the player appears: at the
// table, in the lobby, in friends lists. The app turns the chosen picture into a small square
// JPEG before sending it. The server keeps it as it came, after checking that it really is a
// small picture, since other players' phones will open it.
const MAX_BYTES = 200 * 1024;
const MAX_SIDE = 512;

// A refusal the player can be shown as it is
const refuse = (message) => Object.assign(new Error(message), { forPlayer: true });

class Avatar {
  static get MAX_BYTES() {
    return MAX_BYTES;
  }

  // The server does this at every start as well as in migrate.js, so an existing database
  // gets the table without a migration. The photo goes with the account (ON DELETE CASCADE).
  // A removed photo keeps its row with image NULL, so the version only ever goes up and a
  // phone never shows an old photo it kept under a version number that was used again.
  static async ensureSchema() {
    await db.query(`
      CREATE TABLE IF NOT EXISTS avatars (
        user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        image BYTEA,
        mime VARCHAR(20),
        version INTEGER NOT NULL DEFAULT 0,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
  }

  // What the bytes are: { mime, width, height }. Anything else is refused with a message.
  static inspect(buffer) {
    if (!Buffer.isBuffer(buffer) || buffer.length === 0) throw refuse('No picture was sent');
    if (buffer.length > MAX_BYTES) throw refuse('That picture is too large');

    let mime = null;
    let size = null;
    if (buffer.length >= 24 && buffer.readUInt32BE(0) === 0x89504e47 && buffer.readUInt32BE(4) === 0x0d0a1a0a
      && buffer.toString('ascii', 12, 16) === 'IHDR') {
      mime = 'image/png';
      size = { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
    } else if (buffer.length >= 4 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
      mime = 'image/jpeg';
      size = jpegSize(buffer);
    }
    if (!mime) throw refuse('The picture must be a JPEG or PNG image');
    if (!size || size.width < 1 || size.height < 1 || size.width > MAX_SIDE || size.height > MAX_SIDE) {
      throw refuse(`The picture must be at most ${MAX_SIDE} pixels on each side`);
    }
    return { mime, ...size };
  }

  // Keeps a new photo for the player and returns its version, which goes up with every change
  static async save(userId, buffer) {
    const { mime } = Avatar.inspect(buffer);
    const result = await db.query(
      `INSERT INTO avatars (user_id, image, mime, version) VALUES ($1, $2, $3, 1)
       ON CONFLICT (user_id) DO UPDATE
         SET image = $2, mime = $3, version = avatars.version + 1, updated_at = CURRENT_TIMESTAMP
       RETURNING version`,
      [userId, buffer, mime]
    );
    return result.rows[0].version;
  }

  static async remove(userId) {
    await db.query(
      `UPDATE avatars SET image = NULL, mime = NULL, version = version + 1, updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $1`,
      [userId]
    );
  }

  // The photo to send: { image, mime, version }, or undefined when the player has none
  static async load(userId) {
    const result = await db.query(
      `SELECT image, mime, version FROM avatars WHERE user_id = $1 AND image IS NOT NULL`,
      [userId]
    );
    return result.rows[0];
  }

  // The photo version of each of these players, by id as a string; players without one are
  // left out (0 to the app)
  static async versions(userIds) {
    const ids = userIds.map(Number).filter(Number.isInteger);
    const versions = new Map();
    if (ids.length === 0) return versions;
    const result = await db.query(
      `SELECT user_id, version FROM avatars WHERE user_id = ANY($1::int[]) AND image IS NOT NULL`,
      [ids]
    );
    for (const row of result.rows) versions.set(String(row.user_id), row.version);
    return versions;
  }

  static async versionOf(userId) {
    return (await Avatar.versions([userId])).get(String(userId)) || 0;
  }
}

// The size written in a JPEG's frame header (an SOFn marker), found by walking the markers
// from the start of the file; null when there is none before the image data.
function jpegSize(buffer) {
  let at = 2;
  while (at + 9 <= buffer.length) {
    if (buffer[at] !== 0xff) return null;
    const marker = buffer[at + 1];
    if (marker === 0xff) {
      at += 1; // padding
      continue;
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) {
      at += 2; // markers without a length
      continue;
    }
    if (marker === 0xd9 || marker === 0xda) return null;
    // SOF0 to SOF15, except DHT (C4), JPG (C8) and DAC (CC), which share the range
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      return { height: buffer.readUInt16BE(at + 5), width: buffer.readUInt16BE(at + 7) };
    }
    at += 2 + buffer.readUInt16BE(at + 2);
  }
  return null;
}

module.exports = Avatar;
