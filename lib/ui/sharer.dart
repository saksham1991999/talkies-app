import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// The system share sheet, behind a seam so tests record what would be shared
/// instead of opening a sheet.
abstract class Sharer {
  /// Shares [text]. [origin] anchors the sheet on an iPad.
  Future<void> text(String text, {String? subject, Rect? origin});

  /// Shares [bytes] as a file called [name].
  Future<void> file(Uint8List bytes, String name, String mime, {Rect? origin});
}

class SystemSharer implements Sharer {
  const SystemSharer();

  @override
  Future<void> text(String text, {String? subject, Rect? origin}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject, sharePositionOrigin: origin));
  }

  @override
  Future<void> file(Uint8List bytes, String name, String mime, {Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: mime)],
        fileNameOverrides: [name],
        sharePositionOrigin: origin,
      ),
    );
  }
}

final sharerProvider = Provider<Sharer>((ref) => const SystemSharer());

/// The rectangle of [context]'s widget on screen: where the share sheet points on an iPad.
Rect? shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
}
