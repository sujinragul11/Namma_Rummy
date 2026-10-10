// What a new account has to give: an email address and a mobile number, both of them.
// The app checks the same rules before it sends anything (godot/scenes/home.gd); keep the
// two in step. Only the server's answer counts.

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX_EMAIL_LENGTH = 100; // the width of the column
// An Indian mobile number: ten digits, the first one 6 to 9, however the country is written in front
const INDIAN_MOBILE_PATTERN = /^(?:\+91|91|0)?([6-9]\d{9})$/;
// Any other country: + and the country code, 8 to 15 digits in all
const INTERNATIONAL_PATTERN = /^\+[1-9]\d{7,14}$/;

const MESSAGES = {
  email: 'Enter a valid email address',
  phone: 'Enter a valid mobile number: 10 digits, or + and the country code for a number outside India'
};

// The address in lower case, or '' if it is not an email address.
function cleanEmail(value) {
  const email = typeof value === 'string' ? value.trim().toLowerCase() : '';
  return email.length <= MAX_EMAIL_LENGTH && EMAIL_PATTERN.test(email) ? email : '';
}

// The number as it is stored, or '' if it is not a mobile number. An Indian number becomes
// its ten digits ("+91 98765 43210" and "098765-43210" are both "9876543210"), so that it
// can be typed any of those ways at login; a number from elsewhere keeps its + and country code.
function cleanPhone(value) {
  const typed = typeof value === 'string' ? value.replace(/[\s\-().]/g, '') : '';
  const indian = INDIAN_MOBILE_PATTERN.exec(typed);
  if (indian) return indian[1];
  return INTERNATIONAL_PATTERN.test(typed) ? typed : '';
}

module.exports = { cleanEmail, cleanPhone, MESSAGES };
