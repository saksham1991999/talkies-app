import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the Together tab in the Shell. Appended after Stats, so the old
/// tab numbers (`go(1)`, `go(3)`) stay valid.
const togetherTab = 5;

/// Segments of the Together tab. `friends` shows only while the app is online.
enum TogetherSegment { groups, nights, friends }

class TogetherSegmentNotifier extends Notifier<TogetherSegment> {
  @override
  TogetherSegment build() => TogetherSegment.groups;
  void go(TogetherSegment s) => state = s;
}

final togetherSegmentProvider = NotifierProvider<TogetherSegmentNotifier, TogetherSegment>(TogetherSegmentNotifier.new);
