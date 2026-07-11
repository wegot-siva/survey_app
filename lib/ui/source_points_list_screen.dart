import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.readOnly = false,
    this.isAdmin = false,
  });

  final SurveyRepository repository;
  final Site site;
  final bool readOnly;

  /// Threaded through to [SourcePointFormScreen] — see its doc for what
  /// this shows.
  final bool isAdmin;

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
          readOnly: widget.readOnly,
          isAdmin: widget.isAdmin,
        ),
      ),
    );
    await _load();
  }

  /// Opens the standard Add form pre-filled from [source] (identity fields
  /// and photos cleared — see [SourcePoint.copyAsDuplicate]), letting the
  /// user review/adjust before it saves as a brand-new record.
  Future<void> _duplicate(SourcePoint source) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourcePointFormScreen(
          repository: widget.repository,
          site: widget.site,
          duplicateFrom: source.copyAsDuplicate(),
          isAdmin: widget.isAdmin,
        ),
      ),
    );
    await _load();
  }

  /// Creates [count] independent copies of [source] directly (no per-record
  /// form review), each via the same [SurveyRepository.addSourcePoint] path
  /// used everywhere else — not a shared template, so editing one later
  /// never affects the others.
  Future<void> _duplicateMany(SourcePoint source) async {
    final count = await _promptForCount(context);
    if (count == null) return;

    for (var i = 0; i < count; i++) {
      await widget.repository.addSourcePoint(source.copyAsDuplicate());
    }
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
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
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
                  title: Row(
                    children: [
                      Flexible(child: Text(_titleFor(sp))),
                      if (sp.apartment.trim().isEmpty) ...[
                        const SizedBox(width: 8),
                        const _IncompleteBadge(),
                      ],
                    ],
                  ),
                  subtitle: Text(_subtitleFor(sp)),
                  onTap: () => _addOrEdit(sp),
                  trailing: widget.readOnly
                      ? null
                      : PopupMenuButton<_SourcePointAction>(
                          onSelected: (action) {
                            switch (action) {
                              case _SourcePointAction.duplicate:
                                _duplicate(sp);
                              case _SourcePointAction.duplicateMany:
                                _duplicateMany(sp);
                              case _SourcePointAction.delete:
                                _delete(sp);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _SourcePointAction.duplicate,
                              child: ListTile(
                                leading: Icon(Icons.copy_outlined),
                                title: Text('Duplicate'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _SourcePointAction.duplicateMany,
                              child: ListTile(
                                leading: Icon(Icons.library_add_outlined),
                                title: Text('Duplicate ×N'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _SourcePointAction.delete,
                              child: ListTile(
                                leading: Icon(Icons.delete_outline),
                                title: Text('Delete'),
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
    );
  }
}

enum _SourcePointAction { duplicate, duplicateMany, delete }

/// Small, visibly-distinct marker shown next to a point whose identity field
/// (apartment) is still blank — meant to be noticeable before the survey is
/// submitted, not just on close inspection.
class _IncompleteBadge extends StatelessWidget {
  const _IncompleteBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Incomplete',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

/// Prompts for a positive integer count (capped at 1000 as a sanity limit).
/// Returns null if cancelled or the input never validates.
Future<int?> _promptForCount(BuildContext context) {
  final controller = TextEditingController(text: '2');
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Duplicate ×N'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Number of copies'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(controller.text.trim());
            if (n == null || n < 1 || n > 1000) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Enter a number from 1 to 1000.'),
                ),
              );
              return;
            }
            Navigator.of(context).pop(n);
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
