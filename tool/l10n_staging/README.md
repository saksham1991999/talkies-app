# String staging

UI authors write English strings to `en/<area>.json`:

```json
{ "acctSignIn": { "text": "Sign in" }, "friendsCount": { "text": "{count} friends", "placeholders": { "count": "int" } } }
```

Keys are lowerCamelCase with an area prefix (`acct`, `friends`, `crew`, `deck`, `night`, `chat`, `prof`, `gate`).
Plural text uses ICU: `{count, plural, =1{1 friend} other{{count} friends}}`, with `count` declared as `int`.
No em dashes. Plain, short sentences.

Translators write one file per language, `<lang>.json` (`hi ta te bn mr kn ml`), mapping every staged key to its translation.
Keep the same `{placeholders}` and plural structure.

Run `python3 tool/merge_arb.py --check`, then `python3 tool/merge_arb.py`, then `flutter gen-l10n`. Delete the staged files after a merge.
