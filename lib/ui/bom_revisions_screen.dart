import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/bom_manual_edit_snapshot.dart';
import '../models/bom_revision.dart';
import '../models/bom_snapshot.dart';
import 'bom_revision_form_screen.dart';
import 'bom_version_detail_screen.dart';

/// Version history for a locked survey's BoM: v1 (the frozen snapshot) plus
/// every revision and manual edit (v2, v3, ...), each viewable, and an "Add
/// revision" action that layers a new additive delta on top. Revisions and
/// manual edits share one version counter (see
/// SurveyRepository.addBomRevision), so listing them interleaved in version
/// order reflects the real order they were made in.
class BomRevisionsScreen extends StatefulWidget {
  const BomRevisionsScreen({
    super.key,
    required this.repository,
    required this.surveyId,
    required this.surveyName,
    required this.createdByRole,
  });

  final SurveyRepository repository;
  final String surveyId;
  final String surveyName;
  final String createdByRole;

  @override
  State<BomRevisionsScreen> createState() => _BomRevisionsScreenState();
}

class _BomRevisionsScreenState extends State<BomRevisionsScreen> {
  BomSnapshot? _snapshot;
  List<BomRevision> _revisions = const [];
  List<BomManualEditSnapshot> _manualEditSnapshots = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final snapshot = await widget.repository.getBomSnapshot(widget.surveyId);
    final revisions = await widget.repository.getBomRevisions(widget.surveyId);
    final manualEdits = await widget.repository.getBomManualEditSnapshots(
      widget.surveyId,
    );
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _revisions = revisions;
      _manualEditSnapshots = manualEdits;
      _loading = false;
    });
  }

  Future<void> _viewSnapshot(BomSnapshot snapshot) async {
    final lines = await widget.repository.getBomSnapshotLines(snapshot.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomVersionDetailScreen(
          title: 'v1 — Frozen',
          subtitle: 'Finalized by ${snapshot.finalizedBy} on '
              '${_formatDate(snapshot.finalizedAt)}',
          lines: [
            for (final l in lines)
              (
                item: l.item,
                sku: l.sku,
                unit: l.unit,
                qty: l.qty,
                group: l.group,
                isDelta: false,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewRevision(BomRevision revision) async {
    final lines = await widget.repository.getBomRevisionLines(revision.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomVersionDetailScreen(
          title: 'v${revision.version} — ${revision.reason}',
          subtitle: 'Added by ${revision.createdBy} on '
              '${_formatDate(revision.createdAt)}',
          lines: [
            for (final l in lines)
              (
                item: l.item,
                sku: l.sku,
                unit: l.unit,
                qty: l.qtyDelta,
                group: l.group,
                isDelta: true,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewManualEditSnapshot(BomManualEditSnapshot snapshot) async {
    final lines = await widget.repository.getBomManualEditSnapshotLines(
      snapshot.id,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomVersionDetailScreen(
          title: 'v${snapshot.version} — ${snapshot.reason}',
          subtitle: 'Edited by ${snapshot.editedBy} on '
              '${_formatDate(snapshot.editedAt)}',
          lines: [
            for (final l in lines)
              (
                item: l.itemName,
                sku: l.sku,
                unit: l.unit,
                qty: l.qty,
                group: l.group,
                isDelta: false,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRevision() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomRevisionFormScreen(
          repository: widget.repository,
          surveyId: widget.surveyId,
          surveyName: widget.surveyName,
          createdByRole: widget.createdByRole,
        ),
      ),
    );
    await _load();
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: Text('Version history — ${widget.surveyName}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRevision,
        icon: const Icon(Icons.add),
        label: const Text('Add revision'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : snapshot == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This survey has not been finalized yet.'),
              ),
            )
          : ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('v1 — Frozen'),
                  subtitle: Text(
                    'Finalized by ${snapshot.finalizedBy} on '
                    '${_formatDate(snapshot.finalizedAt)}',
                  ),
                  onTap: () => _viewSnapshot(snapshot),
                ),
                for (final entry in _laterVersionsInOrder()) entry,
              ],
            ),
    );
  }

  /// Every version after v1 (revisions and manual edits), interleaved in
  /// version order — both share one counter, so this reflects the real
  /// order they were made in, not "all revisions then all manual edits".
  List<Widget> _laterVersionsInOrder() {
    final entries = <(int version, Widget tile)>[
      for (final revision in _revisions)
        (
          revision.version,
          ListTile(
            leading: const Icon(Icons.difference_outlined),
            title: Text('v${revision.version} — ${revision.reason}'),
            subtitle: Text(
              'Added by ${revision.createdBy} on '
              '${_formatDate(revision.createdAt)}',
            ),
            onTap: () => _viewRevision(revision),
          ),
        ),
      for (final edit in _manualEditSnapshots)
        (
          edit.version,
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: Text('v${edit.version} — ${edit.reason}'),
            subtitle: Text(
              'Edited by ${edit.editedBy} on ${_formatDate(edit.editedAt)}',
            ),
            onTap: () => _viewManualEditSnapshot(edit),
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final entry in entries) entry.$2];
  }
}
