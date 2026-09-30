// Reads where films and series stream from their Wikipedia articles and adds
// it to the bundled catalog. Covers series and films from 2010 on.
//
// Run after tool/build_catalog.py:  dart run tool/bake_ott.dart   (about 20 minutes)
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:talkies/data/catalog.dart';

Future<void> main() async {
  final file = File('assets/catalog/catalog.json');
  final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final items = (j['items'] as List).cast<Map<String, dynamic>>();
  String wiki(Map<String, dynamic> e) => (e['w'] as String?) ?? e['t'] as String;
  final chosen = [
    for (final e in items)
      if (e['k'] == 's' || ((e['y'] as int?) ?? 0) >= 2010) e,
  ];
  final c = http.Client();
  var added = 0, withOtt = 0;
  try {
    for (var i = 0; i < chosen.length; i += 500) {
      final part = chosen.sublist(i, i + 500 > chosen.length ? chosen.length : i + 500);
      final found = await fetchStreaming(c, [for (final e in part) wiki(e)]);
      for (final e in part) {
        final more = found[wiki(e)] ?? const <String>[];
        final before = ((e['ott'] as List?) ?? const []).cast<String>();
        final all = {...before, ...more}.toList();
        if (all.length > before.length) added++;
        if (all.isNotEmpty) {
          e['ott'] = all;
          withOtt++;
        }
      }
      stdout.writeln('${i + part.length}/${chosen.length} scanned, $added gained services');
    }
  } finally {
    c.close();
  }
  file.writeAsStringSync(jsonEncode(j));
  stdout.writeln('done: $withOtt of ${chosen.length} scanned titles have services; $added gained them');
}
