import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/survey_repository.dart';
import '../models/bom_line.dart';
import '../models/duct_lora.dart';
import '../models/inlet_point.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../services/bom_engine.dart';
import '../services/bom_excel_exporter.dart';
import 'bom_manual_entries_screen.dart';

/// On-screen BoM preview for one site (Material Master phase). Reads
/// Material Master rows + the site's survey data, runs [BomEngine], and shows
/// the result grouped A–G. No prices, no export — that's a later phase.
class BomPreviewScreen extends StatefulWidget {
  const BomPreviewScreen({
    super.key,
    required this.repository,
    required this.site,
    required this.addedByRole,
  });

  final SurveyRepository repository;
  final Site site;

  /// Label of the signed-in role (e.g. "Engineer"), recorded on manual BoM
  /// entries added from this screen.
  final String addedByRole;

  @override
  State<BomPreviewScreen> createState() => _BomPreviewScreenState();
}

class _BomPreviewScreenState extends State<BomPreviewScreen> {
  Map<MaterialGroup, List<BomLine>>? _bom;
  bool _loading = true;
  bool _exporting = false;

  // Loaded inputs, kept so export can recompute per-block without re-fetching.
  List<MaterialMasterItem> _materials = const [];
  List<SourcePoint> _sourcePoints = const [];
  List<InletPoint> _inletPoints = const [];
  List<DuctLora> _ductLoras = const [];

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    final materials = await widget.repository.getMaterialMasterItems();
    final sourcePoints = await widget.repository.getSourcePoints(
      widget.site.id,
    );
    final inletPoints = await widget.repository.getInletPoints(
      widget.site.id,
    );
    final ductLoras = await widget.repository.getDuctLoras(widget.site.id);

    final bom = const BomEngine().generate(
      materials: materials,
      sourcePoints: sourcePoints,
      inletPoints: inletPoints,
      ductLoras: ductLoras,
    );

    if (!mounted) return;
    setState(() {
      _materials = materials;
      _sourcePoints = sourcePoints;
      _inletPoints = inletPoints;
      _ductLoras = ductLoras;
      _bom = bom;
      _loading = false;
    });
  }

  /// Runs the SAME [BomEngine] once per block over that block's filtered
  /// points — the engine math is unchanged, only its inputs are scoped. A
  /// site with no blocks yields a single sheet; points whose block isn't in
  /// the site's block list land in an "Unassigned" sheet so nothing is dropped.
  ///
  /// Note: DERIVED items (e.g. Duct LoRa = ceil(wired ÷ N)) round per block, so
  /// per-block totals can sum higher than the whole-site on-screen figure.
  List<BlockBom> _buildPerBlockBoms() {
    const engine = BomEngine();
    final siteBlocks = widget.site.blocks;

    if (siteBlocks.isEmpty) {
      return [
        (
          label: widget.site.name,
          bom: engine.generate(
            materials: _materials,
            sourcePoints: _sourcePoints,
            inletPoints: _inletPoints,
            ductLoras: _ductLoras,
          ),
        ),
      ];
    }

    final result = <BlockBom>[
      for (final block in siteBlocks)
        (
          label: block,
          bom: engine.generate(
            materials: _materials,
            sourcePoints: _sourcePoints.where((s) => s.block == block).toList(),
            inletPoints: _inletPoints.where((i) => i.block == block).toList(),
            ductLoras: _ductLoras.where((d) => d.block == block).toList(),
          ),
        ),
    ];

    bool unassigned(String? block) =>
        block == null || block.isEmpty || !siteBlocks.contains(block);
    final uSps = _sourcePoints.where((s) => unassigned(s.block)).toList();
    final uIps = _inletPoints.where((i) => unassigned(i.block)).toList();
    final uDls = _ductLoras.where((d) => unassigned(d.block)).toList();
    if (uSps.isNotEmpty || uIps.isNotEmpty || uDls.isNotEmpty) {
      result.add((
        label: 'Unassigned',
        bom: engine.generate(
          materials: _materials,
          sourcePoints: uSps,
          inletPoints: uIps,
          ductLoras: uDls,
        ),
      ));
    }
    return result;
  }

  /// Opens the D/E/G "Add materials" picker for this survey. Available any
  /// time regardless of survey status — not gated to the computed BoM having
  /// any rows.
  Future<void> _openManualEntries() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomManualEntriesScreen(
          repository: widget.repository,
          surveyId: widget.site.id,
          surveyName: widget.site.name,
          addedByRole: widget.addedByRole,
        ),
      ),
    );
    // Manual entries aren't part of the computed BoM shown here yet
    // (mechanics only this slice) — no need to regenerate on return.
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await const BomExcelExporter().export(
        siteName: widget.site.name,
        blocks: _buildPerBlockBoms(),
      );
      if (!mounted) return;
      setState(() => _exporting = false);
      await Share.shareXFiles(
        [XFile(path)],
        subject: 'BoM — ${widget.site.name}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export BoM: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bom = _bom;
    final hasNoMaterials = bom != null && bom.values.every((l) => l.isEmpty);
    final canExport = !_loading && !hasNoMaterials;

    return Scaffold(
      appBar: AppBar(
        title: Text('BoM — ${widget.site.name}'),
        actions: [
          IconButton(
            tooltip: 'Add materials (D/E/G)',
            onPressed: _openManualEntries,
            icon: const Icon(Icons.add_shopping_cart_outlined),
          ),
          IconButton(
            tooltip: 'Export BoM to Excel',
            onPressed: canExport && !_exporting ? _export : null,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : hasNoMaterials
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No Material Master rows yet.\n\n'
                  'Add rows in Material Master (from the home screen) so the '
                  'BoM engine has quantities to compute from.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final group in MaterialGroup.values)
                  if ((bom![group] ?? const []).isNotEmpty)
                    _GroupSection(group: group, lines: bom[group]!),
              ],
            ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.group, required this.lines});

  final MaterialGroup group;
  final List<BomLine> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                '${group.code} — ${group.label}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            for (final line in lines) _BomLineRow(line: line),
          ],
        ),
      ),
    );
  }
}

class _BomLineRow extends StatelessWidget {
  const _BomLineRow({required this.line});

  final BomLine line;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(line.materialName),
      subtitle: Text(line.variantLabel),
      trailing: Text(
        '${_formatQuantity(line.quantity)} ${line.unit}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  static String _formatQuantity(double q) {
    return q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
  }
}
