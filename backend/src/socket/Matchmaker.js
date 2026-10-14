// "Play Now": finds opponents without a room code or a host. Everyone looking for the same kind
// of table (game, seats, entry) waits in one queue, and a table is made the moment enough of
// them are there. Players from the same region, which is the time zone their phone is set to,
// are matched first; the longer a player waits, the wider the search goes:
//   first  REGION_ONLY  only players in the same time zone
//   then   NEARBY       up to three hours either way
//   then   everywhere
// A table that cannot fill all its seats starts a short while after its second player is
// found, with whoever is there by then.
//
// This class only keeps the queue and decides who sits together. Seating them (the table,
// the entries, the game) is done by the `onMatch` callback the SocketManager passes in.

const seconds = (name, fallback) => {
  const value = parseFloat(process.env[name]);
  return (Number.isFinite(value) && value >= 0 ? value : fallback) * 1000;
};

const REGION_ONLY_MS = seconds('MATCH_REGION_SECONDS', 8);
const NEARBY_MS = seconds('MATCH_NEARBY_SECONDS', 16);
const FILL_MS = seconds('MATCH_FILL_SECONDS', 15);
const NEARBY_MINUTES = 180;
const TICK_MS = 1000;
const DAY_MINUTES = 1440;

const REACH = { region: 0, nearby: NEARBY_MINUTES, everywhere: Infinity };

// The time zone as people write it: 330 -> "UTC+5:30"
const regionLabel = (offset) => {
  if (offset === null) return '';
  const sign = offset < 0 ? '-' : '+';
  const minutes = Math.abs(offset);
  const rest = minutes % 60;
  return `UTC${sign}${Math.floor(minutes / 60)}${rest ? `:${String(rest).padStart(2, '0')}` : ''}`;
};

// Minutes between two time zones, the short way round the globe. A player whose time zone
// is unknown is near everyone.
const distance = (a, b) => {
  if (a.offset === null || b.offset === null) return 0;
  const apart = Math.abs(a.offset - b.offset) % DAY_MINUTES;
  return Math.min(apart, DAY_MINUTES - apart);
};

const scopeOf = (waited) => {
  if (waited < REGION_ONLY_MS) return 'region';
  if (waited < NEARBY_MS) return 'nearby';
  return 'everywhere';
};

class Matchmaker {
  // onMatch(tickets) seats the players and resolves to the tickets that could not be seated
  // and should go on searching. notify(userId, event, payload) sends a player an event.
  constructor({ onMatch, notify }) {
    this.onMatch = onMatch;
    this.notify = notify;
    this.tickets = new Map(); // userId -> ticket, oldest first
    this.seating = new Map(); // userId -> ticket being seated at a table right now
    this.lastSent = new Map(); // userId -> the last status sent, to send only what changed
    this.timer = null;
  }

  static keyOf({ gameType, maxPlayers, stake, pointValue }) {
    return `${gameType}:${maxPlayers}:${stake}:${pointValue}`;
  }

  // `options` are already checked: { gameType, maxPlayers, stake, pointValue, offset }, offset
  // being the phone's time zone in minutes east of UTC, or null when unknown.
  // Searching again for the same table (after a reconnect) keeps the player's place in the queue.
  find(userId, username, options) {
    const key = Matchmaker.keyOf(options);
    const previous = this.tickets.get(userId);
    const seating = this.seating.get(userId);
    if (seating && !seating.cancelled) return; // a table is being made for them this moment

    this.tickets.delete(userId); // re-inserted below, so the map stays in arrival order
    this.lastSent.delete(userId);
    const keepPlace = previous && previous.key === key;
    this.tickets.set(userId, {
      userId,
      username,
      key,
      gameType: options.gameType,
      maxPlayers: options.maxPlayers,
      stake: options.stake,
      pointValue: options.pointValue,
      offset: options.offset,
      since: keepPlace ? previous.since : Date.now(),
      groupSince: null, // when this player, leading a group, first had company
      cancelled: false
    });
    this.run();
  }

  // Returns true if the player was searching
  cancel(userId) {
    const seating = this.seating.get(userId);
    if (seating) seating.cancelled = true;
    const ticket = this.tickets.get(userId);
    this.tickets.delete(userId);
    this.lastSent.delete(userId);
    if (ticket) this.run(); // the others in that queue see one player fewer
    return Boolean(ticket || seating);
  }

  isSearching(userId) {
    return this.tickets.has(userId);
  }

  // The tables being searched for and how many are searching for each, for the status line
  queueSizes() {
    const sizes = new Map();
    for (const ticket of this.tickets.values()) {
      sizes.set(ticket.key, (sizes.get(ticket.key) || 0) + 1);
    }
    return sizes;
  }

