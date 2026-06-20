import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Persists captured photos to a stable on-device location (offline-first).
///
/// `image_picker` returns files in a temporary/cache directory that the OS can
/// evict. This copies the capture into the app's documents directory so the
/// path stored on a record stays valid until sync (and beyond). UI code goes
/// through this service rather than touching the filesystem directly.
class PhotoFileStore {
  PhotoFileStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  static const _subdir = 'photos';

  /// Copies [sourcePath] into the app's documents `photos/` folder under a
  /// fresh unique filename and returns the new absolute path. The filename is
  /// independent of any record id, so capture works before a record is saved.
  Future<String> saveCapture(String sourcePath) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _subdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ext = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final dest = p.join(dir.path, '${_uuid.v4()}$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }
}
