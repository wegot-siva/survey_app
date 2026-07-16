import 'package:flutter/material.dart';

import '../../data/survey_repository.dart';
import '../../models/material_master_item.dart';
import 'form_fields.dart';

/// Shared "pick a Material Master row" step, used by both the "Add
/// materials" picker (BomManualEntryFormScreen, groups C-G) and the Add
/// Revision line form (BomRevisionLineFormScreen, groups A-G) — previously
/// two separately-maintained copies of the same cascade/group-filtering
/// logic, where a fix to one (the group-leakage fix, then the cascade's
/// Variant-skip fix) had to be re-applied to the other by hand. Now there's
/// exactly one implementation both screens depend on.
///
/// Renders the 4-level cascade (Material Type -> Category -> Variant ->
/// Size) unconditionally for [group] C or D — never falling back to a flat
/// dropdown for those two, even on an empty catalog — and a flat dropdown
/// filtered to exactly [group]'s own rows for every other group (A, B, E,
/// F, G). The cascade under D reads the exact same material_type-tagged
/// rows as C (those rows' own `group` stays C; only the caller's saved
/// entry/line gets D) — same rule as before, now enforced in one place.
///
/// [group] is fully owned by the caller, not chosen here: a fixed, locked
/// value for "Add materials" (opened from within one BoM section), or a
/// live value from an interactive Group dropdown the caller renders itself
/// for Add Revision (where a delta can target any of A-G). Resets its own
/// selection and reports null via [onChanged] whenever [group] changes.
///
/// Calls [onChanged] with the resolved [MaterialMasterItem] (or null while
/// nothing is fully resolved) — the caller reads materialName/sku/
/// itemLabel/sensorSize/sensorType/unit off of it for whatever entry shape
/// it's building (BomManualEntry vs BomRevisionLine).
class BomMaterialPicker extends StatefulWidget {
  const BomMaterialPicker({
    super.key,
    required this.repository,
    required this.group,
    required this.onChanged,
  });

  final SurveyRepository repository;
  final MaterialGroup group;
  final ValueChanged<MaterialMasterItem?> onChanged;

  @override
  State<BomMaterialPicker> createState() => _BomMaterialPickerState();
}

class _BomMaterialPickerState extends State<BomMaterialPicker> {
  /// Every Material Master row, unfiltered — the cascade needs C's
  /// material_type-tagged rows regardless of the group they're rendering
  /// under (C or D), and the flat dropdown narrows this down to exactly
  /// [BomMaterialPicker.group] itself — see [_flatCatalog].
  List<MaterialMasterItem> _catalog = const [];
  bool _loadingCatalog = true;

  /// The resolved catalog row (flat dropdown or cascade leaf), if any —
  /// mirrored out to the caller via [BomMaterialPicker.onChanged] on every
  /// change; this widget never records name/sku/unit itself; that's the
  /// caller's job, since it varies (a quantity vs a quantity delta, an
  /// `addedBy` vs a revision id, etc).
  MaterialMasterItem? _selectedMaterial;

  // Cascade-only selections (group C or D). Each level resets everything
  // below it when changed.
  String? _cascadeMaterialType;
  String? _cascadeCategory;
  String? _cascadeVariant;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void didUpdateWidget(covariant BomMaterialPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The old selection (cascade levels or a flat pick) belongs to the
    // group that's no longer current — clear it and tell the caller, so a
    // stale material never rides along under a newly-chosen group.
    if (oldWidget.group != widget.group) {
      _resetSelection();
    }
  }

  Future<void> _loadCatalog() async {
    final items = await widget.repository.getMaterialMasterItems();
    if (!mounted) return;
    setState(() {
      _catalog = items;
      _loadingCatalog = false;
    });
  }

  /// True when [BomMaterialPicker.group] should show the 4-level cascade
  /// instead of the flat dropdown — unconditionally for C (Plumbing
  /// accessories) and D (Plumbing rework — reworks draw from the same
  /// plumbing catalog), never for any other group. Not gated on whether the
  /// catalog currently has any material_type-tagged rows: C/D must always
  /// show the cascade, even on an empty catalog (see the Material Type
  /// dropdown's emptyHint in [_buildCascadeFields] for that case).
  bool get _cascadeModeActive =>
      widget.group == MaterialGroup.c || widget.group == MaterialGroup.d;

  void _resetSelection() {
    setState(() {
      _selectedMaterial = null;
      _cascadeMaterialType = null;
      _cascadeCategory = null;
      _cascadeVariant = null;
    });
    widget.onChanged(null);
  }

  void _setSelected(MaterialMasterItem? item) {
    setState(() => _selectedMaterial = item);
    widget.onChanged(item);
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
  /// dead end.
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
          (m) => m.materialType == materialType && m.category == category,
        )
        .toList();
    rows.sort((a, b) => (a.sizeMm ?? 0).compareTo(b.sizeMm ?? 0));
    return rows;
  }

  /// The flat dropdown's own catalog — [_catalog] narrowed to exactly
  /// [BomMaterialPicker.group]'s own rows, not the full unfiltered list the
  /// cascade reads. That full list exists so C and D's cascade can read C's
  /// material_type-tagged rows from D too — it must never leak into a flat
  /// group's dropdown, which only ever offers that one group's own rows.
  List<MaterialMasterItem> get _flatCatalog =>
      _catalog.where((m) => m.group == widget.group).toList();

  /// SKU is deliberately left out — it made these labels hard to scan when
  /// choosing between similar rows. Storage/export/audit still carry it;
  /// only this selection-time display drops it.
  static String _catalogItemLabel(MaterialMasterItem m) =>
      '${m.materialName} — ${m.unit}';

  Widget _buildFlatDropdown() {
    return AppDropdownField<MaterialMasterItem>(
      label: 'Material (from catalog)',
      value: _selectedMaterial,
      items: _flatCatalog,
      itemLabel: _catalogItemLabel,
      emptyHint:
          'No Material Master rows yet — add some first (home '
          'screen, Admin only).',
      onChanged: _setSelected,
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
          onChanged: (v) {
            setState(() {
              _cascadeMaterialType = v;
              _cascadeCategory = null;
              _cascadeVariant = null;
              _selectedMaterial = null;
            });
            widget.onChanged(null);
          },
        ),
        AppDropdownField<String>(
          label: 'Category',
          value: _cascadeCategory,
          items: _cascadeCategories,
          itemLabel: (t) => t,
          emptyHint: 'Choose a Material Type first.',
          onChanged: (v) {
            setState(() {
              _cascadeCategory = v;
              _cascadeVariant = null;
              _selectedMaterial = null;
            });
            widget.onChanged(null);
          },
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
            onChanged: (v) {
              setState(() {
                _cascadeVariant = v;
                _selectedMaterial = null;
              });
              widget.onChanged(null);
            },
          ),
        AppDropdownField<MaterialMasterItem>(
          label: 'Size',
          value: _selectedMaterial,
          items: _cascadeSizeRows,
          itemLabel: (m) => m.sizeDisplay?.isNotEmpty == true
              ? m.sizeDisplay!
              : _catalogItemLabel(m),
          emptyHint: _cascadeSizeEmptyHint,
          onChanged: _setSelected,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCatalog) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return _cascadeModeActive ? _buildCascadeFields() : _buildFlatDropdown();
  }
}
