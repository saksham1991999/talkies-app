import 'dart:convert';
import 'dart:io';

/// One JSON document on disk. Writes are serialized and atomic (tmp + rename),
/// so a crash mid-write never leaves a half file.
class JsonFile {
  JsonFile(this.file);
  final File file;
  Future<void> _pending = Future.value();

  Map<String, dynamic>? read() {
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      // Keep the unreadable file for recovery instead of overwriting it.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      file.renameSync('${file.path}.corrupt-$stamp');
      return null;
    }
  }

  /// Every write holds the full state, so a failed write (disk full) is
  /// repaired by the next one. A failure must not block later writes.
  void write(Map<String, dynamic> data) {
    final text = jsonEncode(data);
    _pending = _pending.then((_) async {
      try {
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(file.path);
      } on FileSystemException {
        // The next write retries with the full state.
      }
    });
  }

  Future<void> flush() => _pending;
}
