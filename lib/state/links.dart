import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crews_remote.dart' show normalizeCode, pendingJoinProvider;
import 'providers.dart' show autoRefreshProvider;

// Invite links. `talkies://join?code=<8 chars>` stores the code in
// [pendingJoinProvider]; the Shell and the Together screen decide what to show.
// Nothing else in the app opens from a link.

/// The invite code in a `talkies://join?code=XXXXXXXX` link, or null for any
/// other link and for a code that is not one.
String? joinCodeOf(Uri uri) {
  if (uri.scheme != 'talkies' || uri.host != 'join') return null;
  return normalizeCode(uri.queryParameters['code'] ?? '');
}

/// Where links come from. The app uses the `app_links` plugin; tests give their own.
abstract class LinkSource {
  /// The link that started the app, or null.
  Future<Uri?> initial();

  /// Links that arrive while the app runs.
  Stream<Uri> get stream;
}

class PluginLinks implements LinkSource {
  PluginLinks([AppLinks? links]) : _links = links ?? AppLinks();
  final AppLinks _links;

  @override
  Future<Uri?> initial() => _links.getInitialLink();

  @override
  Stream<Uri> get stream => _links.uriLinkStream;
}

final linkSourceProvider = Provider<LinkSource>((ref) => PluginLinks());

/// Listens for links once the Shell starts it. The plugin README says the stream
/// also carries the first link, but asking for it too costs nothing: the same
/// code set twice is one change.
class LinkListener {
  LinkListener(this._ref);
  final Ref _ref;
  var _started = false;
  StreamSubscription<Uri>? _sub;

  void start() {
    // Tests turn background work off with autoRefreshProvider.
    if (_started || !_ref.read(autoRefreshProvider)) return;
    _started = true;
    final source = _ref.read(linkSourceProvider);
    _sub = source.stream.listen(_take, onError: (Object _) {});
    unawaited(source.initial().then(_take, onError: (Object _) {}));
  }

  void _take(Uri? uri) {
    final code = uri == null ? null : joinCodeOf(uri);
    if (code != null && _ref.mounted) _ref.read(pendingJoinProvider.notifier).set(code);
  }

  void dispose() => _sub?.cancel();
}

final linksProvider = Provider<LinkListener>((ref) {
  final listener = LinkListener(ref);
  ref.onDispose(listener.dispose);
  return listener;
}, retry: (_, _) => null);

/// The Shell calls this once, after the first frame.
void startLinks(WidgetRef ref) => ref.read(linksProvider).start();
