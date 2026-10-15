# TODO

## Implement “join by roomCode” flow
- [x] Identify mismatch: client constructs fake `gameId` from `roomCode`, backend expects real backend-generated `gameId`
- [x] Add backend socket handler: `joinGameByRoomCode` (resolve real game id via DB and/or Redis)
- [x] Update mobile HomeScreen to emit `joinGameByRoomCode` instead of `joinGame`
- [x] Run backend and verify second player can join and receive `gameState` without socket `error`

## Godot client (`godot/`)
- [x] Project, Socket.IO client, login / register, lobby, card table, results (runs on PC)
- [ ] Play it by hand with two windows (so far checked by automated runs and screenshots)
- [x] Android build: Android SDK, JDK 17 and Godot export templates installed, export presets, `build-android.bat`
- [x] Namma Rummy logo on the home screen, boot splash and app icons made from it
- [x] Phone-sized layout: finger-sized buttons and cards, wider cards on wider phones
- [x] Carry cards with a finger: onto a group, between groups or beside the ends for a new group,
      onto the open pile to discard (`tests/ui_tour` plays the whole game with simulated touches)
- [x] Animations: deal, draw, discard, the other players' moves, turn clock ring, result with confetti
- [x] Music (menu and table tunes) and sound effects for every move, with on/off buttons
- [x] Big effects: round banner, meld sparkles, declare impact, winner's fireworks, low-time warning
- [x] Close Joker 240: pool rules with a 240 limit; the joker lies face down for each player
      until their hand holds a pure sequence (server side, so the client cannot peek)
- [x] Sign-up needs an email address and a mobile number, both checked for their form
      (`backend/src/validation.js`, mirrored in `godot/net/account_rules.gd`)
- [ ] Sign-up, next: neither is verified (no SMS code, no email link), so a made-up number
      that looks right is accepted
- [x] After a valid declaration the others get 15 seconds to arrange their cards and Submit
- [x] Arranging time looked at on the PC at 1280x720 (both sides: the declarer waiting, and the
      other player with the Submit button). Still to see on a real phone
- [ ] Listen to the music and effects and adjust: they were written and checked by measurement
      (tuning, loudness, clean loops), not by ear. Loudness per effect is in `autoload/sound.gd`
- [ ] Try on a real phone what could only be written, not run, on the PC: the form moving above
      the on-screen keyboard, the back button, padding around the notch, vibration
- [x] Friends: add by username, requests (accept / decline / block), who is online or in a game,
      invite a friend from the lobby, room code on WhatsApp, "played with recently" suggestions
- [x] After a game: "Play again" opens a table with the same rules and entry and calls the same
      players to it; "Add friend" beside an opponent on the result screen
- [ ] Friends, next: an invitation only reaches a friend whose game is open (no push message
      when the app is closed)
- [x] Profile screen (home menu > Profile): games played and won, win rate, coins; the username
      and the email address can be changed there
- [x] Home menu laid out like a card-game lobby (2026-10-10): player and coins in a top bar with
      round buttons (rules, music, sound, profile), big tiles for Points / Pool / Close Joker /
      Play with friends, a bottom bar. A tile opens the table setup; Delete account is in the profile
- [x] Table screen in the same style (2026-10-10): oval felt with a wooden rim, opponents seated
      around the far side in dark pills, "Declare here" slot (tap, or drop the finishing card on it),
      the joker tucked under a stacked deck with its count, info pills top-left, own avatar and coins
      bottom-left. The hand, its groups, dragging and all animations are unchanged
- [ ] Menu ideas not built, on purpose: a coin shop or "+ coins" (coins cannot be bought), Deals
      Rummy (not a mode here), Ranks and More Games (nothing behind them yet)
- [ ] Look at the coin screens (menu, lobby, table, result) at the wide phone shape, 1600x720:
      seen at 1280x720, checked only by position at the wide shape
- [ ] Remove `mobile/` once the Godot client has replaced it

## Still open
- [ ] Play a full game on two real phones (so far verified with simulated players and in a browser)
- [x] Games and lobbies survive a restart of the server: kept in the database after every move,
      loaded again at startup (`tests/server_restart` kills the server mid-game and plays on)
- [ ] Try the Redis restore path against a real Redis server (no longer needed for restarts)
- [x] Play coins: 50,000 at sign-up, tables with an entry of 1,000 to 50,000 (or free), the
      winner takes the pot (`backend/src/models/Coins.js`, `tests/coins_e2e`)
- [ ] Coins, to decide: a player who has lost everything can only play free tables. There is
      no daily bonus or refill, and nothing sells coins. Selling coins or paying them out would
      make it real-money play, for which both stores and Indian law have much stricter rules
- [x] The old wallet idea is out of the code and out of every server answer, and the route that
      let a player raise their own win counts (`POST /api/user/stats`) is removed. The unused
      `wallet` column itself stays in the `users` table: dropping it gains nothing
- [ ] Before going public: set a real `JWT_SECRET` in `backend/.env` (with `NODE_ENV=production`
      the server now refuses to start without it)

## Store release (see "Publishing to Google Play and the App Store" in README.md)
- [x] Account deletion in the app and on the web, privacy policy and terms pages
- [x] Store builds: fixed server address, no Server field, export presets for Android and iOS
- [x] Store listing texts, form answers, icon and feature graphic in `store/`
- [ ] Put the backend on a public server with https; fill in `LEGAL_OWNER` and `SUPPORT_EMAIL`
- [ ] Set `RELEASE_SERVER_URL` in `godot/autoload/config.gd`, then run `build-android.bat`
- [ ] Google Play Console account; Apple Developer Program account and its Team ID
- [ ] AdMob account: the App ID into `godot/project.godot` ([admob] general/android/app_id)
      and one interstitial ad unit into `RELEASE_INTERSTITIAL_ID` in `godot/autoload/config.gd`;
      until then store builds show no ads (see "Ads" in README.md)
- [ ] See Google's test ads on a real phone with a debug build: before sitting down, between
      rounds, after a finished game. On the PC only the timing was tested (stand-in ads), and
      an Android 16 emulator only got as far as "Initialized AdMob" (too slow on this PC)
- [ ] A Mac with Xcode for the last step of the iOS build
- [ ] Screenshots for both stores, taken from the finished game
- [ ] "Forgot password": there is no way yet for a player to reset a password

