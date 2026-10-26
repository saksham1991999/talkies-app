# String staging

UI authors write English strings to `en/<area>.json`:

```json
{ "acctSignIn": { "text": "Sign in" }, "friendsCount": { "text": "{count} friends", "placeholders": { "count": "int" } } }
```

Keys are lowerCamelCase with an area prefix (`acct`, `friends`, `crew`, `deck`, `night`, `chat`, `prof`, `gate`).
Plural text uses ICU: `{count, plural, =1{1 friend} other{{count} friends}}`, with `count` declared as `int`.
No em dashes. Plain, short sentences.

Translators write one file per language, `<lang>.json`, mapping every staged key to its translation.
The name is the ARB code, so `zh_Hant.json` and `pt_BR.json` keep their underscore.
Keep the same `{placeholders}` and plural structure.

Run the merge in order:

1. `python3 tool/merge_arb.py --check` validates the staged English strings. (`--draft` runs the same checks.)
2. `python3 tool/merge_arb.py --draft` adds the new keys to all 45 ARBs, the 44 other languages holding the English text as a draft, and records the keys in `drafted.json`.
3. `python3 tool/merge_arb.py --translate` replaces drafts with whatever translations have arrived.

Step 3 reads every `<lang>.json` that exists and checks them **together**, then
applies them all or none. One malformed or partial file fails the whole run: you
get a list of problems and no ARB is touched. Fix the named file and run it
again. A language with no file at all is not an error; it keeps its English draft
and stays listed in `drafted.json`, so a partly translated batch ships nothing
wrong and nothing is lost.
`--translate` prints `no drafts to translate` when `drafted.json` is empty,
which is the state after a completed merge.

`--draft` and `--translate` run `flutter gen-l10n` themselves, so there is no separate step. A bare `python3 tool/merge_arb.py` only prints the usage. Delete the staged files after a merge, and leave `drafted.json` as `[]`.
