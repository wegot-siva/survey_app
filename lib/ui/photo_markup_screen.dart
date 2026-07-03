import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/photo_file_store.dart';

const double _strokeWidth = 6;

/// Full-screen freehand markup over an existing photo (photo markup slice 1).
///
/// Capture only — no shapes/text, just a pen in one of two colours, plus
/// single taps for simple dot marks. On save, the drawing is flattened onto
/// the photo and written out through the existing [PhotoFileStore] capture
/// pipeline (so it's just "a new captured file" as far as storage/sync are
/// concerned — nothing new to build there). Returns the new local path, or
/// null if the user backs out (or saves with nothing drawn).
class PhotoMarkupScreen extends StatefulWidget {
  const PhotoMarkupScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<PhotoMarkupScreen> createState() => _PhotoMarkupScreenState();
}

class _PhotoMarkupScreenState extends State<PhotoMarkupScreen> {
  static const _penColors = [Colors.red, Colors.yellow];

  final GlobalKey _boundaryKey = GlobalKey();
  final List<_Stroke> _strokes = [];

  Color _color = _penColors.first;
  Uint8List? _imageBytes;
  int _imageWidth = 0;
  int _imageHeight = 0;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageWidth = frame.image.width;
      _imageHeight = frame.image.height;
      _loading = false;
    });
  }

  void _onPanStart(DragStartDetails details) {
    setState(() => _strokes.add(_Stroke(_color)..points.add(details.localPosition)));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _strokes.last.points.add(details.localPosition));
  }

  void _undo() {
    setState(() => _strokes.removeLast());
  }

  void _clear() {
    setState(() => _strokes.clear());
  }

  Future<void> _save() async {
    if (_strokes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Render at the original photo's resolution, not the screen's — so
      // markup doesn't downgrade the photo's quality.
      final pixelRatio = _imageWidth / boundary.size.width;
      final flattened = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await flattened.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(
        tempDir.path,
        'markup_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await File(tempPath).writeAsBytes(pngBytes);
      // Same pipeline a fresh capture uses — copies into stable storage.
      final savedPath = await PhotoFileStore().saveCapture(tempPath);
      await File(tempPath).delete();

      if (!mounted) return;
      Navigator.of(context).pop(savedPath);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save markup: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = _imageBytes;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Mark photo'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _strokes.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Clear all marks',
            onPressed: _strokes.isEmpty ? null : _clear,
            icon: const Icon(Icons.layers_clear_outlined),
          ),
          IconButton(
            tooltip: 'Save',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: _loading || imageBytes == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: AspectRatio(
                aspectRatio: _imageWidth / _imageHeight,
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(imageBytes, fit: BoxFit.fill),
                        CustomPaint(painter: _MarkupPainter(_strokes)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in _penColors)
                      _ColorSwatch(
                        color: c,
                        selected: c == _color,
                        onTap: () => setState(() => _color = c),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Stroke {
  _Stroke(this.color);

  final Color color;
  final List<Offset> points = [];
}

class _MarkupPainter extends CustomPainter {
  const _MarkupPainter(this.strokes);

  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first,
          _strokeWidth / 2,
          Paint()..color = stroke.color,
        );
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = stroke.color
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  // Strokes mutate in place (same list instance); always repaint on rebuild
  // rather than diffing — repaints are bounded by user interaction.
  @override
  bool shouldRepaint(covariant _MarkupPainter oldDelegate) => true;
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
