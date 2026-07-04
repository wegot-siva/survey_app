import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/bom_manual_entry.dart';
import 'bom_manual_entry_form_screen.dart';

/// Lists a survey's manually-added D/E/G BoM entries, with add/edit/delete.
/// Reachable only from the BoM preview screen — not per survey point — and
/// available for any survey regardless of status.
class BomManualEntriesScreen extends StatefulWidget {
  const BomManualEntriesScreen({
    super.key,
    required this.repository,
    required this.surveyId,
    required this.surveyName,
    required this.addedByRole,
  });

  final SurveyRepository repository;
  final String surveyId;
  final String surveyName;
  final String addedByRole;

  @override
  State<BomManualEntriesScreen> createState() =>
      _BomManualEntriesScreenState();
}

class _BomManualEntriesScreenState extends State<BomManualEntriesScreen> {
  List<BomManualEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await widget.repository.getBomManualEntries(
      widget.surveyId,
    );
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _addOrEdit([BomManualEntry? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomManualEntryFormScreen(
          repository: widget.repository,
          surveyId: widget.surveyId,
          addedByRole: widget.addedByRole,
          existing: existing,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete(BomManualEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('"${entry.materialName}" will be permanently removed.'),
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

    await widget.repository.deleteBomManualEntry(entry.id);
    await _load();
  }

  static String _formatQty(double q) {
    return q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add materials — ${widget.surveyName}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Add material'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No manually-added materials yet.\n\n'
                  'Use this to add extra D (Plumbing rework), E (Electrical), '
                  'or G (Labour) items the computed BoM doesn\'t cover.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final group in kBomManualEntryGroups)
                  if (_entries.any((e) => e.group == group)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        '${group.code} — ${group.label}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final entry in _entries.where((e) => e.group == group))
                      ListTile(
                        leading: const Icon(Icons.add_shopping_cart_outlined),
                        title: Text(
                          entry.sku.isEmpty
                              ? entry.materialName
                              : '${entry.materialName} (${entry.sku})',
                        ),
                        subtitle: Text(
                          '${_formatQty(entry.qty)} ${entry.unit}  •  '
                          'added by ${entry.addedBy}',
                        ),
                        onTap: () => _addOrEdit(entry),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(entry),
                        ),
                      ),
                    const Divider(height: 1),
                  ],
              ],
            ),
    );
  }
}
