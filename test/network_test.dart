import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:talkies/data/catalog.dart';

/// Live calls to Wikidata and Wikipedia. Run with: NETWORK=1 flutter test test/network_test.dart
void main() {
  final skip = Platform.environment['NETWORK'] != '1';

  test(
    'refresh fetches recent and upcoming Indian films',
    () async {
      final dir = Directory.systemTemp.createTempSync('talkies_net');
      final delta = File('${dir.path}/catalog_delta.json');
      final n = await refreshCatalog(delta, DateTime(2026, 9, 30));
      expect(n, greaterThan(150));
      final items = (jsonDecode(delta.readAsStringSync()) as Map)['items'] as List;
      expect(items.where((e) => e['p'] != null).length, greaterThan(5));
      final c = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync(), delta.readAsStringSync());
      expect(c.upcoming(DateTime(2026, 9, 30)), isNotEmpty);
      dir.deleteSync(recursive: true);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('streaming services come from live articles', () async {
    final c = http.Client();
    final found = await fetchStreaming(c, ['Jawan (film)', 'Panchayat (TV series)', 'Kantara (film)']);
    c.close();
    expect(found['Jawan (film)'], contains('netflix'));
    expect(found['Panchayat (TV series)'], contains('prime'));
    expect(found['Kantara (film)'], contains('prime'));
  }, skip: skip);

  test('synopsis comes from Wikipedia', () async {
    final s = await fetchSynopsis('Sholay');
    expect(s, contains('Sholay'));
  }, skip: skip);
}
