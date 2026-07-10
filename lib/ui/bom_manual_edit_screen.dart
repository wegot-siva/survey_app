import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/bom_manual_edit_snapshot_line.dart';
import '../models/material_master_item.dart';
import '../services/bom_revision_engine.dart';
import 'widgets/form_fields.dart';

/// One line's current (possibly hand-edited) values, held as plain mutable
/// fields rather than live [TextEditingController]s — the compact list only
/// ever needs to *read* these to render a `Text` row; controllers are only
/// created transiently, one row at a time, by [_EditLineSheet] while its
/// modal is open. At 100-300+ rows this is the difference between a handful
/// of live controllers and hundreds sitting in memory for the whole session.
class _LineDraft {
  _LineDraft(this.original)
    : sku = original.sku,
      itemName = original.item,
      description = original.description,
      unit = original.unit,
      qty = original.rawQty;

  final BomRunningTotalLine original;
  String sku;
  String itemName;
  String description;
  String unit;
  double qty;

  MaterialGroup get group => original.group;

  /// True once any field differs from the value this line started the
  /// session with — drives the compact list's "edited" badge. Reverting a
  /// field back to its original value un-flags the row, which is the
  /// correct read of "touched" for a save that bundles every line's
  /// *current* value regardless.
  bool get edited =>
      sku != original.sku ||
      itemName != original.item ||
      description != original.description ||
      unit != original.unit ||
      qty != original.rawQty;
}

/// Admin/Approver "Edit BoM": a compact, searchable list of a survey's
/// current (latest) resolved version. Tapping a row opens a modal with that
/// line's full editable form (SKU, item name, description, unit, qty);
/// saving the modal only stages the edit in local UI state (see
/// [_LineDraft]) and shows an "edited" marker on the row — it does NOT touch
/// storage. The screen-level "Save as new version" action is the only place
/// that calls [SurveyRepository.addBomManualEditSnapshot], bundling every
/// line's current value (touched and untouched alike) into one new,
/// immutable version. No existing snapshot/revision/manual-edit row is ever
/// modified.
class BomManualEditScreen extends StatefulWidget {
  const BomManualEditScreen({
    super.key,
    required this.repository,
    required this.surveyId,
    required this.surveyName,
    required this.basedOnVersion,
    required this.currentLines,
    required this.editedByRole,
  });

  final SurveyRepository repository;
  final String surveyId;
  final String surveyName;

  /// The version this edit's starting line list was resolved from — passed
  /// straight through to [SurveyRepository.addBomManualEditSnapshot].
  final int basedOnVersion;

  final List<BomRunningTotalLine> currentLines;

  /// Label of the signed-in role (e.g. "Approver"), recorded as `editedBy`.
  final String editedByRole;

  @override
  State<BomManualEditScreen> createState() => _BomManualEditScreenState();
}

class _BomManualEditScreenState extends State<BomManualEditScreen> {
  late final List<_LineDraft> _lines;
  final _search = TextEditingController();
  String _query = '';
  bool _saving = false;

  /// Set once a save has actually gone through — lets the PopScope guard
  /// below tell "just saved, about to pop" apart from "has real unsaved
  /// edits", without needing to reset every _LineDraft's baseline.
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _lines = [for (final line in widget.currentLines) _LineDraft(line)];
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _hasUnsavedEdits => _lines.any((l) => l.edited);

  List<_LineDraft> _matching(MaterialGroup group) {
    final inGroup = _lines.where((l) => l.group == group);
    if (_query.isEmpty) return inGroup.toList(growable: false);
    return inGroup
        .where(
          (l) =>
              l.itemName.toLowerCase().contains(_query) ||
              l.sku.toLowerCase().contains(_query) ||
              group.code.toLowerCase() == _query ||
              group.label.toLowerCase().contains(_query),
        )
        .toList(growable: false);
  }

