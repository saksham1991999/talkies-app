import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves screenshots taken by integration tests to build/screens/.
/// `--dart-define=STORE_LOCALE=ja` writes them under build/screens/ja/ instead.
const storeLocale = String.fromEnvironment('STORE_LOCALE');

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final dir = storeLocale.isEmpty ? 'build/screens' : 'build/screens/$storeLocale';
    final f = File('$dir/$name.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return true;
  },
);
