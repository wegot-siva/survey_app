import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/bom_revision_line.dart';
import '../models/material_master_item.dart';
import 'widgets/form_fields.dart';

/// Builds one draft [BomRevisionLine] for the "Add revision" flow: pick a
/// Material Master catalog row (name/SKU/unit come along for the ride, like
/// the D/E/G "Add materials" picker), enter a quantity delta (+/-), and file
/// it under any group A-G.
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

  List<MaterialMasterItem> _catalog = const [];
  bool _loadingCatalog = true;

  MaterialMasterItem? _selectedMaterial;
  String _materialName = '';
  String _sku = '';
  String _unit = '';
  MaterialGroup? _group;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final items = await widget.repository.getMaterialMasterItems();
    if (!mounted) return;
    setState(() {
      _catalog = items;
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
        _unit = item.unit;
        _group = item.group;
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

  static String _catalogItemLabel(MaterialMasterItem m) {
    final namePart = m.sku.isEmpty ? m.materialName : '${m.materialName} (${m.sku})';
    return '$namePart — ${m.unit}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add line')),
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
                  label: 'Quantity delta (+/-)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                  ],
                ),
                AppDropdownField<MaterialGroup>(
                  label: 'Group (A-G)',
                  value: _group,
                  items: MaterialGroup.values,
                  itemLabel: (g) => '${g.code} — ${g.label}',
                  onChanged: (v) => setState(() => _group = v),
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
