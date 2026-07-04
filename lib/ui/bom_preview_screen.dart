import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/survey_repository.dart';
import '../models/bom_line.dart';
import '../models/bom_revision_line.dart';
import '../models/bom_snapshot.dart';
import '../models/bom_snapshot_line.dart';
import '../models/duct_lora.dart';
import '../models/inlet_point.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../services/bom_engine.dart';
import '../services/bom_excel_exporter.dart';
import '../services/bom_revision_engine.dart';
import 'bom_manual_entries_screen.dart';
import 'bom_revisions_screen.dart';

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
  bool _finalizing = false;

  // Loaded inputs, kept so export can recompute per-block without re-fetching.
  List<MaterialMasterItem> _materials = const [];
  List<SourcePoint> _sourcePoints = const [];
  List<InletPoint> _inletPoints = const [];
  List<DuctLora> _ductLoras = const [];

  // Set once a survey has been finalized. Non-null means the review screen
  // shows this frozen data instead of a live recompute — Export keeps using
  // the live `_bom` above regardless, per the Finalize slice's exclusions.
  BomSnapshot? _snapshot;
  List<BomSnapshotLine> _snapshotLines = const [];

  // Every revision's delta lines, flattened across all revisions (v2+), for
  // computing the running total. Which revision each line came from doesn't
  // matter here — that detail lives in BomRevisionsScreen's history view.
  List<BomRevisionLine> _allRevisionLines = const [];

  // Toggles the locked view between the running total (default — the
  // operationally relevant number) and the v1 frozen snapshot.
  bool _showRunningTotal = true;

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

    // Loaded unconditionally alongside the live compute above — a locked
    // survey has no snapshot removed later, so this is just "does one exist".
    final snapshot = await widget.repository.getBomSnapshot(widget.site.id);
    final snapshotLines = snapshot == null
        ? const <BomSnapshotLine>[]
        : await widget.repository.getBomSnapshotLines(snapshot.id);

    var allRevisionLines = const <BomRevisionLine>[];
    if (snapshot != null) {
      final revisions = await widget.repository.getBomRevisions(
        widget.site.id,
      );
      final lines = <BomRevisionLine>[];
      for (final revision in revisions) {
        lines.addAll(await widget.repository.getBomRevisionLines(revision.id));
      }
      allRevisionLines = lines;
    }

    if (!mounted) return;
    setState(() {
      _materials = materials;
      _sourcePoints = sourcePoints;
      _inletPoints = inletPoints;
      _ductLoras = ductLoras;
      _bom = bom;
      _snapshot = snapshot;
      _snapshotLines = snapshotLines;
      _allRevisionLines = allRevisionLines;
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

  /// Opens the version history (v1 + every revision), each viewable, with
  /// its own "Add revision" action. Only reachable once the survey is locked.
  Future<void> _openRevisions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomRevisionsScreen(
          repository: widget.repository,
          surveyId: widget.site.id,
          surveyName: widget.site.name,
          createdByRole: widget.addedByRole,
        ),
      ),
    );
    // A revision may have been added — refresh the running total.
    await _generate();
  }

  /// Freezes the current BoM (live A/B/C/F + D/E/G manual entries) as an
  /// immutable version-1 snapshot. One-way: no unlock/re-finalize flow exists.
  Future<void> _finalize() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalize BoM?'),
        content: const Text(
          'This freezes the current Bill of Materials as final. It cannot be '
          'edited or unlocked afterward — continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Finalize'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _finalizing = true);

    final bom = _bom;
    final manualEntries = await widget.repository.getBomManualEntries(
      widget.site.id,
    );

    final lines = <BomSnapshotLine>[
      if (bom != null)
        for (final group in MaterialGroup.values)
          for (final line in bom[group] ?? const <BomLine>[])
            BomSnapshotLine(
              id: '',
              snapshotId: '',
              sku: line.sku,
              item: _snapshotItemLabel(line),
              unit: line.unit,
              qty: line.quantity,
              group: line.group,
              source: BomSnapshotSource.auto,
            ),
      for (final entry in manualEntries)
        BomSnapshotLine(
          id: '',
          snapshotId: '',
          sku: entry.sku,
          item: entry.materialName,
          unit: entry.unit,
          qty: entry.qty,
          group: entry.group,
          source: BomSnapshotSource.manual,
        ),
    ];

    await widget.repository.finalizeBom(
      surveyId: widget.site.id,
      lines: lines,
      finalizedBy: widget.addedByRole,
    );

    if (!mounted) return;
    setState(() => _finalizing = false);
    await _generate();
  }

  static String _snapshotItemLabel(BomLine line) =>
      line.variantLabel == '—'
      ? line.materialName
      : '${line.materialName} (${line.variantLabel})';

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
    final locked = _snapshot != null;
    final hasNoMaterials =
        !locked && bom != null && bom.values.every((l) => l.isEmpty);
    final canExport = !_loading && !hasNoMaterials;
    final canFinalize = !_loading && !locked && !hasNoMaterials;
    final runningTotal = locked
        ? const BomRevisionEngine().computeRunningTotal(
            snapshotLines: _snapshotLines,
            revisionLines: _allRevisionLines,
          )
        : const <BomRunningTotalLine>[];

    return Scaffold(
      appBar: AppBar(
        title: Text('BoM — ${widget.site.name}'),
        actions: [
          if (locked)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Chip(
                  label: Text('Finalized'),
                  avatar: Icon(Icons.lock_outline, size: 18),
                ),
              ),
            ),
          if (locked)
            IconButton(
              tooltip: 'Version history / add revision',
              onPressed: _openRevisions,
              icon: const Icon(Icons.history),
            ),
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
      floatingActionButton: canFinalize
          ? FloatingActionButton.extended(
              onPressed: _finalizing ? null : _finalize,
              icon: _finalizing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_outline),
              label: const Text('Finalize'),
            )
          : null,
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
          : locked
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: true, label: Text('Running total')),
                      ButtonSegment(value: false, label: Text('v1 (Frozen)')),
                    ],
                    selected: {_showRunningTotal},
                    onSelectionChanged: (sel) =>
                        setState(() => _showRunningTotal = sel.first),
                  ),
                ),
                Expanded(
                  child: _showRunningTotal
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final group in MaterialGroup.values)
                              if (runningTotal.any((l) => l.group == group))
                                _RunningTotalGroupSection(
                                  group: group,
                                  lines: runningTotal
                                      .where((l) => l.group == group)
                                      .toList(),
                                ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final group in MaterialGroup.values)
                              if (_snapshotLines.any((l) => l.group == group))
                                _SnapshotGroupSection(
                                  group: group,
                                  lines: _snapshotLines
                                      .where((l) => l.group == group)
                                      .toList(),
                                ),
                          ],
                        ),
                ),
              ],
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

