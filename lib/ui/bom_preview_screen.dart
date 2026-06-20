import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/bom_line.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../services/bom_engine.dart';

/// On-screen BoM preview for one site (Material Master phase). Reads
/// Material Master rows + the site's survey data, runs [BomEngine], and shows
/// the result grouped A–G. No prices, no export — that's a later phase.
class BomPreviewScreen extends StatefulWidget {
  const BomPreviewScreen({
    super.key,
    required this.repository,
    required this.site,
  });

  final SurveyRepository repository;
  final Site site;

  @override
  State<BomPreviewScreen> createState() => _BomPreviewScreenState();
}

class _BomPreviewScreenState extends State<BomPreviewScreen> {
  Map<MaterialGroup, List<BomLine>>? _bom;
  bool _loading = true;

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
      _bom = bom;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bom = _bom;
    final hasNoMaterials = bom != null && bom.values.every((l) => l.isEmpty);

    return Scaffold(
      appBar: AppBar(title: Text('BoM — ${widget.site.name}')),
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
