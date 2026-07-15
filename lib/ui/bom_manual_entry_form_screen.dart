import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/bom_manual_entry.dart';
import '../models/material_master_item.dart';
import '../models/survey_options.dart';
import 'widgets/form_fields.dart';

/// The reusable "Add materials" picker: opened from within one BoM section
/// (C, D, E, F, or G — see [lockedGroup]), pick a Material Master catalog
/// row (its name/SKU/unit come along for the ride), and enter a quantity.
/// Add or edit a single [BomManualEntry].
///
/// Groups C and D always show a 4-level cascading selector (Material Type ->
/// Category -> Variant -> Size) driven by the plumbing catalog's finer
/// structure ([MaterialMasterItem.materialType]/[category]/[variant]/
/// [sizeMm]/[sizeDisplay]) — see [_cascadeModeActive]. Unconditional: C/D
/// never fall back to a flat dropdown, even if the catalog currently has no
/// material_type-tagged rows (the Material Type level just shows an empty
/// hint in that case). Every other group (E/F/G) uses the flat dropdown.
///
/// Mechanics only — this entry is not linked back to the catalog row's id, so
/// it survives that row being edited or removed later, and it is never read
/// by the BoM engine in this slice.
class BomManualEntryFormScreen extends StatefulWidget {
  const BomManualEntryFormScreen({
    super.key,
    required this.repository,
    required this.surveyId,
    required this.addedByRole,
    this.existing,
    this.lockedGroup,
  });

  final SurveyRepository repository;
  final String surveyId;

  /// Label of the signed-in role (e.g. "Engineer"), recorded as `addedBy` for
  /// a freshly-created entry. Ignored when editing (the original `addedBy` /
  /// `addedAt` are preserved — see [BomManualEntry]).
  final String addedByRole;

  final BomManualEntry? existing;

  /// When set, the target group is fixed to this value and the Group field
  /// becomes a read-only label instead of an interactive dropdown — used
  /// when this screen is opened from within one BoM section
  /// (BomGroupManualSectionScreen), where the group is already implied by
  /// which section the engineer navigated into, whether adding or editing.
  final MaterialGroup? lockedGroup;

  @override
  State<BomManualEntryFormScreen> createState() =>
      _BomManualEntryFormScreenState();
}

class _BomManualEntryFormScreenState extends State<BomManualEntryFormScreen> {
  late final TextEditingController _qty;

  List<MaterialMasterItem> _catalog = const [];
  bool _loadingCatalog = true;

  /// The catalog row picked (flat dropdown or resolved cascade leaf), if
  /// any — only used to update [_materialName]/[_sku]/[_unit] when a
  /// selection is (re)made. Starts null even when editing (an entry isn't
  /// linked back to a catalog row by id); the copied fields below already
  /// carry the existing values in that case.
  MaterialMasterItem? _selectedMaterial;

  String _materialName = '';
  String _sku = '';
  String _itemLabel = '';
  SensorSize? _sensorSize;
  SensorType? _sensorType;
  String _unit = '';
  MaterialGroup? _group;

  // Cascade-only selections (group C with material_type-populated rows).
  // Each level resets everything below it when changed.
  String? _cascadeMaterialType;
  String? _cascadeCategory;
  String? _cascadeVariant;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _qty = TextEditingController(text: e?.qty.toString() ?? '');
    _materialName = e?.materialName ?? '';
    _sku = e?.sku ?? '';
    _itemLabel = e?.itemLabel ?? '';
    _sensorSize = e?.sensorSize;
    _sensorType = e?.sensorType;
    _unit = e?.unit ?? '';
    _group = e?.group ?? widget.lockedGroup;
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final items = await widget.repository.getMaterialMasterItems();
    if (!mounted) return;
    setState(() {
      _catalog = items
          .where((item) => kBomManualEntryGroups.contains(item.group))
          .toList();
      _loadingCatalog = false;
    });
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  /// True when the target group should show the 4-level cascade instead of
  /// the flat dropdown — unconditionally for C (Plumbing accessories) and D
  /// (Plumbing rework — reworks draw from the same plumbing catalog), never
  /// for any other group. Not gated on whether the catalog currently has any
  /// material_type-tagged rows: C/D must always show the cascade, even on an
  /// empty catalog (see the Material Type dropdown's emptyHint in
  /// [_buildCascadeFields] for that case) — a flat dropdown must never
  /// appear for these two groups under any data condition. The cascade under
  /// D reads the exact same material_type-tagged rows as C — those rows'
  /// own `group` stays C; only the entry being saved gets D (see [_save],
  /// unchanged).
  bool get _cascadeModeActive =>
      _group == MaterialGroup.c || _group == MaterialGroup.d;