/// Read-only rendering of one group's frozen [BomSnapshotLine]s. Mirrors
/// [_GroupSection]'s look so a finalized BoM feels like the same screen, not
/// a different feature.
class _SnapshotGroupSection extends StatelessWidget {
  const _SnapshotGroupSection({required this.group, required this.lines});

  final MaterialGroup group;
  final List<BomSnapshotLine> lines;

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
            for (final line in lines) _SnapshotLineRow(line: line),
          ],
        ),
      ),
    );
  }
}

class _SnapshotLineRow extends StatelessWidget {
  const _SnapshotLineRow({required this.line});

  final BomSnapshotLine line;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(line.item),
      subtitle: Text(line.source.label),
      trailing: Text(
        '${_formatQuantity(line.qty)} ${line.unit}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  static String _formatQuantity(double q) {
    return q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
  }
}

/// Read-only rendering of one group's running-total lines (v1 + every
/// revision's deltas, summed). Mirrors [_GroupSection]'s look.
class _RunningTotalGroupSection extends StatelessWidget {
  const _RunningTotalGroupSection({required this.group, required this.lines});

  final MaterialGroup group;
  final List<BomRunningTotalLine> lines;

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
            for (final line in lines) _RunningTotalLineRow(line: line),
          ],
        ),
      ),
    );
  }
}

class _RunningTotalLineRow extends StatelessWidget {
  const _RunningTotalLineRow({required this.line});

  final BomRunningTotalLine line;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(line.sku.isEmpty ? line.item : '${line.item} (${line.sku})'),
      subtitle: line.isBelowZero
          ? Text(
              'Revisions push this below zero — showing 0',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          : null,
      leading: line.isBelowZero
          ? Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error)
          : null,
      trailing: Text(
        '${_formatQuantity(line.displayQty)} ${line.unit}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: line.isBelowZero ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    );
  }

  static String _formatQuantity(double q) {
    return q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
  }
}
