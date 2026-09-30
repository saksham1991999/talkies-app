# Talkies

A movie ticket diary for India. Every film you watch becomes a ticket stub.

Talkies is a movie diary for Indian film goers. Every feature is free.

- Flutter + Riverpod 3. No backend.
- Works offline. The app bundles 34,000+ titles (Indian films in 15+ languages, Indian web and TV series, major world films).
- Your data stays on the phone, in one JSON file. Android Auto Backup and iOS device backup include it.

## Repository layout

This repo holds the app and its website.

- The repo root is the Flutter app (`lib/`, `android/`, `ios/`, `assets/`, `tool/`, tests).
- `docs/` is the website: landing, privacy policy and support pages. GitHub Pages serves it at https://saksham1991999.github.io/talkies-app/.
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

## Release builds

Android release builds sign with the upload key in `android/app/upload-keystore.jks`. Its password is in `android/key.properties`. Git ignores both files.

1. Back up both files somewhere safe (a password manager or an encrypted drive). A lost upload key blocks app updates until Google resets it.
2. Turn on Play App Signing when you first upload, so Google holds the app signing key.
3. Without `key.properties`, release builds fall back to the debug key, so a fresh clone still builds.

For the Play Store, build with `flutter build appbundle`. For smaller APKs, add `--split-per-abi`.

## Store assets

Listing text for both stores is in `store/listing_data.py` (run it to check the length limits). Privacy and support pages are in `docs/` (GitHub Pages).

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
flutter test                                   # unit tests
NETWORK=1 flutter test test/network_test.dart  # live Wikidata and Wikipedia calls
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart -d <device>      # end to end
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/locales_test.dart -d <device>  # every screen, every language
```

On iOS both write screenshots to `build/screens/`. On Android they skip screenshots (`convertFlutterSurfaceToImage` hangs on the emulator).

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
  data/       models, catalog (search, releases, refresh), stats, csv, json file
  state/      Riverpod providers: settings, diary, catalog, navigation
  ui/         theme, icons, widgets, share images, screens/
  l10n/       app_<lang>.arb (8 languages), labels for languages and genres
tool/         catalog builder, recent-release baker, icon generator, label generator
```

## Licences

- Tanker by Indian Type Foundry, [ITF Free Font License](assets/fonts/Tanker-LICENSE.txt).
- Teko by Indian Type Foundry, [SIL OFL](assets/fonts/Teko-OFL.txt) (Devanagari fallback).
- Wikidata content is CC0. Wikipedia posters are non-free images shown for identification; Talkies loads them from Wikimedia and does not bundle them.
