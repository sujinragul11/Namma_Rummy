# Rummy Multiplayer Game

A real-time multiplayer Rummy card game built with Node.js backend and React Native mobile app.

## Features

- **Real-time Multiplayer**: Play with friends using WebSocket connections
- **Play Now (automatic matchmaking)**: pick a game and tap Play Now; the server seats you with other players who want the same table, without a room code. Players in the same region (the phone's time zone) are matched first; after 8 seconds the search widens to time zones up to 3 hours away, after 16 seconds to everyone. A 2-seat table starts as soon as two are found; a 6-seat table starts when it is full, or 15 seconds after its second player is found, with whoever is there
- **Multiple Game Modes**: Close Joker 240 (the joker stays hidden until you make a pure sequence; a green dot on a player's avatar shows who has seen it), Pool 101, Pool 201, and Deals Rummy (2 or 3 deals). The server also still plays Points Rummy, but the app's menu no longer offers it: Close Joker took its tile
- **Coins**: Every account starts with 50,000 play coins. Points Rummy (server only, see above) is played for coins a point (free, 5, 10, 20, 50, 100, 200 or 500): each loser pays the winner their points times that value, and what 80 points cost is held while playing. A Pool or Deals table has an entry (free, 500, 1,000, 2,000, 5,000, 10,000, 25,000 or 50,000); each player pays it to sit down and the winner of the game takes the whole pot. Leaving before the cards are dealt gives the entry back; a game that ends without a winner returns every entry. Coins are play money: they cannot be bought, transferred or cashed out
- **Profile photos**: Settings > Profile photo picks a picture from the phone's gallery (Android, and the PC test builds; Godot has no picker on iOS yet). The phone turns it upright, cuts it square and sends a small JPEG; it shows at the table, in the lobby, in friends lists and in the top bar. It can be removed again, and goes with a deleted account
- **Friends**: Add friends by username, see who is online or in a game, open a private table (Play with Friends) and invite a friend to it with one tap, share the room code on WhatsApp
- **Turn Timer**: 30 seconds per turn; the server plays for a player who runs out of time and drops them after three misses in a row
- **Cross-platform**: Works on iOS and Android
- **Persistent Games**: Finished games and results are saved to PostgreSQL database
- **Games survive a server restart**: every game in progress is kept in the database after each move; when the server comes back the players are put back at their table with the same cards, and the turn clock starts again
- **Redis (optional)**: a second place to keep running games; not needed
- **Secure Authentication**: JWT-based user authentication, for the API and for the game socket

## Tech Stack

### Backend
- **Node.js** with Express.js
- **Socket.IO** for real-time communication
- **PostgreSQL** for data persistence
- **Redis** for caching and session management
- **JWT** for authentication
- **bcrypt** for password hashing

### Mobile App
- **React Native** with Expo
- **Zustand** for state management
- **React Navigation** for navigation
- **React Native Paper** for UI components
- **Socket.IO Client** for real-time connection

## Project Structure

```
rummy-multiplayer/
├── backend/
│   ├── src/
│   │   ├── server.js              # Main server file
│   │   ├── config.js              # Settings that must be set before going public
│   │   ├── pages.js               # Privacy policy, terms and account deletion web pages
│   │   ├── database/
│   │   │   ├── db.js              # Database connection
│   │   │   └── migrate.js         # Database migrations
│   │   ├── models/
│   │   │   ├── User.js            # User model
│   │   │   ├── Friend.js          # Friendships and friend requests
│   │   │   └── Game.js            # Game model
│   │   ├── game/
│   │   │   ├── GameEngine.js      # Core game logic
│   │   │   ├── DeckManager.js     # Card deck management
│   │   │   └── Validator.js       # Game rules validation
│   │   └── socket/
│   │       ├── SocketManager.js   # WebSocket management
│   │       └── FriendsManager.js  # Friends lists, who is online, invitations
│   ├── package.json
│   ├── .env
│   ├── .env.example               # What a public server needs in its .env
│   └── Dockerfile, docker-compose.yml
├── mobile/
│   ├── src/
│   │   ├── screens/
│   │   │   ├── HomeScreen.js      # Home screen
│   │   │   ├── GameLobbyScreen.js # Game lobby
│   │   │   ├── GameScreen.js      # Main game screen (landscape table)
│   │   │   └── ProfileScreen.js   # User profile
│   │   ├── store/
│   │   │   ├── authStore.js       # Login state
│   │   │   └── gameStore.js       # Game socket and table state
│   │   ├── services/
│   │   │   └── api.js             # HTTP client
│   │   ├── utils/
│   │   │   ├── constants.js       # Server URLs, colors
│   │   │   ├── rummy.js           # Meld rules for on-screen hints (mirrors backend Validator.js)
│   │   │   └── dialogs.js         # Alerts that also work on web
│   │   └── components/
│   │       └── PlayingCard.js     # A single card
│   ├── App.js                     # Main app component
│   ├── package.json
│   └── .env
├── godot/                         # Godot 4 game client (replacing mobile/)
│   ├── project.godot
│   ├── autoload/
│   │   ├── config.gd              # Server address, saved login, sound switches
│   │   ├── sound.gd               # Music and sound effects (the `Sound` autoload)
│   │   ├── ui.gd                  # Theme, message boxes, notices
│   │   └── fx.gd                  # Fireworks, confetti, sparkles, flash, shake, banners (`Fx`)
│   ├── audio/                     # The sounds and the two tunes, as .wav files
│   ├── tools/
│   │   └── make_audio.js          # Makes every file in audio/ from code (no recordings)
│   ├── net/
│   │   ├── socket_io_client.gd    # Socket.IO v4 client for Godot
│   │   └── game_client.gd         # Login, game socket, table state (the `Game` autoload)
│   ├── rules/
│   │   └── rummy.gd               # Meld rules for on-screen hints (mirrors backend Validator.js)
│   ├── scenes/
│   │   ├── main.tscn              # Picks the screen: home, lobby or table
│   │   ├── home.tscn              # Login / register; the menu: player bar, game tiles, bottom bar
│   │   ├── game_tile.gd           # A big coloured tile of the menu, drawn in code
│   │   ├── menu_overlay.gd        # A box over the menu: table setup, room code, the rules
│   │   ├── lobby.tscn             # Room code and players
│   │   ├── friends.tscn           # The friends list, over the home screen or the lobby
│   │   ├── profile.tscn           # The player's own account: games played and won, coins, name and email
│   │   ├── table.tscn             # The card table: oval felt with a wooden rim, seats, piles, the hand
│   │   ├── table_cloth.gd         # The table itself, drawn in code: floor, wooden rim, lit felt
│   │   ├── card.gd                # A playing card, drawn in code; can be tapped or carried
│   │   ├── player_badge.gd        # A player's avatar with the turn clock as a ring around it
│   │   ├── sound_switches.gd      # The music and sound on/off buttons
│   │   ├── drifting_suits.gd      # Faint card suits rising behind the home screen and lobby
│   │   └── felt.gd                # The green table cloth behind every screen
│   ├── assets/                    # Logo, boot splash and app icons, made from the Namma Rummy logo
│   ├── export_presets.cfg         # Android and iOS export settings (package name, icons, version code)
│   └── tests/                     # Rule cross-check, two-player client test, UI tour, effects preview, store rules
├── store/                         # Store listing texts, form answers and graphics
├── docs/                          # Static web pages: the privacy policy (publish with GitHub Pages)
├── build-android.bat              # Builds the .aab for Google Play and an .apk for a phone
├── sign-android.bat               # Signs a bundle that was built without the upload key
└── README.md
```

## Setup Instructions

**Quick start on Windows:** once the steps below have been done once, double-click
`start-dev.bat` in this folder. It opens the backend and the Expo dev server in their own
windows, each in the right folder, and leaves alone whichever is already running.
The backend runs from `backend/`; every `expo` command runs from `mobile/`.

### Prerequisites

1. **Node.js** (v16 or higher)
2. **PostgreSQL** database
3. **Redis** server (optional, see below)
4. **Expo Go** from the Play Store / App Store on your phone, on the same Wi-Fi as your PC.
   The store version only runs the newest Expo SDK; this project is on SDK 57. If Expo Go says
   the project is incompatible, upgrade the project (`npx expo install expo@latest`, then
   `npx expo install --fix`, in `mobile/`).
   Some office Wi-Fi networks block phone-to-PC traffic; if the phone cannot load the app,
   connect the PC to the phone's hotspot instead.

### Database Setup

1. Install PostgreSQL and create a database:
```bash
createdb My_Rummy -U postgres
```

2. Set password for PostgreSQL user:
```bash
psql -U postgres
ALTER USER postgres WITH PASSWORD 'sujin';
\q
```

### Backend Setup

1. Navigate to backend directory:
```bash
cd rummy-multiplayer/backend
```

2. Install dependencies:
```bash
npm install
```

3. Run database migrations:
```bash
npm run migrate
```
   Run this again whenever you update the code. It is safe to repeat, and it brings a
   database made by an older version up to date (for example, it lets an account be
   registered with a phone number and no email).

4. Start the backend server:
```bash
npm start
```

The backend will run on `http://localhost:3001`

Games in progress survive a restart of the server: each one is written into its row of the
`games` table (column `snapshot`, which the server adds by itself) before a move is answered,
and loaded again at startup. The players see "Reconnecting..." for a few seconds and then play
on. So `npm run dev`, which restarts the server whenever a backend file is saved, no longer
ends the games on it. Redis is optional and not needed for this (`REDIS_HOST=localhost` or
`REDIS_URL=...` in `backend/.env` keeps a second copy there).

### Mobile App Setup

1. Navigate to mobile directory:
```bash
cd rummy-multiplayer/mobile
```

2. Install dependencies:
```bash
npm install
```

3. Start the Expo development server:
```bash
npm start
```

4. Scan the QR code from the terminal with Expo Go (Android) or the Camera app (iOS).

The app finds the backend by itself: it uses port 3001 on the machine that is running Expo,
so there is no IP address to edit. To use a server somewhere else, set `EXPO_PUBLIC_API_URL`
and `EXPO_PUBLIC_SOCKET_URL` in `mobile/.env`.

5. Or run on an emulator / in a browser:
```bash
# For Android
npm run android

# For iOS
npm run ios

# For web
npm run web
```

### Godot Client

`godot/` is the game client made with Godot 4.7. It uses the same backend as the Expo app,
so start the backend first (`npm start` in `backend/`).

1. In Godot's Project Manager choose **Import** and pick `rummy-multiplayer/godot/project.godot`.
2. Press **F5** to run. Register or log in, then create a game or join one with a room code.

**Quickest way to play on Windows:** double-click `play-godot.bat` in this folder. It starts
the backend if needed and opens the game twice, player 1 on the left half of the screen and
player 2 on the right, each with its own login. (If Godot is not in your Downloads folder,
correct the `GODOT` line at the top of that file.)

**Two players on one PC:** every running copy needs its own login. In the editor open
**Debug → Customize Run Instances…**, enable multiple instances (2), and give the second
instance the launch argument `--profile=two`. From a terminal the same thing is
`godot --path godot --profile=two`.

**Server address:** the client looks for the backend at `http://127.0.0.1:3001`. To use
another machine, type its address into the **Server** field on the login form
(for example `192.168.1.5:3001`); it is remembered.

**On a phone** (the test `.apk` from `build-android.bat debug`): the phone and the PC that
runs the backend must be on the same network, and not every Wi-Fi lets a phone reach a PC
(office networks often do not). What always works is the PC's own hotspot: switch on
Settings > Network & internet > Mobile hotspot, connect the phone to it, and open the game.
The test build starts with `192.168.137.1:3001` in the Server field, which is the PC's
address on its own hotspot. On any other network, type one of the addresses the backend
prints when it starts ("To play from a phone on the same network...").

What it does so far: login and register, lobby, the full table (draw, group, discard, declare,
drop, turn clock), round and game results, pool rounds, and coming back after a lost
connection.

It is laid out for a phone held sideways (the screen is 720 units tall, buttons and cards are
finger-sized, wider phones get wider cards). Cards can be tapped to select them or carried
with a finger: onto another group, between two groups or beside either end of the hand to
start a new group, or onto the open pile to discard. Every move is shown as a card travelling: the deal, a draw, a
discard, and what the other players do. On a phone the form moves above the on-screen
keyboard, the back button asks before leaving a game, and the screen stays clear of the
notch; those four were written against the engine's API and have not been tried on a device
yet. It runs on the PC; `build-android.bat` makes the Android files (see
[Publishing to Google Play and the App Store](#publishing-to-google-play-and-the-app-store)).

**Sound and effects:** the home screen and the lobby play one tune, the table another, and
every move has its sound: cards, turns, the clock's last five seconds, melds, declaring,
winning and losing. Big moments get a show on top: a banner when a round is dealt, stars over
a meld just made, the table shaking on a declaration, fireworks and confetti for the winner,
red at the edges of the screen when time runs out. The two round buttons (on the home screen
and in the table's top bar) switch music and sound off; the choice is remembered. A window
that is not in front is silent, so two copies on one PC do not play over each other, and
`--mute` silences a whole run.

Every sound is made by `godot/tools/make_audio.js` from code alone (no recordings, so nothing
to license). To change one, edit its recipe and run `node tools/make_audio.js` in `godot/`,
then open the project in the Godot editor once so it is imported. To use a recording instead,
replace the `.wav` in `godot/audio/` and keep its name. Loudness of each effect is set in the
`EFFECTS` table at the top of `autoload/sound.gd`.

**Tests** (run from `godot/`, against a test backend, never the real one: they register
throwaway accounts). `tests/test_server.js` is that backend: the real server code on its own
port and database, dealing fixed hands while the flag file exists.

```bash
# The test backend, with a fresh throwaway database (stop it with Ctrl+C when done)
node tests/test_server.js --fresh --port=3101 --db=My_Rummy_test --rig-flag=<file>

# Rules: compare rules/rummy.gd with answers from the server's Validator
godot --headless --path . res://tests/rules_crosscheck.tscn -- --vectors=<file.json>

# Network: two players play through real games
godot --headless --path . res://tests/client_e2e.tscn -- --server=http://127.0.0.1:3101 --rig-flag=<file>

# Coins: entries, refunds, the pot to the winner, tables one cannot afford
godot --headless --path . res://tests/coins_e2e.tscn -- --server=http://127.0.0.1:3101

# Profile photos: made on the phone (EXIF turning, square cut), saved, seen by another player at
# the table, in the friends list and in a badge, replaced, removed, refused when not a small picture
godot --headless --path . res://tests/avatar_e2e.tscn -- --server=http://127.0.0.1:3101 --mute

# Restarts: kills the server in the middle of a game and checks the players play on with the same
# cards. This one starts and stops its own test backend, on the port and database given here
godot --headless --path . res://tests/server_restart.tscn -- --port=3112 --db=My_Rummy_restart_test

# Ads: shown only before sitting down, between rounds and after a finished game (stand-in ads;
# needs the normal 12 s break between rounds, so not a server started with NEXT_ROUND_SECONDS)
godot --headless --path . res://tests/ads_policy.tscn -- --profile=adstest --server=http://127.0.0.1:3101

# Play Now: tiles, setup boxes, the search box and matched tables, through the real screens with two
# screenless players. Start its test backend with short waits first:
#   MATCH_REGION_SECONDS=2 MATCH_NEARBY_SECONDS=4 MATCH_FILL_SECONDS=3 NEXT_ROUND_SECONDS=2 node tests/test_server.js --fresh --port=3101 --db=My_Rummy_test
godot --headless --path . res://tests/match_e2e.tscn -- --profile=matchtest --server=http://127.0.0.1:3101 --mute

# Screens: drives the real UI through three games (points, pool, Close Joker) and saves a picture of each step
godot --path . res://tests/ui_tour.tscn -- --profile=uitour --server=http://127.0.0.1:3101 --shots=<folder> --rig-flag=<file>

# Effects: plays every sound and effect once, checks sound reaches the mixer, saves pictures (needs no server)
godot --path . res://tests/fx_preview.tscn -- --profile=fxpreview --mute --shots=<folder>

# Friends, play again, profile: drives them through the real screens with two more players.
# With a window and --shots it saves pictures; with --headless and without --shots it only checks
godot --path . res://tests/friends_tour.tscn -- --profile=friendstour --server=http://127.0.0.1:3101 --shots=<folder> --mute

# Store rules: delete an account in the app, privacy links, no developer options in a store build
godot --headless --path . res://tests/store_release.tscn -- --profile=storetest --server=http://127.0.0.1:3101 --store-build
```

## Game Rules

### Basic Rummy Rules
- Each player gets 13 cards (one deck for 2 players, two decks for 3 to 6)
- A card is cut as the joker: every card of that rank is wild, along with the printed jokers
- On your turn: draw from the deck or the open pile, then discard one card
- **Pure Sequence**: 3+ consecutive cards of same suit, no wild card standing in (mandatory)
- **Impure Sequence**: Consecutive cards with joker wildcards
- **Set**: 3 or 4 cards of same rank, different suits
- To declare, all 13 cards must be in melds, with at least two sequences, one of them pure
- After a valid declaration the round is won, but the hands are not counted at once: every
  other player still in the round gets 15 seconds to arrange their own cards and press
  **Submit**. The round ends when all of them have submitted or the 15 seconds are over;
  a hand not submitted is counted as it lies. Nobody can draw, discard or drop meanwhile,
  and leaving then is counted like staying (`ARRANGE_TIMEOUT_SECONDS` in `backend/.env`
  changes the time)
- **Drop**: give up the round at the start of your turn

### Scoring
- Face cards (J, Q, K) = 10 points
- Aces = 10 points
- Number cards = face value
- Jokers = 0 points
- The winner scores 0; a losing hand scores its unmelded cards, up to 80
  (everything counts without a pure sequence; only the pure sequence is safe without a second sequence)
- Drop = 20 points before your first turn, 40 after; a wrong declaration = 80
- **Points** games are a single round. **Pool** games continue round after round; a player
  reaching 101 (or 201 in Pool 201) is eliminated and the last player left wins

### Deals Rummy
- A fixed number of deals, 2 or 3, played for chips. Every player starts with 80 chips for each deal
- The winner of a deal takes from each loser as many chips as the loser's points
- After the last deal the player with the most chips wins the game and the pot. Players level
  on chips at the top play one more deal between them (the tie-breaker)

### Close Joker
- Played and scored like a pool game, with a limit of 240 points instead of 101
- The joker is cut face down. A player gets to see it once their own hand holds a pure
  sequence (the "first life") in a group of its own; from then on it is open for that player
  for the rest of the round, and they can use the wild cards as usual
- Each player opens it for themselves: the others are told that it happened, not which card it is.
  The server does not send the joker to a player who has not opened it
- A hand that is dealt a whole suit as one run opens the joker at once, since the cards are
  grouped by suit when dealt
- When the round ends the joker is shown to everyone; the next round starts with a new one, closed again

## API Endpoints

### Authentication
- `POST /api/auth/register` - User registration. Username, password, email and mobile number
  are all required. The email must look like an address; the number must be an Indian mobile
  (10 digits starting 6 to 9, stored without `+91` or a leading `0`) or, for another country,
  `+` and the country code. The rules are in `backend/src/validation.js`; the app checks the
  same in `godot/scenes/home.gd` before sending
- `POST /api/auth/login` - User login with email, mobile number (typed any way) or username

### Games
- `GET /api/games/active` - Get active games
- `POST /api/games/create` - Create new game
- `GET /api/games/:id` - Get game details

### User
- `GET /api/user/profile` - Profile with games played / won
- `PATCH /api/user/profile` - Update username and email
- `POST /api/user/delete` `{ password }` - Delete the account and its game results for good
- `PUT /api/user/avatar` - Save a profile photo: the body is the picture itself
  (`Content-Type: image/jpeg` or `image/png`), at most 200 KB and 512 pixels a side; the app
  sends a 256 pixel square JPEG it made. Answers `{ avatar }`, the photo's new version
- `DELETE /api/user/avatar` - Remove the photo; answers `{ avatar: 0 }`
- `GET /api/avatars/:userId?v=<version>` - A player's photo (404 when there is none). The
  version only goes up, so a phone can keep a photo it has under that version
- Wherever a player appears (the `user` of login and register, the profile, `players[]` of
  `gameState`, every entry of `friendsState`) `avatar` is the photo's version, 0 for none. A
  change is pushed at once to the player's table and to everyone whose lists show them

Register, login and delete accept 40 requests per 5 minutes from one address, then answer 429.

### Web pages
- `/privacy`, `/terms` - Privacy policy and terms of use, linked from the app and the store listings
- `/delete-account` - Delete an account without the app (Google Play asks for this link)

### WebSocket Events

The socket connects with the login token (`auth: { token }`); the server takes the player's
identity from it. Every client event is answered through its acknowledgement callback with
`{ ok: true, ... }` or `{ ok: false, error }`.

#### Client → Server
- `createGame` `{ gameType, maxPlayers, stake | pointValue, private, username }` - Create new game, returns `roomCode`.
  `gameType` is `points`, `pool`, `pool_201`, `close_joker`, `deals_2` or `deals_3`. `stake` is the
  entry; a Points table can instead have `pointValue` (coins a point). `private` tables are
  joined with the room code only
- `findMatch` `{ gameType, maxPlayers, stake | pointValue, timezone }` - Play Now: search for
  players who want the same table, nearest region first. `timezone` is the phone's offset from
  UTC in minutes (330 in India). The answer is `{ searching, region }`; `matchStatus` events
  follow until `matchFound` and the table's `gameState`. A player waiting in a lobby leaves it;
  one in a game is refused. Disconnecting ends the search
- `cancelMatch` - End the search, answers `{ cancelled }`
- `joinGameByRoomCode` `{ roomCode, username }` - Join (or rejoin) a game
- `joinGame` `{ gameId }` - Join by game id
- `startGame` - Host starts before the table is full
- `drawCard` `{ fromDiscard }` - Draw a card
- `discardCard` `{ cardId }` - Discard a card
- `arrangeHand` `{ groups }` - Save how the hand is grouped (arrays of card ids)
- `declare` `{ cardId, groups }` - Discard the finishing card and declare. If it is valid the
  game stays `playing` with `declaredBy` set and `turnPhase` `arrange` while the others arrange
  their cards; `turnTimeLeft` is then the time they have left
- `submitHand` `{ groups }` - After someone else's declaration: hand in one's own arrangement
  (`players[].submitted` in the state says who has)
- `drop` - Drop out of the round
- `leaveGame` - Leave the lobby or forfeit the game
- `friends` - The friends lists (the same content as `friendsState` below)
- `friendRequest` `{ username }` - Ask a player to be friends; accepts if that player had already asked
- `friendRespond` `{ userId, action }` - Answer a request: `accept`, `decline` or `block`
- `friendRemove` `{ userId }` - End a friendship, or take back a request
- `inviteFriend` `{ userId }` - Call a friend who is online to the table you are waiting at.
  A player you finished a game with in the last 15 minutes can be called too, friend or not
  (the app's "Play again" opens a table with the same rules and calls the others to it)

#### Server → Client
- `gameState` - The whole table after every change, with only the receiver's own hand.
  `poolLimit` is the points limit (`null` in a points game). In Close Joker `closedJoker` is
  true, and while `jokerHidden` is true `joker` and `wildRank` are `null`;
  `players[].seenJoker` says who has opened it
  `deals` is the number of deals in Deals Rummy (`round` is the deal, `players[].chips` the chips);
  `pointValue` is the coins a point at a Points table (the round result then has `coins` per player)
- `matchStatus` `{ found, needed, inQueue, scope, region, waited, startsIn }` - Where a Play Now
  search stands: players found for the table so far (with the searcher), `scope` `region`,
  `nearby` or `everywhere`, and `startsIn` (ms) once a table with free seats will start anyway
- `matchFound` `{ gameId, roomCode, players }` - The search is over: the player is seated and dealt in
- `matchFailed` `{ message }` - The player could not be seated (e.g. not enough coins any more)
- `playerJoined`, `playerLeft`, `playerDisconnected`, `playerReconnected` - Table notices
- `playerDropped`, `wrongDeclaration` - Round notices
- `gameOver` - Game ended, with every player's result
- `friendsState` `{ friends, incoming, outgoing, recent }` - The player's whole friends lists,
  sent on connecting and after every change. Each friend has a `status`: `online`, `lobby`
  (waiting at a table), `playing` or `offline`. `recent` are players met at a table who are in
  none of the lists yet
- `gameInvite` `{ username, roomCode, poolLimit, closedJoker, deals, maxPlayers, stake, pointValue, again }` - A friend invites
  the player to their table; joining is `joinGameByRoomCode`. `stake` is the entry in coins,
  `again` is true when the two have just played together

## Development

### Running Tests
```bash
# Backend tests
cd backend
npm test

# Mobile tests
cd mobile
npm test
```

### Code Quality
- ESLint for code linting
- Prettier for code formatting
- Husky for pre-commit hooks

## Deployment

### Backend Deployment

The apps in the stores need the backend on a public address with HTTPS. One small Linux
machine runs everything: the game server, PostgreSQL and Redis in Docker, with Caddy in
front for HTTPS. Games in progress live in that one process, so run one copy only.

**On Render (render.com), with no server to look after:**

Render runs the backend straight from a Git repository and gives it HTTPS at
`https://<name>.onrender.com`. `render.yaml` in this folder describes the service and its
PostgreSQL database, so Render creates both in one step.

1. Put this folder (`rummy-multiplayer`) into a private GitHub repository. `.gitignore`
   keeps `node_modules`, `.env` files, builds and `build/` out of it.
2. On render.com sign in with GitHub, choose **New > Blueprint**, pick the repository, and
   confirm. Render reads `render.yaml`, asks for `LEGAL_OWNER` and `SUPPORT_EMAIL` (they
   appear on the privacy policy), makes `JWT_SECRET` itself, and creates the web service
   `namma-rummy` and the database `namma-rummy-db` in Singapore, on the plans named in
   `render.yaml` (free to try; Starter and Basic-256mb for the real game).
   The first build takes a few minutes; `node src/database/migrate.js` runs on every start,
   so the tables are created and kept up to date by themselves.
3. Open `https://namma-rummy.onrender.com/health`, `/privacy`, `/terms` and
   `/delete-account` in a browser (the name has a random suffix if `namma-rummy` is taken;
   the service page shows the real address).
4. Put that address into `RELEASE_SERVER_URL` in `godot/autoload/config.gd` and build the
   apps (next section). To try the live server with the test `.apk` first, type the address
   into the Server field on the login screen.

Every later `git push` deploys by itself (players see "Reconnecting..." for a few seconds;
games in progress survive, they are kept in the database). Logs and the environment variables
are on the service's page in the dashboard. Do not use the free plans for the real game: the
free web service sleeps after 15 minutes without visitors, which ends every game in
progress, and the free database is deleted after 30 days.

**On DigitalOcean (or any Ubuntu machine you can ssh into):**

1. Create a Droplet: Ubuntu 24.04, the Basic plan with 2 GB of memory is plenty (1 GB
   works), in the region nearest your players (Bangalore for India). Add your SSH key
   (`%USERPROFILE%\.ssh\id_ed25519.pub` on this PC) so you can log in without a password,
   and switch on weekly backups if you want DigitalOcean to keep copies of the whole machine.
2. Give it a name: in your domain's DNS add an A record, for example `rummy.yourdomain.com`,
   pointing at the Droplet's IP address. The HTTPS certificate is issued for that name, so
   the record must exist before the next step. (No domain yet? `<ip-with-dashes>.sslip.io`,
   e.g. `203-0-113-10.sslip.io`, resolves to that IP without any setup; good enough to try,
   not for the store listing.)
3. On this PC run `deploy-server.bat root@<droplet ip> rummy.yourdomain.com`. The first run
   asks for the publisher's name and a support email (they appear on the privacy policy),
   makes the secrets into `backend/.env.production` (keep that file private and keep a copy),
   uploads the backend, installs Docker and Caddy on the machine, starts everything, sets up
   a daily database dump in `/opt/rummy/backups`, and checks `https://rummy.yourdomain.com/health`.
4. Open `https://rummy.yourdomain.com/health`, `/privacy`, `/terms` and `/delete-account`
   in a browser.
5. Put `https://rummy.yourdomain.com` into `RELEASE_SERVER_URL` in `godot/autoload/config.gd`
   and build the apps (next section). To try the live server with the test `.apk` first,
   type the name into the Server field on the login screen.

To update the server after a code change, run the same `deploy-server.bat` command again:
it uploads the code and restarts only what changed (players see "Reconnecting..." for a few
seconds; games in progress survive). Logs: `ssh root@<ip>`, then
`cd /opt/rummy && docker compose logs -f server`.

**By hand, or on another host:** copy `backend/.env.example` to `.env` and fill it in (with
`NODE_ENV=production` the server refuses to start until `JWT_SECRET`, `LEGAL_OWNER` and
`SUPPORT_EMAIL` are set); then either `docker compose --env-file .env up -d --build` in
`backend/`, or `npm ci --omit=dev`, `npm run migrate`, `npm start` next to your own
PostgreSQL. Put a reverse proxy with an HTTPS certificate in front of port 3001 (it has to
pass WebSocket connections through) and set `TRUST_PROXY` to the number of proxies.

### Publishing to Google Play and the App Store

The store texts, the graphics and the answers for the store forms are in `store/listing.md`.

**Once, for both stores**

1. Put the public server address into `RELEASE_SERVER_URL` in `godot/autoload/config.gd`.
   Store builds play on that server only and hide the Server field.
2. The package name is `app.nammarummy.com` (in `godot/export_presets.cfg`). It cannot
   be changed after the first upload, so change it now if you want another one.

**Android**

1. Double-click `build-android.bat`. The first run creates your upload key in
   `%USERPROFILE%\namma-rummy-keys` and asks you to choose its password. Keep a copy of the
   key file and the password: Google Play accepts updates only when they are signed with it.
2. It writes two files into `build/`: the `.aab` for Google Play and the same game as an
   `.apk`. Copy the `.apk` to a phone, install it and play a game against the public server.
3. In Google Play Console create the app, fill in "App content" from `store/listing.md`, and
   upload the `.aab` to a testing track first.
4. For every later upload run `build-android.bat bump` (Google Play refuses a version code it
   has already seen). For a new version number shown to players, change `config/version` in
   `godot/project.godot` as well.

`build-android.bat debug` makes a test `.apk` that keeps the Server field, for playing
against the backend on your PC before the public server exists.

`sign-android.bat` signs a bundle that was built without the key, such as
`build/namma-rummy-<version>-<code>-unsigned.aab` made by a helper that could not ask for
your password. It asks for the password and writes the signed `.aab` next to it.

**Ads (Google AdMob)**

The Android app shows full-screen ads at three moments of a game and never at any other
(`godot/autoload/ads.gd` decides, `godot/tests/ads_policy` checks it):

1. Before the player sits down at a table (Play Now, a new table, a room code, an invitation,
   Play again). The ad comes before the server is asked, so no turn clock runs meanwhile.
2. In the break between two rounds (Pool, Deals), while at least 9 of its 12 seconds are left.
3. When the player leaves the result of a finished game.

Never during anyone's turn or the 15 seconds to arrange cards after a declaration, at most one
every 90 seconds, and only when an ad has already been downloaded, so nobody waits for one.
Players in the EEA, the UK and Switzerland first see Google's consent form, and Settings offers
"Privacy choices for ads" where the law requires it.

Test builds (`build-android.bat debug`) show Google's test ads. Store builds show no ads until
you fill in your own AdMob ids:

1. Create an AdMob account, add the app (Android, package `app.nammarummy.com`) and create one
   "Interstitial" ad unit.
2. Put the app's App ID (it contains `~`) into `godot/project.godot`:
   ```
   [admob]

   general/android/app_id="ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX"
   ```
3. Put the ad unit ID (it contains `/`) into `RELEASE_INTERSTITIAL_ID` in
   `godot/autoload/config.gd`.
4. In Play Console answer "Contains ads" with Yes and fill in Data safety as `store/listing.md`
   describes.

Never tap your own real ads, and never use your real ad unit in a test build: Google closes
accounts for invalid clicks. The ads come from the Poing Studios AdMob plugin in
`godot/addons/admob/`; its Android and iOS libraries (`android/bin`, `ios/bin`) are not in git,
and the first headless editor run of a fresh clone downloads them.

The build needs JDK 17 and the Android SDK (platform 36, build-tools 36.1.0) in
`%LOCALAPPDATA%\Android`, and the Godot 4.7.2 export templates. Their paths are at the top of
`build-app.ps1`.

**iPhone and iPad**

Apple's build tools run only on a Mac, so the last step needs one (your own, a borrowed one,
or a rented cloud Mac) with Xcode.

1. Join the Apple Developer Program and put your Team ID into the iOS preset:
   `application/app_store_team_id` in `godot/export_presets.cfg`.
2. Double-click `build-ios.bat`. It writes the Xcode project into `build/ios/`.
3. Copy that folder to the Mac, open `namma-rummy.xcodeproj` in Xcode, choose
   Product > Archive, then Distribute App > App Store Connect.
4. In App Store Connect fill in the listing from `store/listing.md`, pick the build and
   submit it for review.

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

## License

This project is licensed under the MIT License.

## Support

For support, email support@rummymultiplayer.com or join our Discord community.
