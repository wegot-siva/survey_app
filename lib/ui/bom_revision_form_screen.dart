import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/bom_revision_line.dart';
import 'bom_revision_line_form_screen.dart';
import 'widgets/form_fields.dart';

/// "Add revision" flow for a locked survey: a required reason, plus one or
/// more delta lines built up locally (via [BomRevisionLineFormScreen]) before
/// a single [SurveyRepository.addBomRevision] call persists the whole
/// revision — reason and lines together, atomically.
class BomRevisionFormScreen extends StatefulWidget {
  const BomRevisionFormScreen({
    super.key,
    required this.repository,
    required this.surveyId,
    required this.surveyName,
    required this.createdByRole,
    this.createdByUserId,
  });

  final SurveyRepository repository;
  final String surveyId;
  final String surveyName;

  /// Display-name snapshot of the signed-in user (or a bare role label as a
  /// fallback), recorded as `createdBy`.
  final String createdByRole;

  /// The signed-in user's real account id, recorded as `createdByUserId` —
  /// see Roles & Assignment Slice 1d.
  final String? createdByUserId;

  @override
  State<BomRevisionFormScreen> createState() => _BomRevisionFormScreenState();
}

class _BomRevisionFormScreenState extends State<BomRevisionFormScreen> {
  final _reason = TextEditingController();
  final List<BomRevisionLine> _lines = [];
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _addLine() async {
    final line = await Navigator.of(context).push(
      MaterialPageRoute<BomRevisionLine>(
        builder: (_) => BomRevisionLineFormScreen(repository: widget.repository),
      ),
    );
    if (line == null) return;
    setState(() => _lines.add(line));
  }

  void _removeLine(int index) {
    setState(() => _lines.removeAt(index));
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a reason for this revision.')),
      );
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one line.')),
      );
      return;
    }

    setState(() => _saving = true);
    await widget.repository.addBomRevision(
      surveyId: widget.surveyId,
      reason: _reason.text.trim(),
      lines: _lines,
      createdBy: widget.createdByRole,
      createdByUserId: widget.createdByUserId,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Revision saved.')),
    );
    Navigator.of(context).pop();
  }

  static String _formatQtyDelta(double q) {
    final rounded = q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
    return q > 0 ? '+$rounded' : rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add revision — ${widget.surveyName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppTextField(
            controller: _reason,
            label: 'Reason (required)',
            maxLines: 2,
          ),
          const FormSectionLabel('Lines'),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No lines added yet.'),
            )
          else
            for (var i = 0; i < _lines.length; i++)
              Card(
                child: ListTile(
                  title: Text(_lines[i].item),
                  subtitle: Text(
                    '${_lines[i].group.code} — ${_lines[i].group.label}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_formatQtyDelta(_lines[i].qtyDelta)} ${_lines[i].unit}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeLine(i),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addLine,
            icon: const Icon(Icons.add),
            label: const Text('Add line'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save revision'),
          ),
        ],
      ),
    );
  }
}