  void _onGroupChanged(MaterialGroup? newGroup) {
    final wasCascade = _cascadeModeActive;
    setState(() => _group = newGroup);
    if (_cascadeModeActive != wasCascade) {
      // Switching between flat and cascade mode leaves the other mode's
      // selection meaningless — clear it so the summary card can't show a
      // material the currently-visible selector didn't pick.
      _clearMaterialSelection();
    }
  }

  void _clearMaterialSelection() {
    setState(() {
      _selectedMaterial = null;
      _materialName = '';
      _sku = '';
      _itemLabel = '';
      _sensorSize = null;
      _sensorType = null;
      _unit = '';
      _cascadeMaterialType = null;
      _cascadeCategory = null;
      _cascadeVariant = null;
    });
  }

  void _onMaterialSelected(MaterialMasterItem? item) {
    setState(() => _applySelectedMaterial(item));
  }

  /// Same field assignment as [_onMaterialSelected], without wrapping its own
  /// `setState` — for cascade `onChanged` handlers that need to clear the
  /// resolved material as part of a single setState alongside a level change.
  void _applySelectedMaterial(MaterialMasterItem? item) {
    _selectedMaterial = item;
    if (item == null) {
      _materialName = '';
      _sku = '';
      _itemLabel = '';
      _sensorSize = null;
      _sensorType = null;
      _unit = '';
    } else {
      _materialName = item.materialName;
      _sku = item.sku;
      _itemLabel = item.itemLabel;
      _sensorSize = item.sensorSize;
      _sensorType = item.sensorType;
      _unit = item.unit;
    }
  }

  List<String> _distinct(Iterable<String?> values) {
    final seen = <String>{};
    for (final v in values) {
      if (v != null && v.isNotEmpty) seen.add(v);
    }
    final list = seen.toList()..sort();
    return list;
  }

  List<String> get _cascadeMaterialTypes =>
      _distinct(_catalog.map((m) => m.materialType));

  List<String> get _cascadeCategories {
    final materialType = _cascadeMaterialType;
    if (materialType == null) return const [];
    return _distinct(
      _catalog
          .where((m) => m.materialType == materialType)
          .map((m) => m.category),
    );
  }

  List<String> get _cascadeVariants {
    final materialType = _cascadeMaterialType;
    final category = _cascadeCategory;
    if (materialType == null || category == null) return const [];
    return _distinct(
      _catalog
          .where((m) => m.materialType == materialType && m.category == category)
          .map((m) => m.variant),
    );
  }

  /// True when the current Material Type + Category has two or more
  /// distinct real variant values to choose between — re-evaluated on every
  /// build, so changing either level above immediately reflects the new
  /// combination's own variant situation. When false (zero or exactly one
  /// distinct value), the Variant step is skipped entirely: most rows carry
  /// no variant distinction at all, and requiring a selection there was a
  /// dead end (a disabled dropdown the flow still waited on).
  bool get _cascadeNeedsVariantStep => _cascadeVariants.length >= 2;

