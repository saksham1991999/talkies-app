# Talkies

A movie ticket diary for India. Every film you watch becomes a ticket stub.

Talkies is a movie diary for Indian film goers. Every feature is free.

- Flutter + Riverpod 3. An optional backend (FastAPI and Supabase) adds an account. The app works fully without it.
- Works offline. The app bundles 34,000+ titles (Indian films in 15+ languages, Indian web and TV series, major world films).
- Your data stays on the phone, in one JSON file, unless you sign in to the optional account. Android Auto Backup and iOS device backup include the file.

## Repository layout

This repo holds the app, its optional backend and its website.

- The repo root is the Flutter app (`lib/`, `android/`, `ios/`, `assets/`, `tool/`, tests).
- `backend/` is the optional FastAPI service. `supabase/` holds its config and SQL migrations. See [Backend (optional)](#backend-optional).
- `docs/` is the website: landing, privacy policy, support and account deletion pages. GitHub Pages serves it at https://saksham1991999.github.io/talkies-app/.
- `store/` holds the App Store and Google Play listing text and screenshots.

## Features

### Diary

- Each viewing is a ticket stub with a WATCHED stamp, printed on coloured paper by venue type, like hall tickets.
- Title, rating in 0.1 steps (or no rating, or hidden ratings), date, place and notes.
- Rewatches get their own stub with a viewing number ("Second watch", ×2 on the counterfoil).
- Date not remembered, month-only and year-only dates.
- Unlimited hashtags.
- Calendar of posters, watchlist on planned dates, filter, week start.

### Films and search

- Films tab: new, upcoming, want, recorded and released, with an Indian language filter.
- Search ignores spaces and punctuation. Search by actor, director or native script (शोले).
- Streaming services on the film page, read from Wikipedia articles and Wikidata, and re-checked live for recent films.
- Link to correct film data on Wikidata.

### Stats and sharing

- Stats for any month, any year or all time: count, watch time, ratings, places, genres, countries, directors, actors, tags, languages, decades, formats, show times and spend.
- Tap any chart bar to see its films.
- 11 stamp ink (accent) colours, dark mode and 5 alternate app icons (Android activity-alias, iOS alternate icons).
- Share images with 12 background colours.
- Quick batch entry, CSV import (Talkies and Letterboxd), CSV export.
- What's new dialog on update.

### India edition

- Hall details: show (morning, matinee, evening, night), class (Balcony, Dress Circle, Recliner…), seat, format (IMAX, 4DX, ScreenX, P[XL]…), ticket price in ₹.
- FDFS (first day, first show) stamp and count.
- "Watched in" language for dubbed viewings (KGF in Hindi, RRR in Tamil).
- Spend stats with Indian number grouping (₹1,23,456).
- Places: cinema halls, Netflix, Prime Video, JioHotstar, SonyLIV, ZEE5, aha, Sun NXT, TV. Add your own (PVR Phoenix, Maratha Mandir).
- UI in 8 languages: English, Hindi, Tamil, Telugu, Bengali, Marathi, Kannada, Malayalam. Indian date formats. Imports `DD/MM/YYYY` dates.
- Films you add yourself, with your own poster photo, for titles not in the list.
- Backup and restore as one JSON file. Poster photos you chose for your own films stay on the phone and are not in the backup.

## Backend (optional)

The app works fully without a server. A build that sets `TALKIES_API_URL` adds an optional account: sign in with an email code, Google or Apple, then sync the diary between phones, add friends, make groups, plan movie nights and chat. Without the flag, the app never contacts a Talkies server. If the server is down, the app hides the online features and keeps working.

- `backend/` is a FastAPI service. It proxies Supabase Auth and stores data in a Supabase Postgres database. Setup is in [backend/README.md](backend/README.md). The API is in [backend/API.md](backend/API.md). Change `API.md` first, then the backend and the app.
- `supabase/` holds `config.toml` and the SQL migrations in `supabase/migrations`.

Build flags (`--dart-define=NAME=value`):

| Flag | Meaning |
|---|---|
| `TALKIES_API_URL` | Server address, for example `https://<your-api-host>`. Empty (the default) means no Talkies server calls. |
| `GOOGLE_CLIENT_ID` | Google client ID. iOS needs it. |
| `GOOGLE_SERVER_CLIENT_ID` | Google server (web) client ID. Google sign-in shows only if the server lists it and this is set. |
| `APPLE_SIGN_IN` | `true` shows Sign in with Apple on iOS. Add the Sign in with Apple capability in Xcode first. |

```sh
flutter run --dart-define=TALKIES_API_URL=https://<your-api-host>
```

For local development, point `TALKIES_API_URL` at a local server. The address must be HTTPS in every build: `_uri()` in `lib/net/api.dart` refuses an `http://` address with `ApiOffline('TALKIES_API_URL must be https')` before it sends anything, so a plain-HTTP local server works only if that check is relaxed. (Android debug builds do permit cleartext at the platform level: `android/app/src/debug/AndroidManifest.xml` sets `usesCleartextTraffic`.) Use HTTPS in release builds.

The Supabase provider settings (Google, Apple, the email code template, SMTP) are in `backend/README.md`. For Google on iOS, add the reversed Google client ID to `ios/Runner/Info.plist` as a URL scheme.

## Release builds

Android release builds sign with the upload key in `android/app/upload-keystore.jks`. Its password is in `android/key.properties`. Git ignores both files.

1. Back up both files somewhere safe (a password manager or an encrypted drive). A lost upload key blocks app updates until Google resets it.
2. Turn on Play App Signing when you first upload, so Google holds the app signing key.
3. Without `key.properties`, release builds fall back to the debug key, so a fresh clone still builds.

For the Play Store, build with `flutter build appbundle`. For smaller APKs, add `--split-per-abi`.

### Builds with a server address

A build that sets `TALKIES_API_URL` changes what the app sends and stores. Do these steps in the same release:

1. Publish `docs/privacy.html`, `docs/delete-account.html` and `docs/support.html` (GitHub Pages).
2. Publish the store listing text from `store/listing_data.py`. The old "no account" text is wrong for this build.
3. Update the App Store Connect privacy label and the Google Play Data safety form by hand. Neither store reads them from this repo.
4. Give Google Play the account deletion URL: https://saksham1991999.github.io/talkies-app/delete-account.html.

Deleting an account also revokes the Sign in with Apple grant (App Store rule 4.8). Set `APPLE_CLIENT_ID` and `APPLE_CLIENT_SECRET` on the backend to enable it; without them deletion still works and only skips the revocation (logged, never fatal). See `backend/README.md`.

## Store assets

Listing text for both stores is in `store/listing_data.py` (run it to check the length limits). The privacy, support and account deletion pages are in `docs/` (GitHub Pages).

1. Run `integration_test/store_screens_test.dart` with `flutter drive` on an iPhone 6.9" simulator, then copy `build/screens/*.png` to `build/store_raw/iphone/`.
2. Do the same on an iPad 13" simulator into `build/store_raw/ipad/`.
3. Run `python3 tool/store_frames.py`. It writes captioned App Store and Play screenshots, the feature graphic and the 512 px icon to `store/`.

## Data sources

- **Film list**: [Wikidata](https://www.wikidata.org) (CC0), built by `tool/build_catalog.py`.
- **Recent releases**: Wikidata plus Wikipedia "List of <language> films of <year>" pages, baked in by `tool/bake_recent.dart` and refreshed in the app every 3 days when online.
- **Posters and synopses**: Wikipedia, loaded when online and cached. Offline, a printed title card replaces the poster.
- **Streaming services**: Wikidata distributor and network data, plus sentences in Wikipedia articles such as "began streaming on Netflix" or "digital rights were acquired by Amazon Prime Video". `tool/bake_ott.dart` reads the articles of all series and all films from 2010 on. The in-app refresh does the same for recent films, and the film page re-checks recent films live, because OTT releases follow cinemas by weeks.

## Run

```sh
flutter pub get
flutter run
```

## Test

```sh
flutter test                                   # unit tests, no server needed
NETWORK=1 flutter test test/network_test.dart  # live Wikidata and Wikipedia calls
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart -d <device>      # end to end
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/locales_test.dart -d <device>  # every screen, every language
```

Backend tests need no database. Database tests skip unless `TEST_DATABASE_URL` is set.

```sh
cd backend && uv sync && uv run pytest
```

On iOS both drive tests write screenshots to `build/screens/`. On Android they skip screenshots (`convertFlutterSurfaceToImage` hangs on the emulator).

The end-to-end test records a film with hall details, rewatches it, checks the calendar, films, watchlist, stats, dark mode, Hindi, the app icon switch (Android; iOS replies only after the user taps OK on its system alert), a film you add yourself, quick add, tear up and undo, the share preview, and the saved file.

## Rebuild the film list

```sh
TALKIES_CONTACT="https://your.site" python3 tool/build_catalog.py   # about 15 minutes, cached in tool/.cache
dart run tool/bake_recent.dart
dart run tool/bake_ott.dart                                         # streaming services, about 20 minutes
python3 tool/make_icons.py                                          # launcher icons, all variants
python3 tool/gen_labels.py tool/labels/*.json                       # language and genre names
```

Wikimedia asks API clients to send contact details in the User-Agent. The default contact is the app's Play Store page. To use your own, pass `--dart-define=TALKIES_CONTACT=https://your.site` to `flutter build`, `-DTALKIES_CONTACT=...` to `dart run`, or set the `TALKIES_CONTACT` environment variable for `tool/build_catalog.py`.

## Layout

```
lib/
  config.dart build-time switches: TALKIES_API_URL, Google and Apple sign-in defines
  data/       models, catalog (search, releases, refresh), recommendations, stats, csv, json file,
              groups, decks and nights, sync format
  net/        HTTP client for the optional server
  state/      Riverpod providers: settings, diary, catalog, navigation,
              server status and session, sync, groups, reminders
  ui/         theme, icons, widgets, share images, screens/
  l10n/       app_<lang>.arb (8 languages), labels for languages and genres
backend/      optional FastAPI service (Supabase Auth and Postgres): app/, tests/, API.md
supabase/     config.toml and SQL migrations
docs/         website: landing, privacy, support, account deletion
store/        store listing text and screenshots
tool/         catalog builder, recent-release baker, icon generator, label generator, ARB merge script
```

## Licences

- Tanker by Indian Type Foundry, [ITF Free Font License](assets/fonts/Tanker-LICENSE.txt).
- Teko by Indian Type Foundry, [SIL OFL](assets/fonts/Teko-OFL.txt) (Devanagari fallback).
- Wikidata content is CC0. Wikipedia posters are non-free images shown for identification; Talkies loads them from Wikimedia and does not bundle them.
