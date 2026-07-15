import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/material_master_item.dart';
import 'material_master_audit_log_screen.dart';
import 'material_master_form_screen.dart';

/// Admin screen for the Material Master: add / edit / delete the per-sensor
/// material kits the BoM engine reads at generation time.
///
/// Gated behind the Admin role — the home screen only shows the entry point
/// to Admin, so this screen never opens for another role in practice, but
/// [changedByRole] is still an explicit parameter (not read from a session
/// singleton) so the screen stays testable without one.
class MaterialMasterScreen extends StatefulWidget {
  const MaterialMasterScreen({
    super.key,
    required this.repository,
    required this.changedByRole,
  });

  final SurveyRepository repository;

  /// Label of the signed-in role (e.g. "Admin"), recorded against every
  /// change-log entry this screen's mutations write.
  final String changedByRole;

  @override
  State<MaterialMasterScreen> createState() => _MaterialMasterScreenState();
}

class _MaterialMasterScreenState extends State<MaterialMasterScreen> {
  List<MaterialMasterItem> _items = const [];
  bool _loading = true;

  final _searchController = TextEditingController();

  /// Lowercased, trimmed live from [_searchController] — see [_filteredItems].
  String _query = '';

  /// Whether the AppBar search field is showing in place of the "Material
  /// Master" title — collapsed by default so it never takes up screen space
  /// until the user actually taps the search icon (see [_openSearch]), same
  /// convention as the Sites home screen.
  bool _searchOpen = false;

  /// [_items] (unchanged) narrowed by [_query], case-insensitive substring
  /// match on material name only. Filter only — never touches storage, sort
  /// order, or an individual row's own behavior (tap-to-edit, delete, etc.).
  List<MaterialMasterItem> get _filteredItems => _query.isEmpty
      ? _items
      : _items
            .where((i) => i.materialName.toLowerCase().contains(_query))
            .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await widget.repository.getMaterialMasterItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _addOrEdit([MaterialMasterItem? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MaterialMasterFormScreen(
          repository: widget.repository,
          changedByRole: widget.changedByRole,
          existing: existing,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openChangeLog() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MaterialMasterAuditLogScreen(repository: widget.repository),
      ),
    );
  }

  Future<void> _delete(MaterialMasterItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete material row?'),
        content: Text('"${item.materialName}" will be permanently removed.'),
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

    await widget.repository.deleteMaterialMasterItem(
      item.id,
      changedByRole: widget.changedByRole,
    );
    await _load();
  }

  static String _variantLabel(MaterialMasterItem item) {
    final parts = [
      item.sensorSize?.label,
      item.sensorType?.label,
    ].whereType<String>();
    return parts.isEmpty ? 'Any variant' : parts.join(' · ');
  }

  static String _behaviorSummary(MaterialMasterItem item) {
    switch (item.behaviorType) {
      case MaterialBehaviorType.fixed:
        return 'Fixed · ${item.quantityPerSensor} ${item.unit} per sensor';
      case MaterialBehaviorType.derived:
        final divisor = item.formulaDivisor;
        return divisor == null
            ? 'Derived · divisor not set (TBD)'
            : 'Derived · ${item.derivedFormula?.label ?? ''} (N=$divisor)';
      case MaterialBehaviorType.variable:
        return 'Variable · ${item.variableSource?.label ?? 'source not set'}';
    }
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
  }

  /// Closes the AppBar search field and clears whatever was typed, restoring
  /// the full list — collapsing back to the icon is also how the user
  /// "clears" the search, not just the field's own clear button.
  void _closeSearch() {
    _searchController.clear();
    setState(() => _searchOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(
                  color: Theme.of(context).appBarTheme.foregroundColor ??
                      Theme.of(context).colorScheme.onSurface,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search materials by name',
                  border: InputBorder.none,
                ),
              )
            : const Text('Material Master'),
        actions: _searchOpen
            ? [
                IconButton(
                  tooltip: 'Close search',
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.close),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Search materials',
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: 'Change log',
                  onPressed: _openChangeLog,
                  icon: const Icon(Icons.history),
                ),
              ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Add material'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No material rows yet.\n\n'
                  'The BoM engine reads every quantity from here — add a row '
                  'per sensor variant (and group) to start generating BoMs. '
                  'Unknown quantities can be left at 0 / TBD for now.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _filteredItems.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No materials match your search.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final group in MaterialGroup.values)
                  if (_filteredItems.any((i) => i.group == group)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        '${group.code} — ${group.label}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final item in _filteredItems.where((i) => i.group == group))
                      ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(
                          item.sku.isEmpty
                              ? item.materialName
                              : '${item.materialName}  (${item.sku})',
                        ),
                        subtitle: Text(
                          '${_variantLabel(item)}  •  ${_behaviorSummary(item)}',
                        ),
                        onTap: () => _addOrEdit(item),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(item),
                        ),
                      ),
                    const Divider(height: 1),
                  ],
              ],
            ),
    );
  }
}
