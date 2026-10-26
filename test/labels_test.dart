import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The label vocabulary (language, genre, show slot and country names) lives in
// tool/labels/labels_<code>.json, one file per app locale, generated into
// lib/l10n/labels_more.dart. These tests keep the three in step: a locale added
// to tool/locales.py without a file, a key added to one language only, or a
// generated file left stale all fail here instead of shipping.

final _row = RegExp(r"^\s*\('([A-Za-z_]+)',", multiLine: true);
final _pair = RegExp(r"'([^']+)':\s*\['((?:[^'\\]|\\.)*)'");
final _dartEntry = RegExp(r"^    '([^']+)': '(.*)',$", multiLine: true);

/// App codes from tool/locales.py, the one list of shipped languages.
List<String> locales() {
  final py = File('tool/locales.py').readAsStringSync();
  final start = py.indexOf('LOCALES = [');
  final end = py.indexOf('\n]', start);
  final block = py.substring(start, end);
  return _row.allMatches(block).map((m) => m.group(1)!).toList()..sort();
}

/// The English registry: every key the app may ask for, with its source text.
Map<String, String> englishLabels() {
  final raw = jsonDecode(File('tool/labels/labels_en.json').readAsStringSync()) as Map<String, dynamic>;
  return raw.map((k, v) => MapEntry(k, v as String));
}

Map<String, String> labelFile(String code) {
  final f = File('tool/labels/labels_$code.json');
  final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return raw.map((k, v) => MapEntry(k, v as String));
}

/// Keys the app actually asks for, read out of the `_langs` / `_genres` /
/// `_shows` / `_countries` tables in lib/l10n/labels.dart.
Set<String> labelsUsedByApp() {
  final src = File('lib/l10n/labels.dart').readAsStringSync();
  const prefixes = {'_langs': 'lang', '_genres': 'genre', '_shows': 'show', '_countries': 'country'};
  final out = <String>{};
  for (final MapEntry(key: table, value: prefix) in prefixes.entries) {
    final start = src.indexOf('const $table = {');
    expect(start, greaterThan(0), reason: '$table is gone from labels.dart');
    final end = src.indexOf('\n};', start);
    final body = src.substring(start, end);
    for (final m in _pair.allMatches(body)) {
      out.add('$prefix:${m.group(1)}');
    }
  }
  return out;
}

/// lib/l10n/labels_more.dart as a map, unescaping the generated quotes.
Map<String, Map<String, String>> generated() {
  final src = File('lib/l10n/labels_more.dart').readAsStringSync();
  final out = <String, Map<String, String>>{};
  String? current;
  for (final line in const LineSplitter().convert(src)) {
    final head = RegExp(r"^  '([^']+)': \{$").firstMatch(line);
    if (head != null) {
      current = head.group(1);
      out[current!] = {};
      continue;
    }
    if (line == '  },') {
      current = null;
      continue;
    }
    final entry = _dartEntry.firstMatch(line);
    if (entry != null && current != null) {
      out[current]![entry.group(1)!] = entry.group(2)!.replaceAll(r'\$', r'$').replaceAll(r"\'", "'").replaceAll(r'\\', r'\');
    }
  }
  return out;
}

void main() {
  test('every locale in tool/locales.py has a labels file', () {
    final missing = locales().where((c) => !File('tool/labels/labels_$c.json').existsSync()).toList();
    expect(missing, isEmpty, reason: 'no tool/labels/labels_<code>.json for: ${missing.join(', ')}');
  });

  test('no stray labels file for a locale the app does not ship', () {
    final known = locales().toSet();
    final files = Directory('tool/labels')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.startsWith('labels_') && n.endsWith('.json'));
    for (final name in files) {
      final code = name.substring('labels_'.length, name.length - '.json'.length);
      expect(known, contains(code), reason: '$name is not a locale in tool/locales.py');
    }
  });

  test('every language file carries the identical key set', () {
    final keys = englishLabels().keys.toSet();
    expect(keys, isNotEmpty);
    for (final code in locales()) {
      final got = labelFile(code).keys.toSet();
      expect(got.difference(keys), isEmpty, reason: '$code has keys the English registry lacks');
      expect(keys.difference(got), isEmpty, reason: '$code is missing keys: ${keys.difference(got).join(', ')}');
    }
  });

  test('every key the app asks for is in the English fallback map', () {
    final used = labelsUsedByApp();
    final known = englishLabels().keys.toSet();
    expect(known.difference(used), isEmpty, reason: 'dead keys in labels_en.json: ${known.difference(used).join(', ')}');
    expect(used.difference(known), isEmpty, reason: 'labels.dart asks for keys with no English text: ${used.difference(known).join(', ')}');
  });

  test('no empty value and no em dash in any language', () {
    for (final code in locales()) {
      for (final MapEntry(:key, :value) in labelFile(code).entries) {
        expect(value.trim(), isNotEmpty, reason: '$code $key is empty');
        expect(value, isNot(contains('\u2014')), reason: '$code $key has an em dash');
        expect(value, isNot(contains('\u2013')), reason: '$code $key has an en dash');
        expect(value, equals(value.trim()), reason: '$code $key has stray whitespace');
      }
    }
  });

  test('no two keys in a family share a value', () {
    // Two film languages never share a name, and a picker that prints the same
    // word for two show slots or two genres is broken. Country names do repeat
    // against language names on purpose (`country:DE` / `lang:de`).
    for (final code in locales()) {
      final file = labelFile(code);
      for (final family in ['lang', 'genre', 'show', 'country']) {
        final seen = <String, String>{};
        for (final MapEntry(:key, :value) in file.entries.where((e) => e.key.startsWith('$family:'))) {
          expect(seen, isNot(contains(value)),
              reason: '$code: $family:${seen[value]} and $key both print "$value"');
          seen[value] = key.substring(family.length + 1);
        }
      }
    }
  });

  test('lib/l10n/labels_more.dart matches the JSON files', () {
    final dart = generated();
    final codes = locales()..sort();
    expect(dart.keys.toSet(), codes.toSet(), reason: 'run python3 tool/gen_labels.py tool/labels/*.json');
    final en = englishLabels();
    for (final code in codes) {
      final json = labelFile(code);
      expect(dart[code]!.keys.toSet(), en.keys.toSet(), reason: '$code block has the wrong keys');
      for (final key in en.keys) {
        expect(dart[code]![key], json[key], reason: '$code $key is stale in labels_more.dart');
      }
    }
  });
}
