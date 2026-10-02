# Talkies

**Keep your ticket stubs. Share the night.**

Talkies is a film diary that looks like a stack of ticket stubs. Today it works alone and offline. The next release adds friends: see what they watch, pick a film together, and plan the night.

## The problem

Choosing a film with friends takes longer than the film. One person suggests, three people say "anything", and the group chat scrolls. Meanwhile each person has a private list of films they want to see, and nobody else can see it.

Talkies already knows your taste. The next step is to use it for the group.

## What Talkies is today

1. **A diary of stubs.** Each viewing is a ticket: film, date, theatre or streaming, seat, price, first-day-first-show mark, who you went with, and a memo.
2. **A calendar of posters.** Each day shows the poster of what you watched. A second view shows the films you planned.
3. **Stats.** Films per month and year, venue split, and rating patterns.
4. **A 34,000-title catalog on the phone.** It works offline and refreshes every 3 days from Wikidata and Wikipedia.
5. **Recommendations on Home.** "For you" and "Because you liked" run on the phone. They use your ratings, directors, cast, genres, language, and streaming services.

Also included: a watchlist with planned dates, streaming availability, CSV and Letterboxd import, backup and restore, share images for tickets and stats, 8 languages, and 11 accent colors.

Talkies has no account by default, no analytics, and no tracking. Signing in stays optional: without an account the app works exactly as it does today.

## What is new: Talkies with friends

Login is optional. Without it, the app works as it does today.

### 1. Your profile
- Sign in and your diary syncs across phones.
- Choose **Private** or **Friends only** for the whole profile.
- Mark single stubs as private. A private stub never appears on your profile.
- Your profile shows a stats card, your top films, and your watchlist.

### 2. Friends' shelves
- Open a friend's profile to see the films they watched. Ratings are optional and set by the friend. Dates are never shown.
- **Taste match %:** a score from the films you both watched and how you both rated them. Each friend shows "You both watched 12" and a match score.
- On any film page: **Friends who watched this**, with avatars and ratings.

### 3. The friends dashboard
- A feed of what friends watched recently: friend name, poster, film title.
- No dates are shown. The order carries the recency.
- One tap adds the film to your watchlist. One tap sends an emoji reaction.

### 4. Groups
- Create a group and invite friends with a link.
- The group has a **shared watchlist**. Any member can add and remove films.
- The group has a chat, tied to its films and nights.

### 5. Swipe to match
- Everyone in the group gets the same deck of films.
- **Right** = I want to watch it. **Left** = skip. **Up** = I have seen it.
- The deck comes from the members' watchlists and from recommendations scored against every member's diary.
- Films that any member has seen are hidden. A switch turns this off.
- Filters: genre, language, decade, streaming service, film or series.
- Search inside the deck. A "show all" list is sorted by right-swipes.
- The top match has a **Schedule it** button.
- Cannot decide? **Tonight picker** chooses at random from the top matches.

### 6. Movie nights
- **Night poll:** propose 3 films and 2 time slots. Friends vote. The winner sets the event.
- The event goes on the calendar with film, date, time, place, and guests.
- Guests reply yes, no, or maybe.
- Reminders arrive as push notifications. Export to the phone calendar as an `.ics` file.
- **Night wrap-up:** after the film, one tap creates a stub for every guest, with "who you went with" filled in.

### 7. Send a film
- Send a film to a friend with a short note. It appears in their dashboard.

## A night with Talkies

1. Priya opens the group "Friday Crew". Five members have added films to the shared watchlist.
2. Everyone swipes for two minutes. Three films get four right-swipes.
3. Priya taps **Schedule it**, adds two time slots, and posts the poll to the group.
4. The group votes. Saturday 8 pm wins. Everyone gets a reminder.
5. After the film, Priya taps **Night wrap-up**. Five stubs appear in five diaries. Each shows the same seat row and the same company.

## Trust and privacy

- Private by default: new profiles start private.
- Viewing dates are never shown to anyone, ever. Nothing on a profile, the feed, or a friend's shelf carries the date you watched a film. Chat messages are the one exception: a message carries its send time to the other members of its group.
- Talkies works offline, and login is not required.
- Account deletion is in Settings and removes all server data. If the account used Sign in with Apple, the Apple grant is revoked on deletion.
- Users can report and block other users.
- Night wrap-up is not private: the stub it creates fills in "who you went with", and that list carries the other attendees' names. Every guest gets such a stub, and each one is visible per that user's own privacy settings.
- `docs/privacy.html` and the store listings will change from "no account, no backend" to describe the optional account.

## Why friends will use it

- A ticket stub is something you keep. A stub with your friends' names on it is something you show.
- The group deck replaces the "anything" chat with a two-minute swipe.
- The diary gets more useful with each friend who joins: more match scores, more "friends who watched this", a fuller feed.

## Roadmap

| Phase | Ships | Depends on |
|---|---|---|
| 1 | Login, sync, privacy settings, delete account | Backend choice |
| 2 | Friends, profiles, taste match, dashboard, report and block | Phase 1 |
| 3 | Groups, shared watchlist, swipe deck, Tonight picker | Phase 2 |
| 4 | Movie nights, poll, calendar, reminders, `.ics` export | Phase 3 |
| 5 | Chat, night wrap-up, send a film | Phase 4 |

Report and block ship in phase 2 because friends can see each other's content from that phase.

## Later

- Year in review, shared with friends
- Watch challenges
- "Who rated it highest" leaderboard