  List<MaterialMasterItem> get _cascadeSizeRows {
    final materialType = _cascadeMaterialType;
    final category = _cascadeCategory;
    if (materialType == null || category == null) return const [];
    if (_cascadeNeedsVariantStep) {
      final variant = _cascadeVariant;
      if (variant == null) return const [];
      final rows = _catalog
          .where(
            (m) =>
                m.materialType == materialType &&
                m.category == category &&
                m.variant == variant,
          )
          .toList();
      rows.sort((a, b) => (a.sizeMm ?? 0).compareTo(b.sizeMm ?? 0));
      return rows;
    }
    // No real variant distinction for this Material Type + Category — every
    // matching row is reachable from Category alone (whether its own
    // `variant` is null, or the one shared non-null value there's no need
    // to choose between).
    final rows = _catalog
        .where(
          (m) =>
              m.materialType == materialType &&
              m.category == category,
        )
        .toList();
    rows.sort((a, b) => (a.sizeMm ?? 0).compareTo(b.sizeMm ?? 0));
    return rows;
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qty.text.trim());
    final group = _group;
    if (_materialName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a material from the catalog.')),
      );
      return;
    }
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a quantity greater than 0.')),
      );
      return;
    }
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a group (C, D, E, F, or G).')),
      );
      return;
    }

    setState(() => _saving = true);

    final existing = widget.existing;
    final draft = BomManualEntry(
      id: existing?.id ?? '',
      surveyId: widget.surveyId,
      materialName: _materialName,
      sku: _sku,
      itemLabel: _itemLabel,
      sensorSize: _sensorSize,
      sensorType: _sensorType,
      unit: _unit,
      qty: qty,
      group: group,
      addedBy: existing?.addedBy ?? widget.addedByRole,
      addedAt: existing?.addedAt ?? DateTime.now(),
    );

    if (existing == null) {
      await widget.repository.addBomManualEntry(draft);
    } else {
      await widget.repository.updateBomManualEntry(draft);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry saved.')),
    );
    Navigator.of(context).pop();
  }

  static String _catalogItemLabel(MaterialMasterItem m) {
    final namePart = m.sku.isEmpty ? m.materialName : '${m.materialName} (${m.sku})';
    return '$namePart — ${m.unit}';
  }

  Widget _buildFlatDropdown() {
    return AppDropdownField<MaterialMasterItem>(
      label: 'Material (from catalog)',
      value: _selectedMaterial,
      items: _catalog,
      itemLabel: _catalogItemLabel,
      emptyHint:
          'No Material Master rows yet — add some first (home '
          'screen, Admin only).',
      onChanged: _onMaterialSelected,
    );
  }

  /// Why the Size dropdown is currently empty, if it is — reflects whichever
  /// prior step actually gates it, since the Variant step may or may not be
  /// part of that chain (see [_cascadeNeedsVariantStep]).
  String get _cascadeSizeEmptyHint {
    if (_cascadeCategory == null) return 'Choose a Category first.';
    if (_cascadeNeedsVariantStep && _cascadeVariant == null) {
      return 'Choose a Variant first.';
    }
    return 'No sizes found for this selection.';
  }

  Widget _buildCascadeFields() {
    final needsVariantStep = _cascadeNeedsVariantStep;
    return Column(
      children: [
        AppDropdownField<String>(
          label: 'Material Type',
          value: _cascadeMaterialType,
          items: _cascadeMaterialTypes,
          itemLabel: (t) => t,
          emptyHint:
              'No plumbing catalog rows yet — add Material Master rows with '
              'Material Type set (Admin only).',
          onChanged: (v) => setState(() {
            _cascadeMaterialType = v;
            _cascadeCategory = null;
            _cascadeVariant = null;
            _applySelectedMaterial(null);
          }),
        ),
        AppDropdownField<String>(
          label: 'Category',
          value: _cascadeCategory,
          items: _cascadeCategories,
          itemLabel: (t) => t,
          emptyHint: 'Choose a Material Type first.',
          onChanged: (v) => setState(() {
            _cascadeCategory = v;
            _cascadeVariant = null;
            _applySelectedMaterial(null);
          }),
        ),
        // Skipped entirely (not just disabled) when this Material Type +
        // Category combination has zero or one real variant value — most
        // rows carry no variant distinction at all, so requiring a
        // selection here was a dead end. Re-evaluated on every build, so
        // switching Category can add or remove this step immediately.
        if (needsVariantStep)
          AppDropdownField<String>(
            label: 'Variant',
            value: _cascadeVariant,
            items: _cascadeVariants,
            itemLabel: (t) => t,
            emptyHint: 'Choose a Category first.',
            onChanged: (v) => setState(() {
              _cascadeVariant = v;
              _applySelectedMaterial(null);
            }),
          ),
        AppDropdownField<MaterialMasterItem>(
          label: 'Size',
          value: _selectedMaterial,
          items: _cascadeSizeRows,
          itemLabel: (m) => m.sizeDisplay?.isNotEmpty == true
              ? m.sizeDisplay!
              : _catalogItemLabel(m),
          emptyHint: _cascadeSizeEmptyHint,
          onChanged: _onMaterialSelected,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lockedGroup = widget.lockedGroup;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? (lockedGroup == null
                    ? 'Add material'
                    : 'Add material (${lockedGroup.code})')
              : 'Edit entry',
        ),
      ),
      body: _loadingCatalog
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (lockedGroup != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Group',
                        border: OutlineInputBorder(),
                      ),
                      child: Text('${lockedGroup.code} — ${lockedGroup.label}'),
                    ),
                  )
                else
                  AppDropdownField<MaterialGroup>(
                    label: 'Group (C, D, E, F, or G only)',
                    value: _group,
                    items: kBomManualEntryGroups,
                    itemLabel: (g) => '${g.code} — ${g.label}',
                    onChanged: _onGroupChanged,
                  ),
                const SizedBox(height: 8),
                if (_cascadeModeActive) _buildCascadeFields() else _buildFlatDropdown(),
                if (_materialName.isNotEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(_materialName),
                      subtitle: Text(
                        _sku.isEmpty ? 'Unit: $_unit' : 'SKU: $_sku  •  Unit: $_unit',
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _qty,
                  label: 'Quantity',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
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
                  label: const Text('Save entry'),
                ),
              ],
            ),
    );
  }
}
