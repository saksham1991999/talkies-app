import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Every language file carries the same keys and the same {placeholders} as English.

const langs = ['hi', 'ta', 'te', 'bn', 'mr', 'kn', 'ml'];

Map<String, String> strings(String lang) {
  final j = jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in j.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

final _arg = RegExp(r'\{\s*(\w+)\s*(?:,\s*(plural|select)\b)?');
final _label = RegExp(r'(?:=\w+|\w+)\s*\{');

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

/// Runs `placeholders()` from tool/merge_arb.py over [texts]: one set of names
/// per text. That Python copy is the reference the l10n tooling validates with.
List<Set<String>> pythonHoles(List<String> texts) {
  const scanner =
      'import json, sys\n'
      'sys.path.insert(0, sys.argv[2])\n'
      'import merge_arb\n'
      'print(json.dumps([sorted(merge_arb.placeholders(t)) for t in json.loads(sys.argv[1])]))\n';
  final tool = Directory('tool').absolute.path;
  final run = Process.runSync(
    'python3',
    ['-c', scanner, jsonEncode(texts), tool],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (run.exitCode != 0) fail('python3 could not run tool/merge_arb.py: ${run.stderr}');
  return [for (final names in jsonDecode(run.stdout as String) as List) (names as List).cast<String>().toSet()];
}

void main() {
  final en = strings('en');

  for (final lang in langs) {
    test('$lang has the keys and placeholders of English', () {
      final t = strings(lang);
      expect(t.keys.toSet(), en.keys.toSet(), reason: 'key sets differ');
      for (final k in en.keys) {
        expect(holes(t[k]!), holes(en[k]!), reason: '$lang.$k placeholders');
        if (en[k]!.contains('plural,')) expect(t[k], contains('other{'), reason: '$lang.$k plural needs other');
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
    expect(pythonHoles(_fixtures), [for (final text in _fixtures) holes(text)]);
  });

  test('no string holds an em dash', () {
    for (final lang in ['en', ...langs]) {
      for (final e in strings(lang).entries) {
        expect(e.value, isNot(contains('—')), reason: '$lang.${e.key}');
      }
    }
  });
}
