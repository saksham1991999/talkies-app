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

final _branch = RegExp(r'(?:=\d+|zero|one|two|few|many|other)\s*$');

/// Argument names in an ICU message. A one-word plural branch body, like `other{films}`, is text.
Set<String> holes(String text) {
  final out = <String>{};
  for (final m in RegExp(r'\{\s*(\w+)\s*(\}|,\s*(?:plural|select))').allMatches(text)) {
    if (m.group(2) == '}' && _branch.hasMatch(text.substring(0, m.start))) continue;
    out.add(m.group(1)!);
  }
  return out;
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

  test('no string holds an em dash', () {
    for (final lang in ['en', ...langs]) {
      for (final e in strings(lang).entries) {
        expect(e.value, isNot(contains('—')), reason: '$lang.${e.key}');
      }
    }
  });
}
