import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/photo_file_store.dart';

/// Mutable per-field photo state a form holds until it saves. `id` is empty
/// until the photo has been persisted to the repository.
class PhotoDraft {
  PhotoDraft({this.id = '', this.localPath, this.remotePath});

  String id;
  String? localPath;
  String? remotePath;

  bool get uploaded => remotePath != null;
}

/// A single captured photo's view state for [MultiPhotoCaptureField].
///
/// [localPath] is nullable because a photo's metadata and its image file
/// arrive separately: a photo pulled from another device exists as a row
/// well before its bytes finish downloading in the background (see
/// SyncService.downloadMissingPhotoFilesInBackground). Such a photo renders
/// as a "downloading" placeholder rather than being hidden.
///
/// Hiding it — which is what every caller used to do, via
/// `if (d.localPath != null)` — was actively unsafe, because the callers'
/// callbacks are index-based: filtering the displayed list while indexing
/// the unfiltered one meant removing one photo deleted a different one. It
/// also meant a form's save list silently omitted the pending photo, and
/// SurveyRepository.setPhotos tombstones anything absent from the list it's
/// given — so merely opening and saving a form during the download window
/// would have deleted the photo from Supabase and every other device.
/// Keeping the display list 1:1 with the model list is what makes both of
/// those impossible.
class PhotoView {
  const PhotoView(this.localPath, {this.uploaded = false});

  /// Where the image file lives, or null while it is still downloading.
  final String? localPath;
  final bool uploaded;
}

/// Opens the camera, copies the capture into stable storage (offline-first),
/// and returns the saved path — or null if cancelled. Errors surface via a
/// SnackBar on [context].
Future<String?> capturePhotoToStore(
  BuildContext context, {
  required ImagePicker picker,
  required PhotoFileStore store,
}) async {
  try {
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 2000,
    );
    if (shot == null) return null;
    return await store.saveCapture(shot.path);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture photo: $e')),
      );
    }
    return null;
  }
}

/// Capture + preview for a photo field. Every photo field allows multiple
/// photos: shows a wrap of thumbnails (each removable, each with an
/// uploaded/pending badge) and an "Add photo" button.
class MultiPhotoCaptureField extends StatefulWidget {
  const MultiPhotoCaptureField({
    super.key,
    required this.label,
    required this.photos,
    required this.onAdded,
    required this.onRemoved,
    this.onEdit,
    this.onView,
    this.readOnly = false,
  });

  final String label;
  final List<PhotoView> photos;
  final ValueChanged<String> onAdded;
  final ValueChanged<int> onRemoved;

  /// Optional — when provided, tapping a thumbnail invokes this with the
  /// photo's index, e.g. to open a markup screen. Takes priority over
  /// [onView] when both are given (only one applies at a time in practice —
  /// [onEdit] for editable forms, [onView] for read-only ones).
  final ValueChanged<int>? onEdit;

  /// Optional — when [onEdit] isn't given (or the field is [readOnly]),
  /// tapping a thumbnail invokes this instead, e.g. to open a read-only
  /// full-screen viewer. Lets a read-only form still preview photos without
  /// exposing markup/edit capability.
  final ValueChanged<int>? onView;

  /// When true: no "Add photo" button, no remove badge, and no edit
  /// affordance — tapping a thumbnail (if [onView] is given) only opens a
  /// read-only preview.
  final bool readOnly;

  @override
  State<MultiPhotoCaptureField> createState() => _MultiPhotoCaptureFieldState();
}

class _MultiPhotoCaptureFieldState extends State<MultiPhotoCaptureField> {
  final ImagePicker _picker = ImagePicker();
  final PhotoFileStore _store = PhotoFileStore();
  bool _capturing = false;

  Future<void> _add() async {
    setState(() => _capturing = true);
    final path = await capturePhotoToStore(
      context,
      picker: _picker,
      store: _store,
    );
    if (!mounted) return;
    setState(() => _capturing = false);
    if (path != null) widget.onAdded(path);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          if (widget.photos.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < widget.photos.length; i++)
                  _Thumb(
                    photo: widget.photos[i],
                    onRemove: widget.readOnly ? null : () => widget.onRemoved(i),
                    onEdit: widget.readOnly || widget.onEdit == null
                        ? null
                        : () => widget.onEdit!(i),
                    onView: widget.onView == null
                        ? null
                        : () => widget.onView!(i),
                  ),
              ],
            ),
          if (!widget.readOnly) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _capturing ? null : _add,
              icon: _capturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add photo'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.photo,
    required this.onRemove,
    this.onEdit,
    this.onView,
  });

  final PhotoView photo;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;

  /// Used for the main-image tap when [onEdit] isn't set — e.g. a read-only
  /// full-screen preview instead of the markup editor.
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final localPath = photo.localPath;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            // No file yet means nothing to open or mark up. The remove
            // affordance below stays live: deleting a photo whose image is
            // still downloading is a perfectly reasonable thing to want, and
            // is now safe because the displayed list matches the model list
            // index for index.
            onTap: localPath == null ? null : (onEdit ?? onView),
            child: localPath == null
                ? const _PendingThumb()
                : Image.file(
                    File(localPath),
                    height: 96,
                    width: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => SizedBox(
                      height: 96,
                      width: 96,
                      child: _UnavailableThumb(),
                    ),
                  ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        Positioned(
          left: 2,
          bottom: 2,
          child: Icon(
            photo.uploaded ? Icons.cloud_done : Icons.cloud_off,
            size: 16,
            color: Colors.white,
          ),
        ),
        // Hidden while the image is still downloading — there is no file for
        // the markup editor to open.
        if (onEdit != null && localPath != null)
          // The visual badge stays small (unchanged), but its tappable area
          // is padded out to close to Material's 44dp minimum touch target —
          // a precise tap on the tiny icon alone was unreliable. Anchored at
          // the corner (not centered on the badge), so this only grows
          // inward, never clipped by the Stack's bounds.
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onEdit,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(3),
                    child: const Icon(Icons.edit, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A photo whose metadata has synced but whose image is still downloading in
/// the background. Distinct from [_UnavailableThumb], which means the file
/// was expected to be here and isn't — this one is a normal, transient state
/// that resolves itself, so it reads as progress rather than as an error.
class _PendingThumb extends StatelessWidget {
  const _PendingThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      width: 96,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(height: 6),
          Text('Downloading', style: TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _UnavailableThumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Text('Saved photo unavailable.'),
    );
  }
}

/// Opens [imagePath] full-screen, pinch-to-zoom, with no edit/markup
/// affordance — for reviewers (e.g. Approver) who should be able to inspect
/// a captured photo but never alter it.
Future<void> openPhotoViewer(
  BuildContext context,
  String imagePath, {
  String title = 'Photo',
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PhotoViewerScreen(imagePath: imagePath, title: title),
    ),
  );
}

class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({
    super.key,
    required this.imagePath,
    this.title = 'Photo',
  });

  final String imagePath;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Photo unavailable.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
