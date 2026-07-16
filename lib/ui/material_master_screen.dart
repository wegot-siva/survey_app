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

  /// True once selection mode is entered (long-press a row, or the toolbar
  /// toggle) — rows show a checkbox and tapping selects instead of opening
  /// edit. Independent of [_searchOpen]: a search can stay applied while
  /// selecting, narrowing which rows are visible to select from.
  bool _selectionMode = false;

  /// Ids of the currently checked rows — persists across a search text
  /// change (a row scrolled out of the filtered view stays selected), and is
  /// always empty when [_selectionMode] is false.
  final Set<String> _selectedIds = {};

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

  /// Enters selection mode — via the toolbar toggle ([initialId] null) or a
  /// row long-press, which also pre-checks that row so the gesture itself
  /// counts as the first selection.
  void _enterSelectionMode([String? initialId]) {
    setState(() {
      _selectionMode = true;
      if (initialId != null) _selectedIds.add(initialId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  /// Tombstones exactly the checked rows via the same per-row
  /// [SurveyRepository.deleteMaterialMasterItem] the single-row delete uses
  /// — never a bulk/raw-SQL path — so each still gets its own audit entry
  /// and its own pending-delete/dirty flags for the next sync, same as
  /// today. Confirmation wording is deliberately distinct from [_clearAll]'s
  /// so the two can never be confused for each other.
  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList(growable: false);
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${ids.length} item${ids.length == 1 ? '' : 's'}?'),
        content: const Text(
          'The selected rows will be permanently removed.',
        ),
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

    for (final id in ids) {
      await widget.repository.deleteMaterialMasterItem(
        id,
        changedByRole: widget.changedByRole,
      );
    }
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    await _load();
  }

  /// Disaster-recovery action: tombstones every currently-active row (not
  /// just what's visible under the current search filter), still one
  /// [SurveyRepository.deleteMaterialMasterItem] call per row — same
  /// tombstone-then-sync path as every other delete here, never a raw
  /// DELETE/TRUNCATE. Kept behind its own confirmation dialog, entirely
  /// separate from [_deleteSelected]'s and from selection mode, so it can
  /// never fire from a selection-mode tap.
  Future<void> _clearAll() async {
    final ids = _items.map((i) => i.id).toList(growable: false);
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all Material Master items?'),
        content: Text(
          'This permanently removes all ${ids.length} active rows. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final id in ids) {
      await widget.repository.deleteMaterialMasterItem(
        id,
        changedByRole: widget.changedByRole,
      );
    }
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
        leading: _selectionMode
            ? IconButton(
                tooltip: 'Cancel selection',
                onPressed: _exitSelectionMode,
                icon: const Icon(Icons.close),
              )
            : null,
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : _searchOpen
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
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Material Master'),
                  Text(
                    '${_items.length} item${_items.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).appBarTheme.foregroundColor?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: 'Delete selected',
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                ),
              ]
            : _searchOpen
            ? [
                IconButton(
                  tooltip: 'Close search',
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.close),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Select items',
                  onPressed: _items.isEmpty ? null : () => _enterSelectionMode(),
                  icon: const Icon(Icons.checklist),
                ),
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
                PopupMenuButton<void>(
                  tooltip: 'More',
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      enabled: _items.isNotEmpty,
                      onTap: _clearAll,
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
              ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
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
                        leading: _selectionMode
                            ? Checkbox(
                                value: _selectedIds.contains(item.id),
                                onChanged: (_) => _toggleSelected(item.id),
                              )
                            : const Icon(Icons.inventory_2_outlined),
                        title: Text(
                          item.sku.isEmpty
                              ? item.materialName
                              : '${item.materialName}  (${item.sku})',
                        ),
                        subtitle: Text(
                          '${_variantLabel(item)}  •  ${_behaviorSummary(item)}',
                        ),
                        onTap: _selectionMode
                            ? () => _toggleSelected(item.id)
                            : () => _addOrEdit(item),
                        onLongPress: _selectionMode
                            ? null
                            : () => _enterSelectionMode(item.id),
                        trailing: _selectionMode
                            ? null
                            : IconButton(
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
