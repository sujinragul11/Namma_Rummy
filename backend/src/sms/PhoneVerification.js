// Proves that a mobile number belongs to the player who typed it: the server sends a 6-digit
// code by SMS and the player types it back. Asked for when an account is made, and before a
// forgotten password is replaced.
//
// Who sends the SMS is set in the environment:
//   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_VERIFY_SERVICE_SID
//       Twilio Verify (https://www.twilio.com/docs/verify). It makes the codes, sends them to
//       any country, keeps them for 10 minutes and allows 5 tries; codes to India follow the
//       DLT rules without registering anything.
//   SMS_TEST_CODE=123456 (refused in production, see config.js)
//       No SMS is sent; that code is the right one for every number. For the tests.
//   neither
//       Numbers are not verified: accounts are made without a code, and a forgotten password
//       cannot be reset by SMS. The server says so when it starts.
// SMS_RESEND_SECONDS sets how long a number waits before another code is sent (default 30).

const { toE164 } = require('../validation');

const TWILIO_SID = process.env.TWILIO_ACCOUNT_SID || '';
const TWILIO_TOKEN = process.env.TWILIO_AUTH_TOKEN || '';
const TWILIO_SERVICE = process.env.TWILIO_VERIFY_SERVICE_SID || '';
const TEST_CODE = process.env.SMS_TEST_CODE || '';
const RESEND_MS = (Number(process.env.SMS_RESEND_SECONDS) || 30) * 1000;
const CODE_LIFETIME_MS = 10 * 60 * 1000; // as long as Twilio keeps a code
const TEST_TRIES = 5;
const TWILIO_TIMEOUT_MS = 10000;

const provider = TWILIO_SID && TWILIO_TOKEN && TWILIO_SERVICE ? 'twilio' : TEST_CODE ? 'test' : 'off';

const lastSent = new Map(); // number -> Date.now() of the last code sent to it
const testCodes = new Map(); // number -> { expiresAt, triesLeft }: the codes "sent" in test mode

// What went wrong, in words for the player. Twilio's error codes:
// https://www.twilio.com/docs/api/errors
const TWILIO_ERRORS = {
  60200: 'That mobile number cannot get SMS. Check the number and the country code.',
  21211: 'That mobile number cannot get SMS. Check the number and the country code.',
  21614: 'That number cannot get SMS. Enter a mobile number.',
  60203: 'Too many codes were sent to this number. Wait 10 minutes and try again.',
  60202: 'Too many wrong codes. Ask for a new code.',
  60205: 'That number cannot get SMS. Enter a mobile number.',
  60410: 'Codes cannot be sent to this number. Please contact support.',
  60605: 'Sending codes to this country is not available yet.',
  21408: 'Sending codes to this country is not available yet.',
};
const SEND_FAILED = 'The code could not be sent. Please try again in a moment.';
const CHECK_FAILED = 'The code could not be checked. Please try again in a moment.';

function enabled() {
  return provider !== 'off';
}

// Forgets numbers that are done with, so the maps do not grow for ever.
function prune(now) {
  for (const [phone, at] of lastSent) if (now - at > CODE_LIFETIME_MS) lastSent.delete(phone);
  for (const [phone, entry] of testCodes) if (now > entry.expiresAt) testCodes.delete(phone);
}

async function twilio(path, fields) {
  const response = await fetch(`https://verify.twilio.com/v2/Services/${TWILIO_SERVICE}/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`${TWILIO_SID}:${TWILIO_TOKEN}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(fields),
    signal: AbortSignal.timeout(TWILIO_TIMEOUT_MS),
  });
  const data = await response.json().catch(() => ({}));
  return { status: response.status, data };
}

// Sends a code to `phone` (a number as validation.cleanPhone stores it).
// Returns { ok: true, resendSeconds } or { ok: false, status, error, waitSeconds? }.
async function send(phone) {
  const now = Date.now();
  prune(now);
  const wait = RESEND_MS - (now - (lastSent.get(phone) || 0));
  if (wait > 0) {
    const waitSeconds = Math.ceil(wait / 1000);
    return { ok: false, status: 429, waitSeconds, error: `A code was sent a moment ago. You can ask for another in ${waitSeconds} seconds.` };
  }

  if (provider === 'test') {
    testCodes.set(phone, { expiresAt: now + CODE_LIFETIME_MS, triesLeft: TEST_TRIES });
  } else {
    try {
      const { status, data } = await twilio('Verifications', { To: toE164(phone), Channel: 'sms' });
      if (status >= 300) {
        console.warn(`⚠️  SMS code to ${toE164(phone)} refused by Twilio: ${status} ${data.code} ${data.message}`);
        return { ok: false, status: status === 429 ? 429 : 400, error: TWILIO_ERRORS[data.code] || SEND_FAILED };
      }
    } catch (error) {
      console.error('SMS code could not be sent:', error.message);
      return { ok: false, status: 503, error: SEND_FAILED };
    }
  }
  lastSent.set(phone, now);
  return { ok: true, resendSeconds: Math.ceil(RESEND_MS / 1000) };
}

// Checks a code typed for `phone`. Returns { ok: true } for the right code (it cannot be used
// again), otherwise { ok: false, status, error }.
async function check(phone, code) {
  if (provider === 'test') {
    const entry = testCodes.get(phone);
    if (!entry || Date.now() > entry.expiresAt) return { ok: false, status: 400, error: expiredMessage() };
    if (code === TEST_CODE) {
      testCodes.delete(phone);
      lastSent.delete(phone); // a new code may be asked for at once, e.g. to reset the password
      return { ok: true };
    }
    entry.triesLeft -= 1;
    if (entry.triesLeft <= 0) {
      testCodes.delete(phone);
      return { ok: false, status: 429, error: TWILIO_ERRORS[60202] };
    }
    return { ok: false, status: 400, error: wrongMessage() };
  }

  try {
    const { status, data } = await twilio('VerificationCheck', { To: toE164(phone), Code: code });
    if (status < 300 && data.status === 'approved') {
      lastSent.delete(phone);
      return { ok: true };
    }
    if (status < 300) return { ok: false, status: 400, error: wrongMessage() };
    // 404: no code is waiting for this number any more (it ran out, or was used, or had too many tries)
    if (status === 404) return { ok: false, status: 400, error: expiredMessage() };
    console.warn(`⚠️  SMS code check for ${toE164(phone)} refused by Twilio: ${status} ${data.code} ${data.message}`);
    return { ok: false, status: status === 429 ? 429 : 400, error: TWILIO_ERRORS[data.code] || CHECK_FAILED };
  } catch (error) {
    console.error('SMS code could not be checked:', error.message);
    return { ok: false, status: 503, error: CHECK_FAILED };
  }
}

function wrongMessage() {
  return 'That code is not right. Check the SMS and try again.';
}

function expiredMessage() {
  return 'That code has run out. Ask for a new one.';
}

// One line for the server's start, so whoever runs it knows whether numbers are checked.
function describe() {
  if (provider === 'twilio') return '📱 Sign-up codes are sent by SMS (Twilio Verify)';
  if (provider === 'test') return `📱 Sign-up codes: TEST mode, the code is always ${TEST_CODE}; no SMS is sent`;
  return '⚠️  Phone numbers are NOT verified: set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_VERIFY_SERVICE_SID to send sign-up codes by SMS';
}

module.exports = { enabled, send, check, describe };
