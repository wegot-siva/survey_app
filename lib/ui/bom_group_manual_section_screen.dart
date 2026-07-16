import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/bom_line.dart';
import '../models/bom_manual_entry.dart';
import '../models/material_master_item.dart';
import 'bom_manual_entry_form_screen.dart';

/// One group's (B, C, D, E, F, or G) BoM section: any auto-computed lines for
/// that group (read-only — most Material Master rows in these groups are
/// manual-only, but D/E/G can still carry a real fixed/derived/variable row
/// same as A, so this isn't assumed empty), plus that group's manually-
/// added entries, with add/edit/delete. Replaces the old cross-group
/// `BomManualEntriesScreen` — reachable only from within its own BoM
/// section, so the target group is already implied by [group] and the
/// engineer never re-selects it (see [BomManualEntryFormScreen.lockedGroup]).
class BomGroupManualSectionScreen extends StatefulWidget {
  const BomGroupManualSectionScreen({
    super.key,
    required this.repository,
    required this.surveyId,
    required this.surveyName,
    required this.addedByRole,
    required this.group,
    this.autoLines = const [],
    this.readOnly = false,
  });

  final SurveyRepository repository;
  final String surveyId;
  final String surveyName;
  final String addedByRole;
  final MaterialGroup group;

  /// This group's auto-computed lines (if any) from the same BomEngine
  /// output the overview screen already computed — shown read-only above
  /// the manual entries, never re-computed here.
  final List<BomLine> autoLines;

  /// When true, hides "Add material" and disables tap-to-edit/delete —
  /// mirrors [BomPreviewScreen.readOnly].
  final bool readOnly;

  @override
  State<BomGroupManualSectionScreen> createState() =>
      _BomGroupManualSectionScreenState();
}

class _BomGroupManualSectionScreenState
    extends State<BomGroupManualSectionScreen> {
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
      _entries = entries.where((e) => e.group == widget.group).toList();
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
          lockedGroup: widget.group,
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
    final scheme = Theme.of(context).colorScheme;
    final autoLines = widget.autoLines.where((l) => l.quantity > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.group.code} — ${widget.group.label}'),
      ),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Add material'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (autoLines.isEmpty && _entries.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No ${widget.group.label} items yet.'
                  '${widget.readOnly ? '' : '\n\nTap "Add material" to add one.'}',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (autoLines.isNotEmpty) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          color: scheme.secondaryContainer,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Text(
                            'Auto-computed',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        for (final line in autoLines)
                          ListTile(
                            dense: true,
                            title: Text(line.materialName),
                            subtitle: Text(line.variantLabel),
                            trailing: Text(
                              '${_formatQty(line.quantity)} ${line.unit}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final entry in _entries)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(entry.materialName),
                      subtitle: Text(
                        '${_formatQty(entry.qty)} ${entry.unit}  •  '
                        'added by ${entry.addedBy}',
                      ),
                      onTap: widget.readOnly ? null : () => _addOrEdit(entry),
                      trailing: widget.readOnly
                          ? null
                          : IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(entry),
                            ),
                    ),
                  ),
              ],
            ),
    );
  }
}
