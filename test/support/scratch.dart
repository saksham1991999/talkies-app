import 'dart:io';

/// Deletes a scratch directory, tolerating a write that lands mid-teardown.
///
/// `deleteSync(recursive: true)` lists a directory and then unlinks each entry, so a
/// store save or a provider still settling when the test ends can create a file between
/// the list and the unlink. Linux then throws `ENOTEMPTY` ("Directory not empty, errno =
/// 39") and fails a test that had already passed; macOS usually wins the race, which is
/// why this surfaced in CI and not locally.
///
/// The directory is scratch space under the system temp dir, so a retry is enough and a
/// last failure is safe to leave for the OS to reap.
void removeScratch(Directory dir) {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      sleep(const Duration(milliseconds: 10));
    }
  }
}
