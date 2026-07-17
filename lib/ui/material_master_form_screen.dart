import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/material_master_item.dart';
import '../models/survey_options.dart';
import 'widgets/form_fields.dart';

/// Add or edit a single Material Master row. Every quantity here is what the
/// BoM engine reads at generation time — there is no code-side fallback, so
/// leaving a quantity at 0 genuinely means "0 / TBD" in every generated BoM
/// until this row is edited.
///
/// The group-specific fields shown are conditional on [_group] — Behaviour is
/// never a user-facing control (it's always saved as
/// [MaterialBehaviorType.fixed]; DERIVED/VARIABLE rows can't be created or
/// edited from this form):
/// - Group A: sensor size/type + quantity per sensor (matched by
///   BomEngine._generateGroupA).
/// - Group C or D: the plumbing cascade fields (material type/category/
///   variant/size) — a cascade row is always visible to both C's and D's
///   picker regardless of which of the two it's tagged, since
///   [BomMaterialPicker]'s cascade never filters by group.
/// - Group B, E, F, or G: name/SKU/unit/notes only — flat manual-pick
///   catalogs with nothing else to compute.
class MaterialMasterFormScreen extends StatefulWidget {
  const MaterialMasterFormScreen({
    super.key,
    required this.repository,
    required this.changedByRole,
    this.existing,
  });

  final SurveyRepository repository;

  /// Label of the signed-in role (e.g. "Admin"), recorded on the change-log
  /// entry this save writes.
  final String changedByRole;

  final MaterialMasterItem? existing;

  @override
  State<MaterialMasterFormScreen> createState() =>
      _MaterialMasterFormScreenState();
}

class _MaterialMasterFormScreenState extends State<MaterialMasterFormScreen> {
  late final TextEditingController _materialName;
  late final TextEditingController _sku;
  late final TextEditingController _itemLabel;
  late final TextEditingController _unit;
  late final TextEditingController _notes;

  // Group A only.
  late final TextEditingController _quantityPerSensor;

  // Group C/D (cascade) only.
  late final TextEditingController _materialType;
  late final TextEditingController _category;
  late final TextEditingController _variant;
  late final TextEditingController _sizeMm;
  late final TextEditingController _sizeDisplay;

