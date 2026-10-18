// What a new account has to give: a username, a mobile number from any country and a
// password. When SMS codes are on (src/sms/PhoneVerification.js) a code sent to the number
// proves it is the player's own. The app checks the same rules before it sends anything
// (godot/net/account_rules.gd); keep the two in step. Only the server's answer counts.

// An Indian mobile number: ten digits, the first one 6 to 9, however the country is written in front
const INDIAN_MOBILE_PATTERN = /^(?:\+91|91|0)?([6-9]\d{9})$/;
// Any other country: + and the country code, 8 to 15 digits in all
const INTERNATIONAL_PATTERN = /^\+[1-9]\d{7,14}$/;
const MAX_USERNAME_LENGTH = 20; // what the form allows
const MIN_PASSWORD_LENGTH = 6;
const CODE_PATTERN = /^\d{6}$/;

const MESSAGES = {
  phone: 'Enter a valid mobile number. For a number outside India, start with + and the country code.',
  madeUpPhone: 'That does not look like a real mobile number. Enter your own number: we send a code to it by SMS.',
  username: `Choose a username of 1 to ${MAX_USERNAME_LENGTH} characters`,
  password: `Choose a password of at least ${MIN_PASSWORD_LENGTH} characters`,
  code: 'Enter the 6-digit code we sent to your phone by SMS',
};

// The number as it is stored, or '' if it is not a mobile number. An Indian number becomes
// its ten digits ("+91 98765 43210" and "098765-43210" are both "9876543210"), so that it
// can be typed any of those ways at login; a number from elsewhere keeps its + and country code.
function cleanPhone(value) {
  const typed = typeof value === 'string' ? value.replace(/[\s\-().]/g, '') : '';
  const indian = INDIAN_MOBILE_PATTERN.exec(typed);
  if (indian) return indian[1];
  return INTERNATIONAL_PATTERN.test(typed) ? typed : '';
}

// The stored number in the international form an SMS service needs: "+919876543210".
function toE164(phone) {
  return phone.startsWith('+') ? phone : `+91${phone}`;
}

// The stored number as people read it: "+91 98765 43210", or "+447700900123" as it is.
function displayPhone(phone) {
  return phone.startsWith('+') ? phone : `+91 ${phone.slice(0, 5)} ${phone.slice(5)}`;
}

// True for numbers people type when they do not want to give theirs: one digit over and over
// (9999999999), a short pattern repeated (9898989898, 9879879879) or a straight run of digits
// (9876543210). `phone` is a stored number; only its own digits count, not the country code.
function looksMadeUp(phone) {
  const digits = phone.startsWith('+') ? phone.slice(-10) : phone;
  for (let period = 1; period <= 3; period++) {
    const pattern = digits.slice(0, period);
    if (pattern.repeat(Math.ceil(digits.length / period)).startsWith(digits)) return true;
  }
  const steps = [...digits].slice(1).map((digit, index) => (Number(digit) - Number(digits[index]) + 10) % 10);
  return steps.every((step) => step === 1) || steps.every((step) => step === 9);
}

// The six digits of an SMS code as typed (spaces dropped), or '' if it is not one.
function cleanCode(value) {
  const code = typeof value === 'string' ? value.replace(/\s/g, '') : '';
  return CODE_PATTERN.test(code) ? code : '';
}

module.exports = {
  cleanPhone, toE164, displayPhone, looksMadeUp, cleanCode,
  MESSAGES, MAX_USERNAME_LENGTH, MIN_PASSWORD_LENGTH,
};
