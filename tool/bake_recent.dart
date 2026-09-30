// Folds recent and upcoming Indian releases (Wikidata + Wikipedia lists) into
// the bundled catalog, so the app has fresh releases before it ever goes online.
//
// Run after tool/build_catalog.py:  dart run tool/bake_recent.dart
import 'dart:convert';
import 'dart:io';

import 'package:talkies/data/catalog.dart';
import 'package:talkies/data/models.dart';

Future<void> main() async {
  final bundled = File('assets/catalog/catalog.json');
  final delta = File('${Directory.systemTemp.createTempSync('talkies').path}/delta.json');
  final today = dateOnly(DateTime.now());
  final n = await refreshCatalog(delta, today);
  final c = Catalog.parse(bundled.readAsStringSync(), delta.readAsStringSync());
  bundled.writeAsStringSync(jsonEncode({'built': ymd(today), 'items': c.items.map((f) => f.toJson()).toList()}));
  stdout.writeln(
    'baked $n recent films; catalog has ${c.items.length} items, ${(bundled.lengthSync() / 1e6).toStringAsFixed(1)} MB',
  );
}
