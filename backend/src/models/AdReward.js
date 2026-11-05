const db = require('../database/db');
const Coins = require('./Coins');
const { describeWait } = require('./DailyBonus');

// Free coins for watching ads. A player who wants more coins watches ADS_PER_REWARD videos
// (AdMob "rewarded" ads, which the player chooses to watch to the end) and then collects
// REWARD_COINS. That can be done DAILY_REWARDS times a day; the day turns at midnight India
// time, measured by the database's clock.
//
// AdMob tells the phone, not this server, that an ad was watched, so the app reports each one.
// The server keeps the count and the daily limit: a player who sends the reports without
// watching anything still gets no more than one who watches every video.

const ADS_PER_REWARD = 2;
const REWARD_COINS = 1000;
const DAILY_REWARDS = 5;

// Midnight in India (UTC+5:30) is where one day of rewards ends. Tests shorten the day with
// AD_REWARD_DAY_SECONDS so that it turns while they watch.
const DAY_OFFSET_SECONDS = 5.5 * 60 * 60;
const DAY_SECONDS = (() => {
  const value = parseFloat(process.env.AD_REWARD_DAY_SECONDS);
  return Number.isFinite(value) && value > 0 ? value : 24 * 60 * 60;
})();

// Which day it is (a day number, the same for everyone), and the milliseconds until the next
const EPOCH = 'EXTRACT(EPOCH FROM now())';
const TODAY = `FLOOR((${EPOCH} + ${DAY_OFFSET_SECONDS}) / ${DAY_SECONDS})::bigint`;
const RESETS_IN = `CEIL(((FLOOR((${EPOCH} + ${DAY_OFFSET_SECONDS}) / ${DAY_SECONDS}) + 1) * ${DAY_SECONDS}
  - ${DAY_OFFSET_SECONDS} - ${EPOCH}) * 1000)::bigint`;

// A refusal the player can be shown as it is
const refuse = (message, extra) => Object.assign(new Error(message), { forPlayer: true }, extra);

class AdReward {
  // The server does this at every start as well as in migrate.js, so an existing database gets
  // the table without a migration. The row goes with the account (ON DELETE CASCADE).
  // `watched` counts the videos towards the next reward and is kept from one day to the next;
  // `collected` counts the rewards collected on `day`.
  static async ensureSchema() {
    await db.query(`
      CREATE TABLE IF NOT EXISTS ad_rewards (
        user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        day BIGINT NOT NULL,
        watched INTEGER NOT NULL DEFAULT 0,
        collected INTEGER NOT NULL DEFAULT 0
      )
    `);
  }

  // Where the player stands: { adsPerReward, reward (coins), dailyLimit (rewards a day),
  // watched (videos towards the next reward), collected (rewards today), resetsIn (ms until
  // the day turns) }. `queryable` is a transaction's client, to see its own changes.
  static async status(userId, queryable = db) {
    const result = await queryable.query(
      `SELECT COALESCE(r.watched, 0) AS watched,
              CASE WHEN r.day = t.today THEN r.collected ELSE 0 END AS collected,
              t.resets_in
       FROM (SELECT ${TODAY} AS today, ${RESETS_IN} AS resets_in) t
       LEFT JOIN ad_rewards r ON r.user_id = $1`,
      [userId]
    );
    const row = result.rows[0];
    return {
      adsPerReward: ADS_PER_REWARD,
      reward: REWARD_COINS,
      dailyLimit: DAILY_REWARDS,
      watched: row.watched,
      collected: row.collected,
      resetsIn: Math.max(0, Number(row.resets_in)),
    };
  }

  // Counts one video watched to the end. Returns the status afterwards.
  //
  // Throws a refusal (with the status) when the reward is already full and waits to be
  // collected, or when today's rewards have all been collected. The check and the count are
  // one statement, so two reports at the same moment cannot both slip past the limit.
  static async watched(userId) {
    let counted;
    try {
      counted = await db.query(
        `INSERT INTO ad_rewards (user_id, day, watched, collected) VALUES ($1, ${TODAY}, 1, 0)
         ON CONFLICT (user_id) DO UPDATE
           SET collected = CASE WHEN ad_rewards.day = EXCLUDED.day THEN ad_rewards.collected ELSE 0 END,
               day = EXCLUDED.day,
               watched = ad_rewards.watched + 1
           WHERE ad_rewards.watched < ${ADS_PER_REWARD}
             AND (ad_rewards.day <> EXCLUDED.day OR ad_rewards.collected < ${DAILY_REWARDS})
         RETURNING user_id`,
        [userId]
      );
    } catch (error) {
      if (error.code === '23503') throw refuse('User not found', { notFound: true }); // account deleted
      throw error;
    }
    const status = await AdReward.status(userId);
    if (counted.rowCount === 0) throw AdReward.refusal(status);
    return status;
  }

  // Pays the reward once its videos have been watched. Returns { prize, coins (the balance
  // afterwards), ...status }. The claim and the payment happen together or not at all, and a
  // second collect at the same moment finds the videos already used up.
  static async collect(userId) {
    return Coins.transaction(async (client) => {
      const claimed = await client.query(
        `UPDATE ad_rewards
           SET watched = watched - ${ADS_PER_REWARD},
               collected = CASE WHEN day = ${TODAY} THEN collected ELSE 0 END + 1,
               day = ${TODAY}
         WHERE user_id = $1 AND watched >= ${ADS_PER_REWARD}
           AND (day <> ${TODAY} OR collected < ${DAILY_REWARDS})
         RETURNING user_id`,
        [userId]
      );
      if (claimed.rowCount === 0) throw AdReward.refusal(await AdReward.status(userId, client));

      const balance = await Coins.move(client, userId, null, 'ad_reward', REWARD_COINS);
      if (balance === null) throw refuse('User not found', { notFound: true }); // rolls the claim back
      return { prize: REWARD_COINS, coins: balance, ...(await AdReward.status(userId, client)) };
    });
  }

  // Why a video was not counted or a reward not paid, for the player, with the status
  static refusal(status) {
    if (status.collected >= DAILY_REWARDS) {
      return refuse(
        `That is all the free coins for today. More videos in ${describeWait(status.resetsIn)}.`,
        { limitReached: true, status }
      );
    }
    if (status.watched >= ADS_PER_REWARD) {
      return refuse('Your coins are waiting: collect them first.', { status });
    }
    const left = ADS_PER_REWARD - status.watched;
    return refuse(`Watch ${left} more ${left === 1 ? 'video' : 'videos'} to collect the coins.`, { status });
  }
}

AdReward.ADS_PER_REWARD = ADS_PER_REWARD;
AdReward.REWARD_COINS = REWARD_COINS;
AdReward.DAILY_REWARDS = DAILY_REWARDS;

module.exports = AdReward;