  Future<void> _editLine(_LineDraft draft) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditLineSheet(draft: draft),
    );
    if (saved == true) setState(() {});
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved edits staged for this BoM. Leaving now discards '
          'them — nothing has been saved yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _saveAsNewVersion() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(),
    );
    if (reason == null || !mounted) return;

    setState(() => _saving = true);
    final lines = [
      for (final line in _lines)
        BomManualEditSnapshotLine(
          id: '',
          snapshotId: '',
          sku: line.sku.trim(),
          itemName: line.itemName.trim(),
          description: line.description.trim(),
          unit: line.unit.trim(),
          qty: line.qty,
          group: line.group,
        ),
    ];

    await widget.repository.addBomManualEditSnapshot(
      surveyId: widget.surveyId,
      basedOnVersion: widget.basedOnVersion,
      reason: reason,
      lines: lines,
      editedBy: widget.editedByRole,
    );

    if (!mounted) return;
    _saved = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('BoM edit saved as a new version.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editedCount = _lines.where((l) => l.edited).length;

    return PopScope(
      canPop: !_hasUnsavedEdits || _saved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final discard = await _confirmDiscard();
        if (discard && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Edit BoM — ${widget.surveyName}'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search by item name, SKU, or group (A-G)',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => _search.clear(),
                        ),
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: (_saving || !_hasUnsavedEdits) ? null : _saveAsNewVersion,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(
            editedCount == 0
                ? 'Save as new version'
                : 'Save as new version ($editedCount edited)',
          ),
        ),
        body: _buildList(),
      ),
    );
  }

  Widget _buildList() {
    final rows = <Widget>[];
    for (final group in MaterialGroup.values) {
      final matches = _matching(group);
      if (matches.isEmpty) continue;
      rows.add(_GroupHeader(group: group));
      for (final line in matches) {
        rows.add(_LineTile(line: line, onTap: () => _editLine(line)));
      }
    }

    if (rows.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No lines.' : 'No lines match "$_query".',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final MaterialGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '${group.code} — ${group.label}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// One compact, read-only row: item name, qty + unit, and an "edited" badge
/// when this line has been touched this session. No editable fields live
/// here — tapping opens [_EditLineSheet].
class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onTap});

  final _LineDraft line;
  final VoidCallback onTap;

  static String _formatQty(double q) {
    return q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      title: Text(line.itemName.isEmpty ? '(unnamed)' : line.itemName),
      subtitle: line.sku.isEmpty ? null : Text(line.sku),
      leading: line.edited
          ? Tooltip(
              message: 'Edited this session',
              child: Icon(
                Icons.edit,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            )
          : const SizedBox(width: 20),
      trailing: Text(
        '${_formatQty(line.qty)} ${line.unit}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Full editable form for one line, shown as a modal bottom sheet. Owns its
/// own short-lived controllers, pre-filled from [draft]'s *current* values
/// (so re-opening an already-edited row shows the staged edit, not the
/// original) — saving writes straight back into the shared [draft] instance
/// and pops `true`; cancelling leaves [draft] untouched.
class _EditLineSheet extends StatefulWidget {
  const _EditLineSheet({required this.draft});

  final _LineDraft draft;

  @override
  State<_EditLineSheet> createState() => _EditLineSheetState();
}

class _EditLineSheetState extends State<_EditLineSheet> {
  late final TextEditingController _sku;
  late final TextEditingController _itemName;
  late final TextEditingController _description;
  late final TextEditingController _unit;
  late final TextEditingController _qty;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _sku = TextEditingController(text: d.sku);
    _itemName = TextEditingController(text: d.itemName);
    _description = TextEditingController(text: d.description);
    _unit = TextEditingController(text: d.unit);
    _qty = TextEditingController(
      text: d.qty == d.qty.roundToDouble()
          ? d.qty.toInt().toString()
          : d.qty.toString(),
    );
  }

  @override
  void dispose() {
    _sku.dispose();
    _itemName.dispose();
    _description.dispose();
    _unit.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _save() {
    final draft = widget.draft;
    draft.sku = _sku.text.trim();
    draft.itemName = _itemName.text.trim();
    draft.description = _description.text.trim();
    draft.unit = _unit.text.trim();
    draft.qty = double.tryParse(_qty.text.trim()) ?? draft.qty;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '${widget.draft.group.code} — ${widget.draft.group.label}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            AppTextField(controller: _itemName, label: 'Item name'),
            AppTextField(controller: _sku, label: 'SKU'),
            AppTextField(
              controller: _description,
              label: 'Description (optional)',
              maxLines: 2,
            ),
            Row(
              children: [
                Expanded(
                  child: AppTextField(controller: _unit, label: 'Unit'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppTextField(
                    controller: _qty,
                    label: 'Qty',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^-?\d*\.?\d*$'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save as new version'),
      content: AppTextField(
        controller: _reason,
        label: 'Reason for this edit (required)',
        maxLines: 2,
        errorText: _error,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final text = _reason.text.trim();
            if (text.isEmpty) {
              setState(() => _error = 'Required');
              return;
            }
            Navigator.of(context).pop(text);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
