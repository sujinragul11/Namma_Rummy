# Namma Rummy: store listing

Text and answers to paste into Google Play Console and App Store Connect.
`YOUR-SERVER` stands for the public address of the game server, for example `rummy.yourdomain.com`.

## Identity

| | |
|---|---|
| App name | Namma Rummy |
| Package name (Android) / Bundle ID (iOS) | `com.roririsoft.nammarummy` |
| Category | Games > Card |
| Price | Free, no in-app purchases, no ads |
| Website | `https://YOUR-SERVER/` |
| Privacy policy | `https://YOUR-SERVER/privacy` |
| Terms of use | `https://YOUR-SERVER/terms` |
| Account deletion | `https://YOUR-SERVER/delete-account` |

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

> Play 13-card rummy online with friends: Points, Pool and Close Joker. Free.

**Subtitle** (App Store, 30 characters at most)

> 13-card rummy with friends

**Keywords** (App Store, 100 characters at most)

> rummy,indian rummy,13 card,card game,pool rummy,points rummy,multiplayer,friends,online

**Full description** (both stores)

> Namma Rummy is classic 13-card rummy that you play online with your friends.
>
> Create a table, share the six-letter room code, and play in real time with 2 to 6 players.
>
> • Points rummy: one quick round
> • Pool 101: play round after round until one player is left
> • Close Joker 240: the joker stays hidden until you make a pure sequence
> • 50,000 free play coins to start: sit at a free table, or at one with an entry from 1,000 to 50,000 coins where the winner takes the pot
> • Add friends, see who is online, and invite them to your table with one tap
> • Share your room code on WhatsApp
> • Play again with the same players in one tap
> • Your profile shows the games you played and won
> • Group your cards into sequences and sets; the game shows which groups are valid
> • When someone declares, you get 15 seconds to arrange your cards before they are counted
> • A wild joker is cut every round
> • 30 seconds per turn keeps the game moving
> • Lost your connection? Come back to the same seat
>
> Namma Rummy is free and is played for fun only. Coins are play tokens with no cash value:
> they cannot be bought, sold or cashed out. There is no real-money play, there are no
> purchases and no prizes.

## Google Play Console: App content

| Question | Answer |
|---|---|
| Privacy policy | `https://YOUR-SERVER/privacy` |
| Ads | No, the app contains no ads |
| App access | Restricted: an account is needed. Give the reviewer a test account (see below) |
| Target audience | 18 and over. Not a choice any more: players stake coins on the games, which the stores treat as simulated gambling |
| News app, Health, Financial features, Government | No |
| Data deletion: can users request account deletion? | Yes. URL: `https://YOUR-SERVER/delete-account` |

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
| Does the app collect or share user data? | Yes, collects. Shares nothing |
| Is all data encrypted in transit? | Yes |
| Can users request that data is deleted? | Yes |

Data types collected, each one: *collected, not shared, processed on the server, purpose
"App functionality" and "Account management"*.

| Data type | Required? |
|---|---|
| Personal info > Email address | Required |
| Personal info > Phone number | Required |
| Personal info > User IDs (the username) | Required |
| App activity > App interactions (games played and results) | Required |
| Contacts (the friends list made inside the app; the phone's address book is never read) | Optional |

## App Store Connect

**App Privacy.** Data collection: Yes. For each type below: used for *App Functionality*,
*linked to the user*, *not used for tracking*.

- Contact Info > Email Address
- Contact Info > Phone Number
- Identifiers > User ID
- User Content > Gameplay Content
- Contacts (the in-app friends list; Apple counts a "social graph" as Contacts)

The same five are already declared in the app's privacy file by the iOS export preset.

**Age rating.** "Simulated gambling": Yes, frequent (coins are staked on the games), which puts
the app in Apple's adult age band. "Gambling" (real money): No. Every other question: None / No.

**Export compliance.** The app uses only standard HTTPS encryption, so it is exempt:
answer that it uses no non-exempt encryption.

**App Review information.** The reviewer cannot get past the login without an account. Create
two on the public server and enter one under "Sign-in required". (Signing up needs an email
and a mobile number; a number from outside India is typed with + and the country code.) Apple
also asks why an app needs each piece of personal data (guideline 5.1.1); be ready to say
what the email and the phone number are each used for. Suggested note:

> Namma Rummy is an online card game for 2 to 6 players. Log in with the demo account above.
> To see a game, tap "Create game" on one device and join with the room code from a second
> device or account (second demo account: USERNAME2 / PASSWORD2).
> Accounts can be deleted in the app: main menu > Delete account.
> Play coins are free tokens: every account starts with 50,000, they cannot be bought, sold,
> transferred or cashed out, and there are no purchases or real-money play of any kind.

## Before the first upload

- [ ] The backend is running on Render with **https** (`render.yaml`; see "Backend Deployment" in
      the README) and the address is in `RELEASE_SERVER_URL`.
- [ ] `RELEASE_SERVER_URL` in `godot/autoload/config.gd` is that address.
- [ ] `https://YOUR-SERVER/privacy`, `/terms` and `/delete-account` open in a browser and show
      your name and support email.
- [ ] Two demo accounts exist on that server for the reviewers.
- [ ] The store build was played on a real phone against that server.
