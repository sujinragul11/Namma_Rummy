const config = require('./config');

// The web pages the app stores ask for: privacy policy, terms, and a way to delete an
// account without installing the app. They are plain HTML without scripts.

const UPDATED = '14 October 2026';

const escapeHtml = (text) => String(text)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

const app = () => escapeHtml(config.appName);
const owner = () => escapeHtml(config.legalOwner || 'the publisher of this app');
const contact = () => {
  const email = escapeHtml(config.supportEmail || 'the support address in the app store listing');
  return config.supportEmail ? `<a href="mailto:${email}">${email}</a>` : email;
};

const layout = (title, body) => `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)} · ${app()}</title>
<style>
  body { margin: 0; background: #f4f6f4; color: #212121; font: 17px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  header { background: #1b5e20; color: #fff; padding: 20px 16px; }
  header a { color: #fff; text-decoration: none; font-size: 20px; font-weight: 600; }
  main { max-width: 720px; margin: 0 auto; padding: 8px 16px 48px; }
  h1 { font-size: 28px; margin: 24px 0 4px; }
  h2 { font-size: 20px; margin: 28px 0 6px; }
  .updated { color: #666; margin-top: 0; }
  a { color: #1565c0; }
  label { display: block; margin: 16px 0 4px; font-weight: 600; }
  input { box-sizing: border-box; width: 100%; padding: 12px; font: inherit; border: 1px solid #bdbdbd; border-radius: 8px; }
  button { margin-top: 20px; padding: 12px 22px; font: inherit; font-weight: 600; color: #fff; background: #c62828; border: 0; border-radius: 22px; cursor: pointer; }
  .notice { padding: 14px 16px; border-radius: 8px; margin-top: 20px; }
  .notice.error { background: #fdecea; color: #b71c1c; }
  .notice.done { background: #e8f5e9; color: #1b5e20; }
  footer { max-width: 720px; margin: 0 auto; padding: 0 16px 32px; color: #666; font-size: 15px; }
  footer a { margin-right: 16px; }
</style>
</head>
<body>
<header><a href="/">${app()}</a></header>
<main>
${body}
</main>
<footer>
  <a href="/privacy">Privacy policy</a><a href="/terms">Terms of use</a><a href="/delete-account">Delete account</a>
</footer>
</body>
</html>`;

const home = () => layout('Home', `
<h1>${app()}</h1>
<p>Classic 13-card rummy in real time. Tap Play Now to be seated with players near you, or
open a private table and share its room code with your friends. Pool, deals and Close Joker
rummy.</p>
<p>The game is free and is played for fun only, with play coins that every player gets for
free. Coins have no cash value: there is no real-money play, nothing to buy and nothing to cash out.</p>
<p>Questions? Write to ${contact()}.</p>
`);

const privacy = () => layout('Privacy policy', `
<h1>Privacy policy</h1>
<p class="updated">Last updated: ${UPDATED}</p>
<p>This policy explains what ${app()} ("the app"), published by ${owner()}, stores about you
and what you can do about it.</p>

<h2>What we collect</h2>
<ul>
  <li><strong>Account details you give us:</strong> a username, an email address, a phone
  number and a password. The password is stored only as a one-way hash; we cannot read it.</li>
  <li><strong>Game records:</strong> the games you played, your seat, your final cards, your
  score and whether you won. Other players at your table see your username and your play.</li>
  <li><strong>Play coins:</strong> your balance of coins, and the coins you paid in, got back
  or won at each table. Coins are tokens of the game and have nothing to do with money.</li>
  <li><strong>Friends:</strong> the players you add as friends inside the app and the friend
  requests you send or receive. This is not your phone's contact list, which the app never
  reads. Players you have accepted as friends can see whether you are online or in a game.</li>
  <li><strong>Profile photo, if you add one:</strong> the app turns the picture you pick into a
  small square photo on your phone and sends us only that. The players at your table, your
  friends and the players you exchange friend requests with see it. You can remove it at any
  time in <em>Settings</em>.</li>
  <li><strong>Technical data:</strong> like any internet service, the server receives your IP
  address when the app connects, and it may appear in short-lived server logs.</li>
</ul>
<p>The app does not ask for your location, contacts, camera or microphone, and it does not
read your photo library: it opens only the one picture you pick when you choose a profile
photo. It contains no third-party analytics.</p>

<h2>Ads</h2>
<p>The Android app shows full-screen ads at a few moments: before you sit down at a table,
in the break between rounds, and after a game. The ads come from Google AdMob, a service of
Google. To choose and count ads, Google's software in the app collects from your device:
its advertising ID, your IP address (from which an approximate location can be worked out),
information about the device and the app, and how you interact with the ads. Google
receives this directly and uses it as described in
<a href="https://policies.google.com/technologies/partner-sites">How Google uses information
from sites or apps that use its services</a>. We do not send Google your account details,
your games or your friends list.</p>
<p>If you are in the European Economic Area, the United Kingdom or Switzerland, the app asks
for your consent before ads may be personalised, the first time it starts. You can change
that choice at any time under <em>Settings &gt; Privacy choices for ads</em>. Anywhere, you can
reset your advertising ID or turn off ad personalisation in your phone's settings
(<em>Settings &gt; Google &gt; Ads</em> on most Android phones).</p>

<h2>How we use it</h2>
<p>Only to run the game: to log you in, seat you at a table, show your name to the players you
play with, keep your results, let you find and invite your friends, and protect the service
against abuse. We do not sell your data, and we do not use what is stored on our servers for
advertising.</p>

<h2>Who receives it</h2>
<p>Your account and game data are kept on servers run for us by our hosting provider. We do
not share them with anyone else, unless the law requires us to. The ad data described under
<em>Ads</em> goes from your device to Google directly.</p>

<h2>On your device</h2>
<p>The app keeps your login on your device so you stay signed in. Logging out removes it.</p>

<h2>How long we keep it, and deleting it</h2>
<p>We keep your account until you delete it. You can delete it at any time, in the app
(<em>Delete account</em> in your profile) or on the web at
<a href="/delete-account">the account deletion page</a>. Deleting removes your username, email
address, phone number, password hash, profile photo, your game results, your coins and their
history, and your friends list straight away.
Records of the tables themselves stay, without anything that identifies you.</p>

<h2>Children</h2>
<p>The app is meant for adults. It is not directed at children, and we do not knowingly
collect their data. If you believe a child has created an account, write to us and we will
delete it.</p>

<h2>Your rights</h2>
<p>You can ask for a copy of your data, ask us to correct it, or ask us to delete it by writing
to ${contact()}.</p>

<h2>Changes</h2>
<p>If this policy changes, the new version will be published on this page with a new date.</p>

<h2>Contact</h2>
<p>${owner()}<br>${contact()}</p>
`);