  // One pass over every queue: make the tables that can be made, tell everyone else where
  // their search stands. Runs on every arrival and departure, and every second meanwhile,
  // because waiting widens the search.
  run() {
    const now = Date.now();
    const queues = new Map();
    for (const ticket of this.tickets.values()) {
      if (!queues.has(ticket.key)) queues.set(ticket.key, []);
      queues.get(ticket.key).push(ticket);
    }

    for (const queue of queues.values()) {
      queue.sort((a, b) => a.since - b.since);
      const free = queue.slice();
      while (free.length > 0) {
        // The one who has waited longest leads; their reach decides who can join them
        const leader = free.shift();
        const reach = REACH[scopeOf(now - leader.since)];
        const mates = free
          .filter(ticket => distance(leader, ticket) <= reach)
          .sort((a, b) => distance(leader, a) - distance(leader, b) || a.since - b.since)
          .slice(0, leader.maxPlayers - 1);
        for (const mate of mates) free.splice(free.indexOf(mate), 1);

        const group = [leader, ...mates];
        if (group.length < 2) {
          leader.groupSince = null;
        } else if (leader.groupSince === null) {
          leader.groupSince = now;
        }

        const full = group.length >= leader.maxPlayers;
        const due = leader.groupSince !== null && now - leader.groupSince >= FILL_MS;
        if (full || due) {
          this.seat(group);
          continue;
        }

        const startsIn = leader.groupSince === null ? null : Math.max(0, leader.groupSince + FILL_MS - now);
        for (const ticket of group) {
          this.sendStatus(ticket, now, { found: group.length, startsIn, inQueue: queue.length });
        }
      }
    }

    this.keepTicking();
  }

  // Takes the group out of the queue and hands it over to be seated. Whoever could not be
  // seated (no coins any more, say) is told by onMatch; the others go back to searching.
  seat(group) {
    for (const ticket of group) {
      this.tickets.delete(ticket.userId);
      this.lastSent.delete(ticket.userId);
      this.seating.set(ticket.userId, ticket);
    }

    Promise.resolve()
      .then(() => this.onMatch(group))
      .catch((error) => {
        console.error('Failed to seat a match:', error.message);
        return group; // all of them search on
      })
      .then((unseated) => {
        for (const ticket of group) {
          if (this.seating.get(ticket.userId) === ticket) this.seating.delete(ticket.userId);
        }
        for (const ticket of unseated || []) {
          if (ticket.cancelled || this.tickets.has(ticket.userId)) continue;
          ticket.groupSince = null;
          this.tickets.set(ticket.userId, ticket);
        }
        // in arrival order again, which run() relies on for leading groups fairly
        const ordered = Array.from(this.tickets.values()).sort((a, b) => a.since - b.since);
        this.tickets = new Map(ordered.map(ticket => [ticket.userId, ticket]));
        if (unseated && unseated.length > 0) this.run();
      });
  }

  // Sends a status only when something the player sees has changed; the app counts the
  // seconds down by itself.
  sendStatus(ticket, now, { found, startsIn, inQueue }) {
    const scope = scopeOf(now - ticket.since);
    const last = this.lastSent.get(ticket.userId);
    // a countdown that runs as expected needs no message every second
    if (last && last.found === found && last.scope === scope && last.inQueue === inQueue
      && (startsIn === null) === (last.startsAt === null)
      && (startsIn === null || Math.abs(now + startsIn - last.startsAt) < 1500)) {
      return;
    }
    this.lastSent.set(ticket.userId, {
      found, scope, inQueue, startsAt: startsIn === null ? null : now + startsIn
    });

    this.notify(ticket.userId, 'matchStatus', {
      searching: true,
      gameType: ticket.gameType,
      maxPlayers: ticket.maxPlayers,
      stake: ticket.stake,
      pointValue: ticket.pointValue,
      found, // players for this table so far, the searching player included
      needed: ticket.maxPlayers,
      inQueue, // everyone searching for this kind of table right now
      scope, // 'region', 'nearby' or 'everywhere'
      region: regionLabel(ticket.offset),
      waited: now - ticket.since,
      startsIn // ms until the table starts with the players found, or null
    });
  }

  keepTicking() {
    if (this.tickets.size > 0 && !this.timer) {
      this.timer = setInterval(() => this.run(), TICK_MS);
      if (this.timer.unref) this.timer.unref();
    } else if (this.tickets.size === 0 && this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
  }
}

Matchmaker.regionLabel = regionLabel;
Matchmaker.distance = distance;
Matchmaker.scopeOf = scopeOf;
Matchmaker.REGION_ONLY_MS = REGION_ONLY_MS;
Matchmaker.NEARBY_MS = NEARBY_MS;
Matchmaker.FILL_MS = FILL_MS;

module.exports = Matchmaker;
