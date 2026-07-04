import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/bom_revision.dart';
import '../models/bom_snapshot.dart';
import 'bom_revision_form_screen.dart';
import 'bom_version_detail_screen.dart';

/// Version history for a locked survey's BoM: v1 (the frozen snapshot) plus
/// every revision (v2, v3, ...), each viewable, and an "Add revision" action
/// that layers a new additive delta on top.
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
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _revisions = revisions;
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
                for (final revision in _revisions)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text('v${revision.version} — ${revision.reason}'),
                    subtitle: Text(
                      'Added by ${revision.createdBy} on '
                      '${_formatDate(revision.createdAt)}',
                    ),
                    onTap: () => _viewRevision(revision),
                  ),
              ],
            ),
    );
  }
}