const terms = () => layout('Terms of use', `
<h1>Terms of use</h1>
<p class="updated">Last updated: ${UPDATED}</p>
<p>By using ${app()} ("the app"), published by ${owner()}, you agree to these terms.</p>

<h2>The game</h2>
<p>The app is a card game played for entertainment only. It offers no real-money play, no
purchases and no prizes, and nothing in it can be exchanged for money or goods. It is free,
and the Android app shows ads from Google AdMob (see the privacy policy).</p>

<h2>Play coins</h2>
<p>Every account gets play coins for free. A table can have an entry in coins, which each
player pays on sitting down; the winner of the game takes the coins that were paid in. A
Points table can instead be played for coins a point: each loser pays the winner their points
times that value, out of coins held while the game is played. Coins
are tokens of the game and nothing else: they have no cash value and cannot be bought, sold,
given to another player, or exchanged for money, goods or services. They are lost when the
account is deleted. We may change how coins work and may adjust or reset balances.</p>

<h2>Your account</h2>
<p>The app is meant for players aged 18 or over. You are responsible for your account and for
keeping your password to yourself. Give accurate details when you register, and use one
account per person.</p>

<h2>Fair play</h2>
<p>Do not cheat, use automated players, interfere with the service, or choose a username or
profile photo that is offensive, sexual, violent, or impersonates someone else. We may remove
such a photo, and suspend or remove accounts that do this.</p>

<h2>Availability</h2>
<p>The app is provided as it is. We try to keep it running but do not promise that it will
always be available or free of errors, and we may change or stop it. To the extent the law
allows, we are not liable for losses arising from its use.</p>

<h2>Ending</h2>
<p>You can stop using the app and delete your account at any time, in the app or on
<a href="/delete-account">the account deletion page</a>.</p>

<h2>Contact</h2>
<p>${owner()}<br>${contact()}</p>
`);

const deleteAccount = ({ error = '', done = false } = {}) => layout('Delete account', done ? `
<h1>Account deleted</h1>
<p class="notice done">Your ${app()} account and the personal data that belonged to it have been deleted.</p>
` : `
<h1>Delete your account</h1>
<p>This permanently deletes your ${app()} account: your username, email address, phone number,
password, game results, coins and friends list. It cannot be undone.</p>
<p>You can also do this in the app: tap your name on the main menu to open your profile, and choose <em>Delete account</em>.</p>
${error ? `<p class="notice error">${escapeHtml(error)}</p>` : ''}
<form method="post" action="/delete-account">
  <label for="identifier">Email, phone or username</label>
  <input id="identifier" name="identifier" autocomplete="username" required>
  <label for="password">Password</label>
  <input id="password" name="password" type="password" autocomplete="current-password" required>
  <button type="submit">Delete my account</button>
</form>
<p>Forgotten your password? Write to ${contact()} from the email address of your account.</p>
`);

module.exports = { home, privacy, terms, deleteAccount };
