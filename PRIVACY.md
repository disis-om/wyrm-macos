# Wyrm — Privacy

Last updated 13 October 2026. Wyrm is made by OM Rajput.

This is written to be read, not to be scrolled past. If something here is
unclear, that is a fault worth reporting.

---

## The short version

- A Wyrm account is a **username and a password** that you choose. Wyrm does
  not ask for your email, your contacts, your files or your location.
- What Wyrm stores about you is what you can already see in the app: your
  names, your picture, your best score, your kills, and anything you typed into
  chat.
- Nothing is sold. Nothing is shared with advertisers. There are no adverts and
  no tracking libraries in this app.
- You can delete your account from inside the app, and it deletes.

---

## Your account and your password

You sign up with a username (your `@handle`) and a password. The password is
never stored as itself. The server keeps only a salted scrypt hash of it and
compares hashes in constant time, so nobody reading the database can read your
password back out of it.

Because there is no email on a normal account, a forgotten password cannot be
reset by mail. Keep it somewhere safe.

---

## What Wyrm knows about you

### What you give it

- **A username**, the `@handle` other players find you by.
- **A display name** and **an in-game name**. The in-game name is printed over
  your snake in the arena.
- **A profile picture**, only if you pick one. It is stored on Wyrm's server
  and is not encrypted.
- **A short bio**, if you write one.
- **A phone number**, only if you enter one. It is stored encrypted and is never
  shown to another player.

### What playing produces

- Your **highest score** and **total kills**, and a record of each finished run
  so those totals can be recounted rather than trusted blindly.
- **Messages** you send in global chat or in a direct thread, and **reports** you
  file about someone else's message.
- **Who you follow** and **who you have blocked**.
- **Name changes**, so the limit on how often you may rename is counted from
  something a reinstall cannot reset.
- **Your custom skin, while you play it online.** When you enter a real arena
  with a skin you built, Wyrm's server holds that skin's colours for that one
  life, so other Wyrm players in the same arena see it exactly. It is cleared
  when you die or leave. If the app is killed, the server lets it expire on its
  own after two minutes.
- **Your settings.** Controls, layout, arrows, colours, sizes, themes, your
  skin and look, and your notification and voice choices are saved to your
  account when the app goes to the background and when you log out, so they
  come back when you log in on any phone. Android and iPhone each keep their
  own copy; your skin and look are shared between them. They are deleted with
  your account.
- If you choose Voice Chat, a separately verified **email address** is stored
  encrypted for voice access and abuse prevention. Other players and the
  operator dashboard never see it.
- Voice rooms keep creator, membership, moderation and call-duration metadata.
  Wyrm does not store the audio, record it or transcribe it.
