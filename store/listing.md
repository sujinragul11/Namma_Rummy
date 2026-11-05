# Namma Rummy: store listing

Text and answers to paste into Google Play Console and App Store Connect.
The game server runs at `https://namma-rummy.onrender.com` (Render; see `render.yaml`).

## Identity

| | |
|---|---|
| App name | Namma Rummy |
| Package name (Android) / Bundle ID (iOS) | `app.nammarummy.com` |
| Category | Games > Card |
| Price | Free, no in-app purchases, contains ads (Google AdMob, Android only) |
| Website | `https://namma-rummy.onrender.com/` |
| Privacy policy | `https://namma-rummy.onrender.com/privacy` |
| Terms of use | `https://namma-rummy.onrender.com/terms` |
| Account deletion | `https://namma-rummy.onrender.com/delete-account` |
| app-ads.txt (AdMob) | `https://namma-rummy.onrender.com/app-ads.txt`, served by `backend/src/server.js`; AdMob only finds it when the Website above is the developer website in Play Console |

The package name cannot be changed after the first upload. To use another one, change it in
`godot/export_presets.cfg` (three places) before you upload anything.

## Graphics in this folder

| File | Where it goes |
|---|---|
| `play-icon-512.png` | Google Play: App icon |
| `play-feature-graphic-1024x500.png` | Google Play: Feature graphic |

Screenshots still have to be taken from the finished game:

- **Google Play:** at least 2 phone screenshots (4 or more is better), landscape, 16:9, for example 1920x1080.
- **App Store:** iPhone 6.9" landscape, 2868x1320, at least 1; and iPad 13" landscape, 2752x2064, at least 1,
  because the build also runs on iPad.

## Texts

**Short description** (Google Play, 80 characters at most)

> 13-card Indian rummy: Close Joker, Pool and Deals. Play Now or with friends.

**Subtitle** (App Store, 30 characters at most)

> 13-card rummy with friends

**Keywords** (App Store, 100 characters at most)

> rummy,indian rummy,13 card,card game,pool rummy,points rummy,multiplayer,friends,online

**Full description** (both stores)

> Namma Rummy is classic 13-card Indian rummy, played online in real time with 2 to 6 players.
>
> Tap Play Now and the game finds players for you, the ones in your region first: no room code needed. Or open a private table under Play with Friends, share its room code on WhatsApp, and play with the people you know.
>
> THREE WAYS TO PLAY
> • Close Joker: the joker is cut face down and stays hidden until you hold a pure sequence. A green dot shows who has seen it. Round after round, reach 240 points and you are out; the last player standing wins.
> • Pool Rummy 101 and 201: the open-joker classic. Reach the limit and you are out; the last player left takes the pot.
> • Deals Rummy: 2 or 3 deals played for chips; the most chips at the end wins.
>
> HOW IT IS PLAYED
> Every player gets 13 cards. On your turn, draw from the deck or the open pile, then discard one. Arrange your hand into sequences and sets, with at least two sequences and one of them pure, and declare before the others do. A wild joker is cut every round, so no two rounds play the same.
>
> PLAY WITH FRIENDS
> • Add friends, see who is online, and invite them to your table with one tap
> • Private tables with a room code you can share on WhatsApp
> • Play again with the same players in one tap
> • Your profile shows the games you played and won
>
> A TABLE THAT PLAYS FAIR
> • Group your cards into sequences and sets; the table shows which groups are valid
> • When someone declares, you get 15 seconds to arrange your cards before they are counted
> • 30 seconds a turn keeps the game moving
> • Lost your connection? Come back to the same seat and carry on
>
> FREE COINS, NO REAL MONEY
> Every player starts with 50,000 free play coins. Sit at a free table, or stake coins on a game and let the winner take everything paid in. Coins are play tokens with no cash value: they cannot be bought, sold, transferred or cashed out. There is no real-money play, no purchases and no prizes. Namma Rummy is free to play and shows ads.
>
> Namma Rummy is for players aged 18 and over.

## Google Play Console: App content

| Question | Answer |
|---|---|
| Privacy policy | `https://namma-rummy.onrender.com/privacy` |
| Ads | Yes, the app contains ads: full-screen ads from Google AdMob before a table, between rounds and after a game |
| App access | Restricted: an account is needed. Give the reviewer a test account (see below) |
| Target audience | 18 and over. Not a choice any more: players stake coins on the games, which the stores treat as simulated gambling |
| News app, Health, Financial features, Government | No |
| Data deletion: can users request account deletion? | Yes. URL: `https://namma-rummy.onrender.com/delete-account` |

**Content rating questionnaire** (category: Game)