  late MaterialGroup _group;
  SensorSize? _sensorSize;
  SensorType? _sensorType;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _materialName = TextEditingController(text: e?.materialName ?? '');
    _sku = TextEditingController(text: e?.sku ?? '');
    _itemLabel = TextEditingController(text: e?.itemLabel ?? '');
    _unit = TextEditingController(text: e?.unit ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');

    _quantityPerSensor = TextEditingController(
      text: e?.quantityPerSensor.toString() ?? '0',
    );

    _materialType = TextEditingController(text: e?.materialType ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    _variant = TextEditingController(text: e?.variant ?? '');
    _sizeMm = TextEditingController(text: e?.sizeMm?.toString() ?? '');
    _sizeDisplay = TextEditingController(text: e?.sizeDisplay ?? '');

    _group = e?.group ?? MaterialGroup.a;
    _sensorSize = e?.sensorSize;
    _sensorType = e?.sensorType;
  }

  @override
  void dispose() {
    _materialName.dispose();
    _sku.dispose();
    _itemLabel.dispose();
    _unit.dispose();
    _notes.dispose();
    _quantityPerSensor.dispose();
    _materialType.dispose();
    _category.dispose();
    _variant.dispose();
    _sizeMm.dispose();
    _sizeDisplay.dispose();
    super.dispose();
  }

  bool get _isGroupA => _group == MaterialGroup.a;
  bool get _isCascadeGroup => _group == MaterialGroup.c || _group == MaterialGroup.d;

  /// Switching group clears whichever fields the new group no longer shows,
  /// so a stale value from a previous selection can never be silently saved
  /// under the wrong group.
  void _onGroupChanged(MaterialGroup? newGroup) {
    if (newGroup == null) return;
    setState(() {
      _group = newGroup;
      if (!_isGroupA) {
        _sensorSize = null;
        _sensorType = null;
        _quantityPerSensor.text = '0';
      }
      if (!_isCascadeGroup) {
        _materialType.clear();
        _category.clear();
        _variant.clear();
        _sizeMm.clear();
        _sizeDisplay.clear();
      }
    });
  }

  /// Group A rows are matched by sensor size + type alone (see
  /// BomEngine._generateGroupA) — two active rows for the same combination
  /// would be an unresolvable conflict the moment a BoM is generated, so
  /// this is rejected here instead of surfacing as a Generate BoM banner
  /// after the fact. Only applies to group A with both size and type set
  /// (a wildcard row can't collide the same way); the row being edited is
  /// excluded from the check against itself.
  Future<MaterialMasterItem?> _conflictingGroupARow() async {
    if (!_isGroupA || _sensorSize == null || _sensorType == null) {
      return null;
    }
    final existing = await widget.repository.getMaterialMasterItems();
    for (final m in existing) {
      if (m.id == (widget.existing?.id ?? '')) continue;
      if (m.group == MaterialGroup.a &&
          m.sensorSize == _sensorSize &&
          m.sensorType == _sensorType) {
        return m;
      }
    }
    return null;
  }

  /// Same idea as [_conflictingGroupARow], for the cascade's own identity:
  /// material type + category + variant + size (mm) — the exact fields
  /// [BomMaterialPicker]'s cascade steps down through to reach a leaf. Checked
  /// across *both* C and D rows together, not just the currently-selected
  /// group — the cascade never filters by group (see the class doc), so a
  /// duplicate tagged the other of the two would be just as ambiguous in the
  /// picker as one tagged the same group.
  Future<MaterialMasterItem?> _conflictingCascadeRow() async {
    if (!_isCascadeGroup) return null;
    final materialType = _materialType.text.trim();
    final category = _category.text.trim();
    if (materialType.isEmpty || category.isEmpty) return null;
    final variant = _variant.text.trim().isEmpty ? null : _variant.text.trim();
    final sizeMm = double.tryParse(_sizeMm.text.trim());

    final existing = await widget.repository.getMaterialMasterItems();
    for (final m in existing) {
      if (m.id == (widget.existing?.id ?? '')) continue;
      if ((m.group == MaterialGroup.c || m.group == MaterialGroup.d) &&
          m.materialType == materialType &&
          m.category == category &&
          m.variant == variant &&
          m.sizeMm == sizeMm) {
        return m;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final name = _materialName.text.trim();
    final unit = _unit.text.trim();
    if (name.isEmpty || unit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material name and unit are required.')),
      );
      return;
    }
    if (_isCascadeGroup &&
        (_materialType.text.trim().isEmpty || _category.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Material type and category are required for C/D.'),
        ),
      );
      return;
    }

    final groupAConflict = await _conflictingGroupARow();
    if (groupAConflict != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A Group A row for ${_sensorSize!.label} ${_sensorType!.label} '
            'already exists ("${groupAConflict.materialName}") — edit that '
            'row instead of creating a duplicate.',
          ),
        ),
      );
      return;
    }

    final cascadeConflict = await _conflictingCascadeRow();
    if (cascadeConflict != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A cascade row for this Material type/Category/Variant/Size '
            'already exists ("${cascadeConflict.materialName}", group '
            '${cascadeConflict.group.code}) — edit that row instead of '
            'creating a duplicate.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final draft = MaterialMasterItem(
      id: widget.existing?.id ?? '',
      group: _group,
      materialName: name,
      sku: _sku.text.trim(),
      itemLabel: _itemLabel.text.trim(),
      unit: unit,
      // Never user-facing — Fixed is the only mode this form can produce.
      // See the class doc for why DERIVED/VARIABLE aren't offered here.
      behaviorType: MaterialBehaviorType.fixed,
      sensorSize: _isGroupA ? _sensorSize : null,
      sensorType: _isGroupA ? _sensorType : null,
      quantityPerSensor: _isGroupA
          ? (double.tryParse(_quantityPerSensor.text.trim()) ?? 0)
          : 0,
      materialType: _isCascadeGroup ? _materialType.text.trim() : null,
      category: _isCascadeGroup ? _category.text.trim() : null,
      variant: _isCascadeGroup && _variant.text.trim().isNotEmpty
          ? _variant.text.trim()
          : null,
      sizeMm: _isCascadeGroup ? double.tryParse(_sizeMm.text.trim()) : null,
      sizeDisplay: _isCascadeGroup && _sizeDisplay.text.trim().isNotEmpty
          ? _sizeDisplay.text.trim()
          : null,
      notes: _notes.text.trim(),
    );

    if (widget.existing == null) {
      await widget.repository.addMaterialMasterItem(
        draft,
        changedByRole: widget.changedByRole,
      );
    } else {
      await widget.repository.updateMaterialMasterItem(
        draft,
        changedByRole: widget.changedByRole,
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Material row saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Add material' : 'Edit material',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppTextField(controller: _materialName, label: 'Material name'),
          AppTextField(controller: _sku, label: 'SKU (optional)'),
          AppTextField(
            controller: _itemLabel,
            label: 'Item label (optional — used as the "Item" column in '
                'Standard/Lumax export instead of Material name)',
          ),
          AppTextField(controller: _unit, label: 'Unit (e.g. pcs, m, set)'),
          AppDropdownField<MaterialGroup>(
            label: 'Group',
            value: _group,
            items: MaterialGroup.values,
            itemLabel: (g) => '${g.code} — ${g.label}',
            onChanged: _onGroupChanged,
          ),

          if (_isGroupA) ...[
            const FormSectionLabel('Sensor variant'),
            _NullableDropdown<SensorSize>(
              label: 'Sensor size',
              value: _sensorSize,
              items: SensorSize.values,
              itemLabel: (v) => v.label,
              anyLabel: 'Any size',
              onChanged: (v) => setState(() => _sensorSize = v),
            ),
            _NullableDropdown<SensorType>(
              label: 'Sensor type',
              value: _sensorType,
              items: SensorType.values,
              itemLabel: (v) => v.label,
              anyLabel: 'Any type',
              onChanged: (v) => setState(() => _sensorType = v),
            ),
            AppTextField(
              controller: _quantityPerSensor,
              label: 'Quantity per sensor',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
          ],

          if (_isCascadeGroup) ...[
            const FormSectionLabel('Plumbing catalog (cascade)'),
            AppTextField(
              controller: _materialType,
              label: 'Material type (e.g. uPVC, CPVC)',
            ),
            AppTextField(
              controller: _category,
              label: 'Category (e.g. Elbow 90°, Tee, Coupler)',
            ),
            AppTextField(
              controller: _variant,
              label: 'Variant (optional — e.g. SCH40, Brass Threaded)',
            ),
            AppTextField(
              controller: _sizeMm,
              label: 'Size in mm (sort/join field, not shown to engineers)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            AppTextField(
              controller: _sizeDisplay,
              label: 'Size shown in picker (e.g. 1¼", 1¼" x 1")',
            ),
          ],

          AppTextField(
            controller: _notes,
            label: 'Notes (optional)',
            maxLines: 2,
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
            label: const Text('Save material row'),
          ),
        ],
      ),
    );
  }
}

/// A dropdown whose value can genuinely be "Any" (null), shown as a real
/// selectable entry rather than just "nothing picked yet".
class _NullableDropdown<T> extends StatelessWidget {
  const _NullableDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.anyLabel,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final String anyLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<T?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text(anyLabel)),
          for (final item in items)
            DropdownMenuItem<T?>(value: item, child: Text(itemLabel(item))),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
