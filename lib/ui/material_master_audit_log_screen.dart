import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/material_master_audit_entry.dart';

/// Read-only Material Master change log (Admin only — reached from within
/// the Material Master screen, which is itself gated to Admin).
class MaterialMasterAuditLogScreen extends StatefulWidget {
  const MaterialMasterAuditLogScreen({super.key, required this.repository});

  final SurveyRepository repository;

  @override
  State<MaterialMasterAuditLogScreen> createState() =>
      _MaterialMasterAuditLogScreenState();
}

class _MaterialMasterAuditLogScreenState
    extends State<MaterialMasterAuditLogScreen> {
  List<MaterialMasterAuditEntry> _entries = const [];

  /// Best-effort id -> current material name, so entries read naturally even
  /// though the audit table only stores the row id. A deleted row's own
  /// entries fall back to its id, since [_summary] already carries its name.
  Map<String, String> _namesById = const {};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await widget.repository.getMaterialMasterAuditLog();
    final items = await widget.repository.getMaterialMasterItems();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _namesById = {for (final i in items) i.id: i.materialName};
      _loading = false;
    });
  }

  static String _eventLabel(MaterialMasterAuditEntry e) {
    switch (e.fieldChanged) {
      case '(created)':
        return 'Created';
      case '(deleted)':
        return 'Deleted';
      default:
        return '${e.fieldChanged} changed';
    }
  }

  static String _valueLine(MaterialMasterAuditEntry e) {
    switch (e.fieldChanged) {
      case '(created)':
        return e.newValue ?? '';
      case '(deleted)':
        return e.oldValue ?? '';
      default:
        return '${e.oldValue ?? '—'}  →  ${e.newValue ?? '—'}';
    }
  }

  static String _formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Material Master change log')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No changes recorded yet.\n\n'
                  'Every add, edit, and delete in Material Master is logged '
                  'here once it happens.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = _entries[i];
                final materialName =
                    _namesById[e.materialRowId] ?? '(deleted item)';
                return ListTile(
                  leading: Icon(
                    switch (e.fieldChanged) {
                      '(created)' => Icons.add_circle_outline,
                      '(deleted)' => Icons.remove_circle_outline,
                      _ => Icons.edit_outlined,
                    },
                  ),
                  title: Text('$materialName — ${_eventLabel(e)}'),
                  subtitle: Text(
                    '${_valueLine(e)}\n'
                    '${e.changedByRole} · ${_formatTimestamp(e.changedAt)}',
                  ),
                  isThreeLine: true,
                );
              },
            ),
    );
  }
}
