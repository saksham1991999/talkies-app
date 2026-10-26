import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Every language file carries the same keys, the same {placeholders} and the
// CLDR plural forms of its language. The locale list is read from disk and from
// tool/locales.py, so a new file is covered without editing this test.

final _arg = RegExp(r'\{\s*(\w+)\s*(?:,\s*(plural|select)\b)?');
final _label = RegExp(r'(?:=\w+|\w+)\s*\{');
final _pluralHead = RegExp(r'\{\s*\w+\s*,\s*plural\s*,');

List<String> languages() {
  final out = <String>[];
  for (final f in Directory('lib/l10n').listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.startsWith('app_') && name.endsWith('.arb')) {
      final code = name.substring(4, name.length - 4);
      if (code != 'en') out.add(code);
    }
  }
  return out..sort();
}

Map<String, String> strings(String lang) {
  final j = jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in j.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

/// Index of the `}` closing the `{` at [i], or -1 when the braces do not balance.
int _blockEnd(String text, int i) {
  var depth = 0;
  for (var j = i; j < text.length; j++) {
    if (text[j] == '{') depth++;
    if (text[j] == '}') {
      depth--;
      if (depth == 0) return j;
    }
  }
  return -1;
}

void _scan(String text, int i, int stop, Set<String> names) {
  while (i < stop) {
    final m = text[i] == '{' ? _arg.matchAsPrefix(text, i) : null;
    if (m == null) {
      i++;
      continue;
    }
    final close = _blockEnd(text, i);
    if (close < 0) {
      i++;
      continue;
    }
    names.add(m.group(1)!);
    if (m.group(2) != null) {
      // `{count, plural, =1{1 ticket} other{films}}`: the case labels and their
      // bodies hold text, so only the block argument is a name. Branch labels
      // are recognised only inside such a block, which is why plain copy
      // ending in "one" or "other" keeps its `{name}`.
      var j = m.end;
      while (j < close) {
        final label = _label.matchAsPrefix(text, j);
        final body = label == null ? -1 : label.end - 1;
        final end = label == null ? -1 : _blockEnd(text, body);
        if (end < 0 || end > close) {
          j++;
        } else {
          _scan(text, body + 1, end, names);
          j = end + 1;
        }
      }
    }
    i = close + 1;
  }
}

/// Argument names in an ICU message. A one-word plural branch body, like `other{films}`, is text.
Set<String> holes(String text) {
  final out = <String>{};
  _scan(text, 0, text.length, out);
  return out;
}

/// The CLDR categories a message provides. `=1` exact branches do not count.
Set<String> pluralCategories(String text) {
  final out = <String>{};
  for (final m in _pluralHead.allMatches(text)) {
    final close = _blockEnd(text, m.start);
    if (close < 0) continue;
    var j = m.end;
    while (j < close) {
      final label = _label.matchAsPrefix(text, j);
      final body = label == null ? -1 : label.end - 1;
      final end = label == null ? -1 : _blockEnd(text, body);
      if (end < 0 || end > close) {
        j++;
        continue;
      }
      final name = label!.group(0)!.split('{')[0].trim();
      if (!name.startsWith('=')) out.add(name);
      j = end + 1;
    }
  }
  return out;
}

/// The messages the two copies of the scanner are compared on. `tool/merge_arb.py`
/// validates the same rule before it writes an ARB, so both must read them alike.
const _fixtures = [
  'Only one {count}',
  'You are the other {name} here',
  '{count, plural, =1{1 ticket} other{{count} tickets}}',
  '{count, plural, other{films}}',
  '{count, plural, zero{no tickets} one{one ticket} other{{count} tickets}}',
  '{gender, select, other{{name} joined}}',
  '{n, plural, other{{count, plural, other{{n} of {count}}}}}',
  'no placeholders at all',
];

/// Runs a function from tool/merge_arb.py over [texts], one result per text.
List<Object?> pythonScan(String fn, List<String> texts) {
  final scanner =
      'import json, sys\n'
      'sys.path.insert(0, sys.argv[2])\n'
      'import merge_arb\n'
      'f = getattr(merge_arb, sys.argv[3])\n'
      'print(json.dumps([sorted(f(t)) for t in json.loads(sys.argv[1])]))\n';
  final tool = Directory('tool').absolute.path;
  final run = Process.runSync(
    'python3',
    ['-c', scanner, jsonEncode(texts), tool, fn],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (run.exitCode != 0) fail('python3 could not run tool/merge_arb.py: ${run.stderr}');
  return jsonDecode(run.stdout as String) as List<Object?>;
}

/// The CLDR forms each locale must provide, straight from tool/locales.py.
Map<String, List<String>> pythonPluralRequired() {
  const scanner =
      'import json, sys\n'
      'sys.path.insert(0, sys.argv[1])\n'
      'import locales\n'
      'print(json.dumps({c: sorted(locales.plural_required(c)) for c in locales.app_codes()}))\n';
  final tool = Directory('tool').absolute.path;
  final run = Process.runSync('python3', ['-c', scanner, tool], stdoutEncoding: utf8, stderrEncoding: utf8);
  if (run.exitCode != 0) fail('python3 could not run tool/locales.py: ${run.stderr}');
  return (jsonDecode(run.stdout as String) as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, (v as List).cast<String>()));
}

void main() {
  final en = strings('en');
  final langs = languages();

  test('every App Store language has a file', () {
    final required = pythonPluralRequired().keys.toSet()..remove('en');
    expect(langs.toSet(), required, reason: 'lib/l10n/app_*.arb does not match tool/locales.py');
  });

  for (final lang in langs) {
    test('$lang has the keys and placeholders of English', () {
      final t = strings(lang);
      expect(t.keys.toSet(), en.keys.toSet(), reason: 'key sets differ');
      for (final k in en.keys) {
        expect(holes(t[k]!), holes(en[k]!), reason: '$lang.$k placeholders');
        if (en[k]!.contains('plural,')) expect(t[k], contains('other{'), reason: '$lang.$k plural needs other');
      }
    });

    test('$lang carries its CLDR plural forms', () {
      final t = strings(lang);
      final need = pythonPluralRequired()[lang]!.toSet();
      // A message still holding the English text is an unfinished draft: it is
      // skipped here, and tool/l10n_status.py keeps that locale out of the app.
      for (final k in en.keys.where((k) => en[k]!.contains('plural,') && t[k] != en[k])) {
        expect(pluralCategories(t[k]!).containsAll(need), isTrue,
            reason: '$lang.$k needs ${need.difference(pluralCategories(t[k]!)).join(',')}');
      }
    });
  }

  test('branch labels count as arguments only inside a plural/select block', () {
    // Copy that happens to end in "one" or "other" still carries its argument.
    expect(holes(_fixtures[0]), {'count'});
    expect(holes(_fixtures[1]), {'name'});
    expect(holes(_fixtures[2]), {'count'});
    expect(holes(_fixtures[3]), {'count'});
    expect(holes(_fixtures[4]), {'count'});
    expect(holes(_fixtures[5]), {'gender', 'name'});
    expect(holes(_fixtures[6]), {'n', 'count'});
    expect(holes(_fixtures[7]), <String>{});
  });

  test('the Dart scanner agrees with tool/merge_arb.py on the same messages', () {
    // The rule lives in two places: `holes()` here and `placeholders()` in the
    // Python tool that validates the ARBs. Run the Python one and compare, so a
    // drift in either copy fails here instead of shipping as a bad translation.
    final py = pythonScan('placeholders', _fixtures);
    expect(py, [for (final text in _fixtures) holes(text).toList()..sort()]);
    final pyPlural = pythonScan('plural_categories', _fixtures);
    expect(pyPlural, [for (final text in _fixtures) pluralCategories(text).toList()..sort()]);
  });

  test('no string holds an em dash', () {
    for (final lang in ['en', ...langs]) {
      for (final e in strings(lang).entries) {
        expect(e.value, isNot(contains('—')), reason: '$lang.${e.key}');
      }
    }
  });

  test('no string borrows a letter from another script', () {
    // Machine translation drops single letters of a neighbouring alphabet into
    // the middle of a word: Korean 삭제 inside Thai, Hindi बदल inside Punjabi,
    // Tamil ட inside Gujarati. The result looks almost right and is unreadable
    // to a native speaker, so it has to fail here rather than ship.
    //
    // Only letters are checked: every Indic locale legitimately shares the
    // danda । with Devanagari, and digits and punctuation cross scripts.
    const ranges = <String, (int, int)>{
      'devanagari': (0x0900, 0x097F), 'bengali': (0x0980, 0x09FF),
      'gurmukhi': (0x0A00, 0x0A7F), 'gujarati': (0x0A80, 0x0AFF),
      'oriya': (0x0B00, 0x0B7F), 'tamil': (0x0B80, 0x0BFF),
      'telugu': (0x0C00, 0x0C7F), 'kannada': (0x0C80, 0x0CFF),
      'malayalam': (0x0D00, 0x0D7F), 'thai': (0x0E00, 0x0E7F),
      'hangul': (0xAC00, 0xD7AF), 'kana': (0x3040, 0x30FF),
      'han': (0x4E00, 0x9FFF), 'arabic': (0x0600, 0x06FF),
      'hebrew': (0x0590, 0x05FF), 'cyrillic': (0x0400, 0x04FF),
      'greek': (0x0370, 0x03FF),
    };
    const danda = {0x0964, 0x0965, 0x0970};
    const expected = <String, String>{
      'ar': 'arabic', 'bn': 'bengali', 'hi': 'devanagari', 'mr': 'devanagari',
      'gu': 'gujarati', 'or': 'oriya', 'pa': 'gurmukhi', 'ta': 'tamil',
      'te': 'telugu', 'kn': 'kannada', 'ml': 'malayalam', 'th': 'thai',
      'he': 'hebrew', 'ru': 'cyrillic', 'uk': 'cyrillic', 'el': 'greek',
      'ja': 'kana', 'zh': 'han', 'zh_Hant': 'han', 'ko': 'hangul',
    };
    for (final MapEntry(key: lang, value: own) in expected.entries) {
      for (final e in strings(lang).entries) {
        for (final rune in e.value.runes) {
          final ch = String.fromCharCode(rune);
          // Letters only; `Dart` has no Unicode category call, so use the
          // scripts themselves as the signal and ignore shared punctuation.
          if (danda.contains(rune)) continue;
          for (final MapEntry(key: script, value: span) in ranges.entries) {
            if (rune < span.$1 || rune > span.$2) continue;
            // Han is shared with kana in Japanese by design.
            final allowed = script == own || (lang == 'ja' && script == 'han');
            expect(allowed, isTrue,
                reason: '$lang.${e.key} holds $script letter "$ch" (U+'
                    '${rune.toRadixString(16).toUpperCase()}): ${e.value}');
            break;
          }
        }
      }
    }
  });
}
