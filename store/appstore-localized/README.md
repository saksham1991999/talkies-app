# Localized App Store screenshots

What these are, exactly, with no spin:

- **The caption is localized.** The two-line headline at the top of each card is
  in the storefront's language, set in the same Tanker / script-fallback face the
  rest of the deck uses, right-aligned for Arabic, Hebrew and Urdu.
- **The app screenshot inside the card is the English capture.** The diary, the
  tab bar, the buttons and the film titles inside every framed phone are the
  English screenshots from `build/store_raw/`. A Japanese buyer sees a Japanese
  headline above an English app. That is the whole trick, and it is the reason
  the first screenshot still reads before the phone's language is switched.
- **The serial (`NO. 0001` ... `NO. 0008`) stays Latin.** It is part of the
  ticket graphic, not copy.

Nothing here is machine-translated at upload time: the captions are hand-written
and live in `CAPTIONS` in `tool/store_frames.py`, one list of eight per language.

## What is in the folder

46 directories, one per storefront that is **not** English, each holding
`iphone-6.9/` (1320x2868, eight PNGs) and `ipad-13/` (2064x2752, eight PNGs).

```
store/appstore-localized/<storefront>/iphone-6.9/01_home.png ... 08_home_hi_dark.png
store/appstore-localized/<storefront>/ipad-13/01_home.png  ... 08_home_hi_dark.png
```

The directory is named with the **App Store Connect storefront code**
(`de-DE`, `pt-BR`, `es-ES`, `zh-Hans`, `zh-Hant`, `fr-FR`, `fr-CA`, ...), not the
ARB app code (`de`, `pt`, `es`, `zh`, `fr`), because `tool/asc.py` looks the
folder up as `store/appstore-localized/<code>` for the storefront it is pushing.

There are 45 caption sets for 50 storefronts. Three sets are shared on purpose:

| caption set | storefronts | why |
| --- | --- | --- |
| `en` | en-US, en-GB, en-AU, en-CA | Same language. Served from `store/appstore/`, so no copy is written here (see below). |
| `fr-FR` | fr-FR, fr-CA | Quebec French differs in register, not in these eight sentences. |
| `es-ES` | es-ES, es-MX | Same. If you want "ingreso"/"boleto" splits later, add an `es-MX` set to `CAPTIONS`. |

The four English storefronts have no directory here on purpose:
`tool/asc.py:screenshot_files()` returns `store/appstore/` for any code starting
with `en`, so a duplicate English tree here would never be uploaded and would
only drift from the shipped bytes.

`python3 tool/check_captions.py` renders every caption into
`build/caption_check/` and refuses to pass if a glyph would render as a box, a
line would overrun the safe width, the caption ink would touch the serial ink,
two lines would collide, an RTL deck would not be right-aligned, or a deck would
change font or size between its eight cards.

## How to recapture one locale properly

The honest version: the screen should be captured on a simulator whose language
is that storefront's language, so the diary, the tabs and the dates inside the
frame are translated too. That needs two simulators (iPhone 6.9" and iPad 13")
and about 10 minutes per locale.

1. Install the language on the simulator once, then set it (Settings > General >
   Language & Region), or boot with a plist override:

   ```sh
   xcrun simctl boot "iPhone 16 Pro Max"
   xcrun simctl spawn booted defaults write .GlobalPreferences AppleLanguages -array ja
   xcrun simctl spawn booted defaults write .GlobalPreferences AppleLocale -string ja_JP
   xcrun simctl shutdown booted && xcrun simctl boot "iPhone 16 Pro Max"
   ```

2. Point the app at the same language so it does not follow the device blindly:

   ```sh
   flutter drive --driver=test_driver/integration_test.dart \
     --target=integration_test/store_screens_test.dart \
     -d "iPhone 16 Pro Max" --dart-define=STORE_LOCALE=ja
   ```

   Screenshots land in `build/screens/ja/`.

3. Move them where the framer expects them:

   ```sh
   mkdir -p build/store_raw_ja/iphone
   cp build/screens/ja/*.png build/store_raw_ja/iphone/
   ```

4. Repeat steps 1-3 on `iPad Pro 13-inch (M4)` with the same
   `--dart-define=STORE_LOCALE=ja`, then:

   ```sh
   mkdir -p build/store_raw_ja/ipad
   cp build/screens/ja/*.png build/store_raw_ja/ipad/
   ```

5. Frame them. `--locale` takes the app code or the storefront code; the output
   folder is always the storefront code:

   ```sh
   python3 tool/store_frames.py --locale ja
   # -> store/appstore-localized/ja/iphone-6.9/*.png and .../ipad-13/*.png
   ```

   It reads `build/store_raw_ja/` and prints the eight captions it used, so a
   wrong face or a missing glyph is visible in the terminal before the upload.

6. Re-run the checks before committing:

   ```sh
   python3 tool/check_captions.py --strict
   ```

To rebuild every storefront from one set of captures (what produced this
folder, using the English captures on purpose):

```sh
python3 tool/store_frames.py --all-stores --raw build/store_raw --jobs 9
```

That takes about five minutes on a 10-core laptop.

## Size, and whether to commit this tree

It is **2.6 GB** (736 PNGs, 2-4 MB each: the grain overlay defeats PNG
compression, exactly as it does for the 90 MB English set). Committing it makes
every clone of the repo carry 29x the screenshot payload that exists today.

The honest recommendation: add `store/appstore-localized/` to `.gitignore`
except this README, and regenerate it from the command above whenever the
captures or the captions change. The tree is fully derived: one command
reproduces it byte for byte, and nothing else in the repo reads it except
`tool/asc.py`, which only needs it at upload time.

## Ship now, or wait?

My view: **ship them now.** An App Store listing's first screenshot is read
before anything else, and a Hindi or Japanese headline over an English app screen
still tells the buyer "this app is for me" in a way that an English headline does
not. The tab bar being English is a smaller loss than the whole listing being
English.

What you are shipping is a localized advert, not a localized product demo. Write
it down wherever the listing is discussed so nobody later assumes these prove the
app is translated on screen; the app *is* translated (45 locales in
`lib/l10n/`), these captures just are not.

Before the first upload, have a native speaker read the eight lines of each
locale you care about. The wording in `tool/store_frames.py` that I would not
ship without a native read:

- **ur** (Urdu): `شو اور قیمت` reads "show and price" — the film-show sense of
  "show" is `شو` in Pakistani usage, but a proofreader may prefer `نمائش`.
  Also `اسٹریم ہوتی ہے` (it streams) is a transliteration, not an Urdu verb.
- **pt-PT**: `Onde está em exibição` is fine for a cinema, but these cards are
  about streaming, where `Onde ver` is the natural Portuguese of Portugal.
- **ca**: `Comparteix l'entrada` uses a straight apostrophe (`l’entrada` is
  written with U+2019); the caption is correct, the punctuation may be flagged.
- **es-MX** inherits `es-ES` verb forms (`se vuelve`, `butaca`); Mexico says
  `se convierte` and `asiento`.
- **ar**: `أفلام جديدة بكل لغة` is correct but flat; `أفلام جديدة بكل اللغات` is
  the more usual phrasing.
