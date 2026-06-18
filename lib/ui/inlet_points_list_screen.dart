import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/inlet_point.dart';
import '../models/site.dart';
import 'inlet_point_form_screen.dart';

/// Lists a site's inlet points with add / edit / delete.
class InletPointsListScreen extends StatefulWidget {
  const InletPointsListScreen({
    super.key,
    required this.repository,
    required this.site,
  });

  final SurveyRepository repository;
  final Site site;

  @override
  State<InletPointsListScreen> createState() => _InletPointsListScreenState();
}

class _InletPointsListScreenState extends State<InletPointsListScreen> {
  List<InletPoint> _points = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final points = await widget.repository.getInletPoints(widget.site.id);
    if (!mounted) return;
    setState(() {
      _points = points;
      _loading = false;
    });
  }

  Future<void> _addOrEdit([InletPoint? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InletPointFormScreen(
          repository: widget.repository,
          site: widget.site,
          existing: existing,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete(InletPoint ip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete inlet point?'),
        content: Text('"${_titleFor(ip)}" will be permanently removed.'),
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

    await widget.repository.deleteInletPoint(ip.id);
    await _load();
  }

  static String _titleFor(InletPoint ip) {
    if (ip.apartmentBhk.trim().isNotEmpty) return ip.apartmentBhk.trim();
    if (ip.block != null && ip.block!.trim().isNotEmpty) return ip.block!;
    return 'Untitled inlet point';
  }

  static String _subtitleFor(InletPoint ip) {
    final parts = <String>[
      if (ip.block != null && ip.block!.isNotEmpty) 'Block ${ip.block}',
      if (ip.series.isNotEmpty) 'Series ${ip.series}',
      if (ip.sensorSize != null) ip.sensorSize!.label,
      if (ip.sensorType != null) ip.sensorType!.label,
    ];
    return parts.isEmpty ? 'No details yet' : parts.join('  •  ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inlet points')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Add inlet point'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _points.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No inlet points yet.\nTap "Add inlet point" to create one.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _points.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final ip = _points[i];
                return ListTile(
                  leading: const Icon(Icons.input_outlined),
                  title: Text(_titleFor(ip)),
                  subtitle: Text(_subtitleFor(ip)),
                  onTap: () => _addOrEdit(ip),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(ip),
                  ),
                );
              },
            ),
    );
  }
}