| Question | Answer |
|---|---|
| Violence, sexuality, bad language, drugs | No |
| Gambling with real money | No |
| Simulated gambling | Yes. Players stake free play coins on a card game and the winner takes the pot. Coins cannot be bought, sold, transferred or cashed out |
| Can users interact or exchange content? | Yes: online play, friend requests and game invitations. Players see each other's usernames. There is no chat |
| Shares the user's location | No |
| Digital purchases | No |

**Data safety**

| Question | Answer |
|---|---|
| Does the app collect or share user data? | Yes. Our server collects the account and game data below; the AdMob SDK collects ad data (second table) |
| Is all data encrypted in transit? | Yes |
| Can users request that data is deleted? | Yes |

Data types collected, each one: *collected, not shared, processed on the server, purpose
"App functionality" and "Account management"*.

| Data type | Required? |
|---|---|
| Personal info > Phone number (proved with an SMS code at sign-up and for a password reset) | Required |
| Personal info > User IDs (the username) | Required |
| App activity > App interactions (games played and results) | Required |
| Contacts (the friends list made inside the app; the phone's address book is never read) | Optional |
| Photos and videos > Photos (the profile photo, only if the player adds one; also shown to other players) | Optional |

Collected by the ads SDK (Google Mobile Ads, with Google's consent SDK). Fill these in from
Google's own guidance, which is the authority and changes over time:
https://developers.google.com/admob/android/privacy/play-data-disclosure . When this was
written it listed, each *collected*, purposes *Advertising or marketing*, *Analytics* and
*Fraud prevention, security, and compliance*:

| Data type | Where it comes from |
|---|---|
| Location > Approximate location | The IP address |
| App activity > App interactions | Ad views and taps, app launches |
| App info and performance > Crash logs, Diagnostics | The SDK's own reports |
| Device or other IDs | The advertising ID (the app declares the AD_ID permission) |

The merged Android manifest also has ACCESS_NETWORK_STATE, READ_BASIC_PHONE_STATE, WAKE_LOCK
and FOREGROUND_SERVICE from the ads SDK. If Play Console asks for a foreground service
type, check the uploaded bundle's manifest under App bundle explorer before answering.

## App Store Connect

The iPhone app shows no ads yet (the ads code runs on Android only), so the answers below
have no advertising entries. Add Identifiers > Device ID for *Third-Party Advertising* and
the App Tracking Transparency question once ads come to iOS.

**App Privacy.** Data collection: Yes. For each type below: used for *App Functionality*,
*linked to the user*, *not used for tracking*.

- Contact Info > Phone Number
- Identifiers > User ID
- User Content > Gameplay Content
- Contacts (the in-app friends list; Apple counts a "social graph" as Contacts)

The same four are already declared in the app's privacy file by the iOS export preset.
New accounts have no email address since 18 October 2026, so neither store gets an email entry.
The phone number goes to Twilio only to send the SMS code; both stores count a service provider
that works on the developer's behalf as part of the developer, so it is not "shared".

**Age rating.** "Simulated gambling": Yes, frequent (coins are staked on the games), which puts
the app in Apple's adult age band. "Gambling" (real money): No. Every other question: None / No.

**Export compliance.** The app uses only standard HTTPS encryption, so it is exempt:
answer that it uses no non-exempt encryption.

**App Review information.** The reviewer cannot get past the login without an account. Create
two on the public server and enter one under "Sign-in required". (Signing up needs a mobile
number and the code sent to it by SMS, which a reviewer cannot receive: make both accounts
yourself, with two numbers you own.) Apple also asks why an app needs each piece of personal
data (guideline 5.1.1): the mobile number is the account's login, proves one person makes one
account, and is how a forgotten password is reset. Suggested note:

> Namma Rummy is an online card game for 2 to 6 players. Log in with the demo account above.
> To see a game, tap a game, then Play Now, on two devices at about the same time, logged in
> with the two demo accounts (second demo account: USERNAME2 / PASSWORD2): the server seats
> them at one table. Or tap Play with Friends > Create Table on one device and join with the
> room code from the other.
> Accounts can be deleted in the app: main menu > Delete account.
> Play coins are free tokens: every account starts with 50,000, they cannot be bought, sold,
> transferred or cashed out, and there are no purchases or real-money play of any kind.

## Before the first upload

- [x] The backend runs on Render with https at `https://namma-rummy.onrender.com`, and that address
      is in `RELEASE_SERVER_URL` (free plans while testing: switch both to paid in `render.yaml` before
      the release, and before the free database's 30th day).
- [ ] `RELEASE_SERVER_URL` in `godot/autoload/config.gd` is that address.
- [ ] `https://namma-rummy.onrender.com/privacy`, `/terms` and `/delete-account` open in a browser and show
      your name and support email.
- [ ] Two demo accounts exist on that server for the reviewers.
- [ ] The store build was played on a real phone against that server.
