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
class PhotoView {
  const PhotoView(this.localPath, {this.uploaded = false});

  final String localPath;
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
  });

  final String label;
  final List<PhotoView> photos;
  final ValueChanged<String> onAdded;
  final ValueChanged<int> onRemoved;

  /// Optional — when provided, tapping a thumbnail invokes this with the
  /// photo's index, e.g. to open a markup screen. Fields that don't pass this
  /// render exactly as before: no edit affordance, unchanged behavior.
  final ValueChanged<int>? onEdit;

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
                    onRemove: () => widget.onRemoved(i),
                    onEdit: widget.onEdit == null
                        ? null
                        : () => widget.onEdit!(i),
                  ),
              ],
            ),
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
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.onRemove, this.onEdit});

  final PhotoView photo;
  final VoidCallback onRemove;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            onTap: onEdit,
            child: Image.file(
              File(photo.localPath),
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
        if (onEdit != null)
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
