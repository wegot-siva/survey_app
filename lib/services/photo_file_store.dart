import 'dart:io';
import 'dart:typed_data';

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

  /// Writes bytes pulled from Storage into the same `photos/` folder and
  /// returns the new absolute path (Full sync Group 4).
  ///
  /// Named after the photo's id rather than a fresh uuid — unlike
  /// [saveCapture], which can't use an id because capture happens before the
  /// record exists. Here the id is known and stable across devices, so the
  /// name is deterministic: re-downloading the same photo overwrites its own
  /// file instead of accumulating a new copy each sync.
  Future<String> saveDownload(String photoId, Uint8List bytes) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _subdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dest = p.join(dir.path, '$photoId.jpg');
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  /// Best-effort delete of a device-local photo file, used when a pull
  /// reconciles away a tombstoned photo — without it, every device would
  /// keep the image bytes of deleted photos forever. A missing file (already
  /// gone, or never downloaded on this device) is not an error.
  Future<void> deleteLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Nothing actionable: the row is already gone from local storage, and
      // the tombstone stays authoritative regardless of the leftover bytes.
    }
  }
}