- **When you play, while Wyrm is open on your screen.** The app tells the
  server what you are doing as it changes: on the menus, in the Ready Room,
  playing in an arena (with that arena's address), playing with AI, or idle
  after two minutes without a touch. It stops when the app goes to the
  background. Each finished run also carries how long it lasted and the arena.
  This is how friends see that you are online and where you play, and how the
  operator sees how many people play and for how long. It is deleted after 90
  days, and with your account.
- To keep the server running, Wyrm counts requests and active players per
  minute. These are totals, not a history of what you did, and they are deleted
  after 90 days.

### What stays on your phone and never leaves it

- Your Team Mode credentials, if you use Team Mode. These are held in the
  Android Keystore — hardware-backed storage that this app can use but cannot
  read out in the clear — and they are sent only to the team service they
  belong to, never to Wyrm's server.
- Logging out removes your settings, messages and Team credentials from the
  phone, so nothing of your account is left there for the next person.

---

## Who else is involved

Wyrm talks to outside services, and it is worth knowing which is which:

1. **Slither's public arena directory**, to list which arenas exist and how busy
   they are, and then the arena itself while you play. This is the game you are
   playing; your snake's position goes to the arena server the way it does in
   any online game. Wyrm sends no account information there — the arena knows
   only the name over your snake and your skin.
   Community-run arenas: Wyrm keeps a random 16-character arena id for your
   account (random, not made from your name or e-mail) and sends it
   only to the arenas on a public list of community-run arenas, so those arenas
   can recognise you between games. Official slither arenas never get it. The
   list is fetched from the same service as the arena flags.
2. **The NTL team service**, only if you turn on Team Mode, and only with the
   credentials you entered yourself. While it is on, it receives your in-game
   name, score, position, rank, which arena you are in and your team chat,
   every four seconds, because that is what Team Mode is.
3. **Google Firebase Cloud Messaging**, to deliver notifications to your phone.
   It is given a device token, not your messages or your account details.
4. **A Gmail sender run by Wyrm**, only to deliver the Voice Chat verification
   code that Wyrm's backend generated.
5. **LiveKit**, only while you are in Voice Chat, to carry live audio between
   room participants. The audio goes between your phone and LiveKit's media
   servers; it does not pass through Wyrm's server.
6. **A public file host** where Wyrm's releases are published. The app reads a
   small signed file from it to learn whether a newer version exists, and
   downloads the update from it when you choose to install one.
7. **Snakey Rain**, only when you enable it in Loadout. The app sends your
   public or personal Rain login, chosen characters, arena address, a copy of
   your arena join, snake position, target and control commands directly to
   `snakeyrain.com` over an encrypted connection. This is a separate service,
   run by its own operator. Personal login and private bot tag codes stay
   encrypted on this phone, are sent only to Rain, and are cleared on logout.
   Rain settings and non-secret character choices follow your Wyrm account.
   Turning Rain off or leaving the app disconnects it and requests bot stop.
   Creating a personal Rain account opens that service's website in a browser.

Wyrm's own server is a rented machine run by the author. It is not a cloud
account with an analytics product attached.

## What Wyrm does not do

- No advertising, and no advertising identifiers.
- No analytics or crash-reporting service from anyone else. Wyrm's own server
  keeps when you play (described above) and per-minute server totals, and
  nothing else about your sessions.
- No location or contacts, and no camera roll scanning. The app asks for a
  photo only when you pick one, and only that photo. It asks for microphone
  permission only when you explicitly enter Voice Chat; a visible foreground
  notification remains while background voice is active.
- No voice recording and no transcription. WebRTC transport encryption is
  used; Wyrm does not make an unsupported end-to-end-encryption claim.
- No selling, renting or sharing of your data. There is nobody to sell it to.

## Other players see

Your display name, your username, your in-game name, your avatar, your bio, your
best score and your kills, anything you posted in global chat, and your custom
skin while you are in the same arena. Friends (players who follow you and whom you follow
back) see whether you are on Wyrm right now and which arena you play in or last
played in. Settings › Privacy › **Show my activity to friends** turns that
off; while it is off you do not see theirs either. While that switch is on,
signed-in players also see you in the arena chat's **Online** list for a few
minutes after you use Wyrm: your in-game name, your username and the arena you
played in; turning the switch off leaves you out of that list. Your phone number and your voice email
address are never shown to another player.

## Deleting messages and Trails

Touch and hold your own message in Global chat or a direct thread, then choose
Delete. Wyrm removes it from the active server database for both sides,
including any report or stored invite notification linked to it, and tells
connected apps to remove it. A deleted message cannot be restored in the app.

Deleting a Trail removes its post, comments, likes, reports and media references.
Its photo, thumbnail and video files are removed from active storage once no
other valid post/upload uses the same file. Deleting a comment also removes its
stored reply notification. Deleting your account removes your Trails, uploaded
Trail media and comments on other Trails.

Disaster-recovery backups and retained rollback releases can still contain old
copies. Nightly database backups rotate after seven days; off-site packs retain
seven daily and four weekly copies. Previous releases remain until release
retention prunes them. Deletion does not recall another player's screenshots,
clipboard, previously delivered notification or downloaded/cached copy.

## Background play

A match can keep running when you switch apps or lock the screen. Android uses
a foreground service with a visible "Your match is still running" notification
and keeps the CPU/Wi-Fi awake while needed; it stops on return or match end.
The arena connection and bot may continue, but no game frames are drawn while
backgrounded. This can use battery and network data. It does not record audio
or require microphone access.

## Deleting your account

Profile → menu → delete. It removes your account, your photograph, your bio and
your phone number outright. Messages you already sent stay where they are but
are attributed to "deleted player" — the same way a deleted account works
anywhere that people have already replied to you. A deleted account cannot be
brought back; signing up again starts a new, empty account.

## Children

Wyrm is not built for children under 13, and accounts are not knowingly created
for them.

## Changes

When this document changes, the date at the top changes with it, and the new
text ships inside the next version of the app (Settings › Privacy).

## Asking

Write to **ommanav.mail@gmail.com**.
