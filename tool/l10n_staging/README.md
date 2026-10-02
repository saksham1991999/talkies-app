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

Run the merge in order:

1. `python3 tool/merge_arb.py --check` validates the staged English strings. (`--draft` runs the same checks.)
2. `python3 tool/merge_arb.py --draft` adds the new keys to all 8 ARBs, the 7 other languages with the English text as a draft.
3. When `<lang>.json` exists for every language (`hi ta te bn mr kn ml`), `python3 tool/merge_arb.py --translate` replaces the drafts with those translations.

`--draft` and `--translate` run `flutter gen-l10n` themselves, so there is no separate step. A bare `python3 tool/merge_arb.py` only prints the usage. Delete the staged files after a merge.
