import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.readOnly = false,
  });

  final SurveyRepository repository;
  final Site site;
  final bool readOnly;

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
          readOnly: widget.readOnly,
        ),
      ),
    );
    await _load();
  }

  /// Opens the standard Add form pre-filled from [source] (identity field
  /// and photos cleared — see [InletPoint.copyAsDuplicate]), letting the
  /// user review/adjust before it saves as a brand-new record.
  Future<void> _duplicate(InletPoint source) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InletPointFormScreen(
          repository: widget.repository,
          site: widget.site,
          duplicateFrom: source.copyAsDuplicate(),
        ),
      ),
    );
    await _load();
  }

  /// Creates [count] independent copies of [source] directly (no per-record
  /// form review), each via the same [SurveyRepository.addInletPoint] path
  /// used everywhere else — not a shared template, so editing one later
  /// never affects the others.
  Future<void> _duplicateMany(InletPoint source) async {
    final count = await _promptForCount(context);
    if (count == null) return;

    for (var i = 0; i < count; i++) {
      await widget.repository.addInletPoint(source.copyAsDuplicate());
    }
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
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
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
                  title: Row(
                    children: [
                      Flexible(child: Text(_titleFor(ip))),
                      if (ip.apartmentBhk.trim().isEmpty) ...[
                        const SizedBox(width: 8),
                        const _IncompleteBadge(),
                      ],
                    ],
                  ),
                  subtitle: Text(_subtitleFor(ip)),
                  onTap: () => _addOrEdit(ip),
                  trailing: widget.readOnly
                      ? null
                      : PopupMenuButton<_InletPointAction>(
                          onSelected: (action) {
                            switch (action) {
                              case _InletPointAction.duplicate:
                                _duplicate(ip);
                              case _InletPointAction.duplicateMany:
                                _duplicateMany(ip);
                              case _InletPointAction.delete:
                                _delete(ip);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _InletPointAction.duplicate,
                              child: ListTile(
                                leading: Icon(Icons.copy_outlined),
                                title: Text('Duplicate'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _InletPointAction.duplicateMany,
                              child: ListTile(
                                leading: Icon(Icons.library_add_outlined),
                                title: Text('Duplicate ×N'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _InletPointAction.delete,
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

enum _InletPointAction { duplicate, duplicateMany, delete }

/// Small, visibly-distinct marker shown next to a point whose identity field
/// (apartment BHK) is still blank — meant to be noticeable before the survey
/// is submitted, not just on close inspection.
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
