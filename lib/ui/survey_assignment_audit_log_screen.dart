import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/survey_assignment_audit_entry.dart';

/// Read-only reassignment history for one survey — reached from the Sales
/// survey screen (Site Hub).
class SurveyAssignmentAuditLogScreen extends StatefulWidget {
  const SurveyAssignmentAuditLogScreen({
    super.key,
    required this.repository,
    required this.siteId,
    required this.siteName,
  });

  final SurveyRepository repository;
  final String siteId;
  final String siteName;

  @override
  State<SurveyAssignmentAuditLogScreen> createState() =>
      _SurveyAssignmentAuditLogScreenState();
}

class _SurveyAssignmentAuditLogScreenState
    extends State<SurveyAssignmentAuditLogScreen> {
  List<SurveyAssignmentAuditEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await widget.repository.getSurveyAssignmentAuditLog(
      widget.siteId,
    );
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  static String _formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reassignment history — ${widget.siteName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No reassignments recorded yet.\n\n'
                  'Every time this survey is reassigned to a different '
                  'engineer, it will be logged here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = _entries[i];
                return ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text('${e.oldAssignee ?? '—'}  →  ${e.newAssignee}'),
                  subtitle: Text(
                    '${e.changedByRole} · ${_formatTimestamp(e.changedAt)}',
                  ),
                );
              },
            ),
    );
  }
}
