import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/bom_revision_line.dart';
import '../models/material_master_item.dart';
import '../models/survey_options.dart';
import 'widgets/bom_material_picker.dart';
import 'widgets/form_fields.dart';

/// Builds one draft [BomRevisionLine] for the "Add revision" flow: choose a
/// target group (A-G), pick a Material Master catalog row from it (name/
/// SKU/unit come along for the ride), and enter a quantity delta (+/-).
///
/// Group is chosen first here (unlike the old flat-catalog-then-group
/// order this screen used to have) so [BomMaterialPicker] — the same
/// cascade-for-C/D, group-filtered-flat-for-everything-else picker the
/// "Add materials" screen uses — has a group to filter by from the start.
/// This also fixes the same cross-group leakage bug for revisions that the
/// "Add materials" picker had: the old flat dropdown here showed the
/// *entire* catalog regardless of group.
///
/// Adding a brand-new material and adjusting the quantity of an existing v1
/// item are the same action here — both just pick a catalog row and enter a
/// delta; if it matches an existing (sku, item) pair the running total picks
/// it up, otherwise it's a new line.
///
/// Purely local: does not touch the repository. Pops the finished draft back
/// to the caller, which collects drafts before saving the whole revision in
/// one call.
class BomRevisionLineFormScreen extends StatefulWidget {
  const BomRevisionLineFormScreen({super.key, required this.repository});

  final SurveyRepository repository;

  @override
  State<BomRevisionLineFormScreen> createState() =>
      _BomRevisionLineFormScreenState();
}

class _BomRevisionLineFormScreenState
    extends State<BomRevisionLineFormScreen> {
  final _qty = TextEditingController();

  MaterialMasterItem? _selectedMaterial;
  String _materialName = '';
  String _sku = '';
  String _itemLabel = '';
  SensorSize? _sensorSize;
  SensorType? _sensorType;
  String _unit = '';
  MaterialGroup? _group;

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
    });
  }

  void _addLine() {
    final qty = double.tryParse(_qty.text.trim());
    final group = _group;
    if (_materialName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a material from the catalog.')),
      );
      return;
    }
    if (qty == null || qty == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a non-zero quantity delta (negative allowed).'),
        ),
      );
      return;
    }
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a group (A-G).')),
      );
      return;
    }

    Navigator.of(context).pop(
      BomRevisionLine(
        id: '',
        revisionId: '',
        sku: _sku,
        item: _itemLabelFor(_materialName, _selectedMaterial),
        materialName: _materialName,
        itemLabel: _itemLabel,
        sensorSize: _sensorSize,
        sensorType: _sensorType,
        unit: _unit,
        qtyDelta: qty,
        group: group,
      ),
    );
  }

  /// Mirrors BomEngine's variant-label combining rule (sensor size + type,
  /// from the catalog row itself) so a delta on the same catalog material
  /// produces the exact same `item` text as its v1 auto-computed line, and
  /// the running total sums them together instead of creating a duplicate.
  static String _itemLabelFor(String materialName, MaterialMasterItem? item) {
    if (item == null) return materialName;
    final parts = [
      item.sensorSize?.label,
      item.sensorType?.label,
    ].whereType<String>();
    return parts.isEmpty ? materialName : '$materialName (${parts.join(' · ')})';
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    return Scaffold(
      appBar: AppBar(title: const Text('Add line')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppDropdownField<MaterialGroup>(
            label: 'Group (A-G)',
            value: _group,
            items: MaterialGroup.values,
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
                subtitle: Text('Unit: $_unit'),
              ),
            ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _qty,
            label: 'Quantity delta (+/-)',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _addLine,
            icon: const Icon(Icons.add),
            label: const Text('Add line'),
          ),
        ],
      ),
    );
  }
}
