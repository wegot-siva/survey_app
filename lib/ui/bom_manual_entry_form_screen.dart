import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/bom_manual_entry.dart';
import '../models/material_master_item.dart';
import '../models/survey_options.dart';
import 'widgets/form_fields.dart';

/// The reusable "Add materials" picker: pick a Material Master catalog row
/// (its name/SKU/unit come along for the ride), enter a quantity, and file it
/// under D, E, or G. Add or edit a single [BomManualEntry].
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
  });

  final SurveyRepository repository;
  final String surveyId;

  /// Label of the signed-in role (e.g. "Engineer"), recorded as `addedBy` for
  /// a freshly-created entry. Ignored when editing (the original `addedBy` /
  /// `addedAt` are preserved — see [BomManualEntry]).
  final String addedByRole;

  final BomManualEntry? existing;

  @override
  State<BomManualEntryFormScreen> createState() =>
      _BomManualEntryFormScreenState();
}

class _BomManualEntryFormScreenState extends State<BomManualEntryFormScreen> {
  late final TextEditingController _qty;

  List<MaterialMasterItem> _catalog = const [];
  bool _loadingCatalog = true;

  /// The catalog row picked via the dropdown, if any — only used to update
  /// [_materialName]/[_sku]/[_unit] when a selection is (re)made. Starts null
  /// even when editing (an entry isn't linked back to a catalog row by id);
  /// the copied fields below already carry the existing values in that case.
  MaterialMasterItem? _selectedMaterial;

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
    _group = e?.group;
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

  void _onMaterialSelected(MaterialMasterItem? item) {
    setState(() {
      _selectedMaterial = item;
      if (item != null) {
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
        const SnackBar(content: Text('Choose a group (D, E, or G).')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add material' : 'Edit entry'),
      ),
      body: _loadingCatalog
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppDropdownField<MaterialMasterItem>(
                  label: 'Material (from catalog)',
                  value: _selectedMaterial,
                  items: _catalog,
                  itemLabel: _catalogItemLabel,
                  emptyHint:
                      'No Material Master rows yet — add some first (home '
                      'screen, Admin only).',
                  onChanged: _onMaterialSelected,
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
                AppDropdownField<MaterialGroup>(
                  label: 'Group (D, E, or G only)',
                  value: _group,
                  items: kBomManualEntryGroups,
                  itemLabel: (g) => '${g.code} — ${g.label}',
                  onChanged: (v) => setState(() => _group = v),
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
