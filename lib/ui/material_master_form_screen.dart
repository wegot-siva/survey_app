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
  late final TextEditingController _quantityPerSensor;
  late final TextEditingController _formulaDivisor;
  late final TextEditingController _notes;

  late MaterialGroup _group;
  SensorSize? _sensorSize;
  SensorType? _sensorType;
  late MaterialBehaviorType _behaviorType;
  DerivedFormula? _derivedFormula;
  VariableSource? _variableSource;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _materialName = TextEditingController(text: e?.materialName ?? '');
    _sku = TextEditingController(text: e?.sku ?? '');
    _itemLabel = TextEditingController(text: e?.itemLabel ?? '');
    _unit = TextEditingController(text: e?.unit ?? '');
    _quantityPerSensor = TextEditingController(
      text: e?.quantityPerSensor.toString() ?? '0',
    );
    _formulaDivisor = TextEditingController(
      text: e?.formulaDivisor?.toString() ?? '',
    );
    _notes = TextEditingController(text: e?.notes ?? '');

    _group = e?.group ?? MaterialGroup.a;
    _sensorSize = e?.sensorSize;
    _sensorType = e?.sensorType;
    _behaviorType = e?.behaviorType ?? MaterialBehaviorType.fixed;
    _derivedFormula =
        e?.derivedFormula ?? DerivedFormula.ceilWiredSensorsDividedByDivisor;
    _variableSource = e?.variableSource;
  }

  @override
  void dispose() {
    _materialName.dispose();
    _sku.dispose();
    _itemLabel.dispose();
    _unit.dispose();
    _quantityPerSensor.dispose();
    _formulaDivisor.dispose();
    _notes.dispose();
    super.dispose();
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

    setState(() => _saving = true);

    final draft = MaterialMasterItem(
      id: widget.existing?.id ?? '',
      group: _group,
      materialName: name,
      sku: _sku.text.trim(),
      itemLabel: _itemLabel.text.trim(),
      unit: unit,
      behaviorType: _behaviorType,
      sensorSize: _sensorSize,
      sensorType: _sensorType,
      quantityPerSensor: double.tryParse(_quantityPerSensor.text.trim()) ?? 0,
      derivedFormula: _behaviorType == MaterialBehaviorType.derived
          ? _derivedFormula
          : null,
      formulaDivisor: _behaviorType == MaterialBehaviorType.derived
          ? double.tryParse(_formulaDivisor.text.trim())
          : null,
      variableSource: _behaviorType == MaterialBehaviorType.variable
          ? _variableSource
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
            label: 'Item label (optional — for Lumax export)',
          ),
          AppTextField(controller: _unit, label: 'Unit (e.g. pcs, m, set)'),
          AppDropdownField<MaterialGroup>(
            label: 'Group',
            value: _group,
            items: MaterialGroup.values,
            itemLabel: (g) => '${g.code} — ${g.label}',
            onChanged: (v) => setState(() => _group = v ?? _group),
          ),

          const FormSectionLabel('Sensor variant (optional)'),
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

          const FormSectionLabel('How the quantity is computed'),
          AppDropdownField<MaterialBehaviorType>(
            label: 'Behaviour',
            value: _behaviorType,
            items: MaterialBehaviorType.values,
            itemLabel: (v) => v.label,
            onChanged: (v) =>
                setState(() => _behaviorType = v ?? _behaviorType),
          ),

          if (_behaviorType == MaterialBehaviorType.fixed)
            AppTextField(
              controller: _quantityPerSensor,
              label: 'Quantity per sensor',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),

          if (_behaviorType == MaterialBehaviorType.derived) ...[
            AppDropdownField<DerivedFormula>(
              label: 'Formula',
              value: _derivedFormula,
              items: DerivedFormula.values,
              itemLabel: (v) => v.label,
              onChanged: (v) => setState(() => _derivedFormula = v),
            ),
            AppTextField(
              controller: _formulaDivisor,
              label: 'Divisor (N) — leave blank for 0 / TBD',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
          ],

          if (_behaviorType == MaterialBehaviorType.variable)
            AppDropdownField<VariableSource>(
              label: 'Survey field',
              value: _variableSource,
              items: VariableSource.values,
              itemLabel: (v) => v.label,
              onChanged: (v) => setState(() => _variableSource = v),
            ),

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
