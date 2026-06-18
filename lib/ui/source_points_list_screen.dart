import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import 'source_point_form_screen.dart';

/// Lists a site's source points with add / edit / delete.
class SourcePointsListScreen extends StatefulWidget {
  const SourcePointsListScreen({
    super.key,
    required this.repository,
    required this.site,
  });

  final SurveyRepository repository;
  final Site site;

  @override
  State<SourcePointsListScreen> createState() => _SourcePointsListScreenState();
}

class _SourcePointsListScreenState extends State<SourcePointsListScreen> {
  List<SourcePoint> _points = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final points = await widget.repository.getSourcePoints(widget.site.id);
    if (!mounted) return;
    setState(() {
      _points = points;
      _loading = false;
    });
  }

  Future<void> _addOrEdit([SourcePoint? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourcePointFormScreen(
          repository: widget.repository,
          site: widget.site,
          existing: existing,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete(SourcePoint sp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete source point?'),
        content: Text('"${_titleFor(sp)}" will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.repository.deleteSourcePoint(sp.id);
    await _load();
  }

  static String _titleFor(SourcePoint sp) {
    if (sp.apartment.trim().isNotEmpty) return sp.apartment.trim();
    if (sp.block != null && sp.block!.trim().isNotEmpty) return sp.block!;
    return 'Untitled source point';
  }

  static String _subtitleFor(SourcePoint sp) {
    final parts = <String>[
      if (sp.block != null && sp.block!.isNotEmpty) 'Block ${sp.block}',
      if (sp.sensorSize != null) sp.sensorSize!.label,
      if (sp.sensorType != null) sp.sensorType!.label,
    ];
    return parts.isEmpty ? 'No details yet' : parts.join('  •  ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Source points')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Add source point'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _points.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No source points yet.\nTap "Add source point" to create one.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _points.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final sp = _points[i];
                return ListTile(
                  leading: const Icon(Icons.water_drop_outlined),
                  title: Text(_titleFor(sp)),
                  subtitle: Text(_subtitleFor(sp)),
                  onTap: () => _addOrEdit(sp),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(sp),
                  ),
                );
              },
            ),
    );
  }
}
