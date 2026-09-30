import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talkies/data/catalog.dart';

void main() {
  List<String> read(String name) => ottInWikitext(File('test/fixtures/article_$name.wiki').readAsStringSync());

  test('real articles', () {
    expect(read('kantara'), containsAll(['netflix', 'prime']));
    expect(read('hi_nanna'), contains('netflix'));
    expect(read('panchayat'), contains('prime'));
  });

  test('infobox network and distributor count', () {
    expect(ottInWikitext('{{Infobox television\n| network = [[SonyLIV]]\n}}'), ['sonyliv']);
    expect(ottInWikitext('| distributor = [[Netflix]]'), ['netflix']);
  });

  test('sentences need a streaming word; references and comments are ignored', () {
    expect(ottInWikitext('The film was shot in Hyderabad. [[Netflix]] was not involved in casting'), isEmpty);
    expect(ottInWikitext('It premiered at the [[Toronto International Film Festival]].'), isEmpty);
    expect(ottInWikitext('Released in cinemas.<ref>{{cite web|title=Streaming on Netflix soon}}</ref>'), isEmpty);
    expect(ottInWikitext('<!-- began streaming on [[ZEE5]] -->Released in cinemas.'), isEmpty);
    expect(ottInWikitext('It began streaming on [[Disney+ Hotstar]] from 4 July.'), ['jiohotstar']);
    expect(ottInWikitext('The digital rights were acquired by [[Aha (streaming service)|Aha]].'), ['aha']);
    expect(ottInWikitext('The film started streaming on aha from 1 May.'), ['aha']);
    expect(ottInWikitext('"Aha!" he said. It premiered in theatres.'), isEmpty);
  });

  test('a classic with no streaming mention stays empty or known', () {
    expect(read('sholay').every(['netflix', 'prime', 'jiohotstar', 'sonyliv', 'zee5', 'erosnow', 'mubi'].contains), isTrue);
  });
}
