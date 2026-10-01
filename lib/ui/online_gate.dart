import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/online.dart';
import 'format.dart';
import 'widgets.dart';

/// Draws [child] only while the server is up and the user is signed in.
/// Entry points to online features use it, so those features are simply absent
/// when the app has no server, the server is down, or nobody is signed in.
class OnlineOnly extends ConsumerWidget {
  const OnlineOnly({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(onlineProvider) ? child : const SizedBox.shrink();
}

/// Inline message for an online screen that is already open when the server
/// goes away. Calm: the diary is safe, and Retry asks again.
class CantReach extends StatelessWidget {
  const CantReach({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return EmptyNote(l.gateCantReach, action: l.gateRetry, onAction: onRetry);
  }
}
