import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/bom_manual_entry.dart';
import '../models/material_master_item.dart';
import '../models/survey_options.dart';
import 'widgets/bom_material_picker.dart';
import 'widgets/form_fields.dart';

/// The reusable "Add materials" picker: opened from within one BoM section
/// (C, D, E, F, or G — see [lockedGroup]), pick a Material Master catalog
/// row (its name/SKU/unit come along for the ride), and enter a quantity.
/// Add or edit a single [BomManualEntry].
///
/// The actual material-selection step (cascade for C/D, group-filtered flat
/// dropdown for E/F/G) is [BomMaterialPicker] — shared with the Add
/// Revision line form, so a fix to that logic only ever needs to happen
/// once. This screen just owns the Group field, quantity, and save.
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

  String _materialName = '';
  String _sku = '';
  String _itemLabel = '';
  SensorSize? _sensorSize;
  SensorType? _sensorType;
  String _unit = '';
  MaterialGroup? _group;

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
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _onGroupChanged(MaterialGroup? newGroup) {
    setState(() => _group = newGroup);
  }

  void _onMaterialChanged(MaterialMasterItem? item) {
    setState(() {
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
    });
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

  @override
  Widget build(BuildContext context) {
    final lockedGroup = widget.lockedGroup;
    final group = _group;
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
      body: ListView(
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
          if (group != null)
            BomMaterialPicker(
              repository: widget.repository,
              group: group,
              onChanged: _onMaterialChanged,
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Choose a group first.'),
            ),
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
