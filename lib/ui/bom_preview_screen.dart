import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/survey_repository.dart';
import '../models/bom_line.dart';
import '../models/bom_revision.dart';
import '../models/bom_revision_line.dart';
import '../models/bom_snapshot.dart';
import '../models/bom_snapshot_line.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../services/bom_engine.dart';
import '../services/bom_revision_engine.dart';
import '../services/lumax_exporter.dart';
import '../services/sun_bom_exporter.dart';
import 'bom_manual_entries_screen.dart';
import 'bom_revisions_screen.dart';

/// Which export formatter to use — both read the same running-total data
/// (see [_BomPreviewScreenState._cumulativeTotalForVersion]); only the
/// output layout differs.
enum _ExportFormat { sunBom, lumax }

/// Entries in the AppBar's version menu — consolidates what used to be a
/// "Finalized" chip, a history icon button, and a running-total/v1
/// SegmentedButton into one control.
enum _VersionMenuAction { runningTotal, v1Frozen, history }

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

  // Set once a survey has been finalized. Non-null means the review screen
  // shows this frozen data instead of a live recompute, and the Export action
  // becomes available (export reads the snapshot + revision running total).
  BomSnapshot? _snapshot;
  List<BomSnapshotLine> _snapshotLines = const [];

  // Every revision (v2+) for this survey, oldest first, plus its delta
  // lines keyed by revision id — kept separate (rather than one flattened
  // list) so a cumulative total can be computed for any version, not just
  // the latest. See _cumulativeTotalForVersion.
  List<BomRevision> _revisions = const [];
  Map<String, List<BomRevisionLine>> _revisionLinesByRevision = const {};

  // Toggles the locked view between the running total (default — the
  // operationally relevant number) and the v1 frozen snapshot.
  bool _showRunningTotal = true;

  // Which version Export reads from. Defaults to the latest version every
  // time the screen (re)loads — see _generate.
  int _selectedExportVersion = 1;

  // Which output format Export writes. Defaults to Sun_BOM — current
  // behavior is unchanged unless this is touched.
  _ExportFormat _selectedExportFormat = _ExportFormat.sunBom;

  // Display-only filter: hides zero-qty rows (and groups with none left)
  // in the locked view (running total + v1 snapshot). Default OFF = hidden.
  // Never affects export, which already excludes zero-qty rows/empty groups
  // on its own. The unlocked/live view has its own per-group toggle instead
  // — see _showAllInGroup.
  bool _showAllItems = false;

  // Per-group "show all" toggle for the unlocked/live view only (bom_engine
  // emits every Material Master row regardless of quantity, so most groups
  // are mostly zero-qty rows by default). Empty = every group hides its
  // zero-qty lines.
  final Set<MaterialGroup> _showAllInGroup = {};

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

    var revisions = const <BomRevision>[];
    var revisionLinesByRevision = const <String, List<BomRevisionLine>>{};
    if (snapshot != null) {
      revisions = await widget.repository.getBomRevisions(widget.site.id);
      final byRevision = <String, List<BomRevisionLine>>{};
      for (final revision in revisions) {
        byRevision[revision.id] = await widget.repository.getBomRevisionLines(
          revision.id,
        );
      }
      revisionLinesByRevision = byRevision;
    }

    if (!mounted) return;
    setState(() {
      _bom = bom;
      _snapshot = snapshot;
      _snapshotLines = snapshotLines;
      _revisions = revisions;
      _revisionLinesByRevision = revisionLinesByRevision;
      // Reset to the latest version on every (re)load — see the field doc.
      _selectedExportVersion = revisions.isEmpty ? 1 : revisions.last.version;
      _loading = false;
    });
  }

  int get _latestVersion => _revisions.isEmpty ? 1 : _revisions.last.version;

  /// The cumulative total *as of* [version]: v1 snapshot lines plus every
  /// revision up through (and including) [version] — not just that
  /// version's own delta. [version] 1 yields the v1 snapshot alone.
  List<BomRunningTotalLine> _cumulativeTotalForVersion(int version) {
    final lines = <BomRevisionLine>[
      for (final revision in _revisions)
        if (revision.version <= version)
          ...(_revisionLinesByRevision[revision.id] ?? const []),
    ];
    return const BomRevisionEngine().computeRunningTotal(
      snapshotLines: _snapshotLines,
      revisionLines: lines,
    );
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
              materialName: line.materialName,
              itemLabel: line.itemLabel,
              sensorSize: line.sensorSize,
              sensorType: line.sensorType,
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
          materialName: entry.materialName,
          itemLabel: entry.itemLabel,
          sensorSize: entry.sensorSize,
          sensorType: entry.sensorType,
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

  /// v1 snapshot lines + every revision's deltas, summed per (sku, item).
  /// Empty when the survey isn't locked yet (both source lists are empty).
  /// Always the latest version, regardless of what Export has selected —
  /// this feeds the on-screen "Running total" toggle, a separate,
  /// already-decided display that Export's version selector doesn't affect.
  List<BomRunningTotalLine> get _runningTotal =>
      _cumulativeTotalForVersion(_latestVersion);

  /// Exports the cumulative total as of [_selectedExportVersion] (defaults
  /// to latest), in whichever format [_selectedExportFormat] has selected,
  /// and opens the share sheet. One shared data fetch
  /// (_cumulativeTotalForVersion) feeds both formatters — only the output
  /// layout differs.
  Future<void> _exportBom() async {
    setState(() => _exporting = true);
    final formatName = _selectedExportFormat == _ExportFormat.lumax
        ? 'Lumax'
        : 'Sun_BOM';
    try {
      final lines = _cumulativeTotalForVersion(_selectedExportVersion);
      final path = switch (_selectedExportFormat) {
        _ExportFormat.sunBom => await const SunBomExporter().export(
          siteName: widget.site.name,
          lines: lines,
        ),
        _ExportFormat.lumax => await const LumaxExporter().export(
          siteName: widget.site.name,
          lines: lines,
        ),
      };
      if (!mounted) return;
      setState(() => _exporting = false);
      await Share.shareXFiles(
        [XFile(path)],
        subject: '$formatName — ${widget.site.name}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export $formatName: $e')),
      );
    }
  }

  List<BomRunningTotalLine> _visibleRunningTotal(List<BomRunningTotalLine> lines) =>
      _showAllItems ? lines : lines.where((l) => l.rawQty > 0).toList();

  List<BomSnapshotLine> _visibleSnapshotLines(List<BomSnapshotLine> lines) =>
      _showAllItems ? lines : lines.where((l) => l.qty > 0).toList();

  /// Format + version selectors for Export, living below the AppBar rather
  /// than as AppBar actions — wide items (two text-heavy dropdowns, plus the
  /// version menu, export icon, add-materials icon) don't fit an AppBar's
  /// fixed-width action row, and AppBar.actions doesn't wrap or scroll; the
  /// ones furthest right (Export, Add materials) were the ones silently
  /// clipped off-screen. A [Wrap] here can drop to a second line on narrow
  /// screens instead of overflowing.
  Widget _exportOptionsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Format: '),
              DropdownButtonHideUnderline(
                child: DropdownButton<_ExportFormat>(
                  value: _selectedExportFormat,
                  onChanged: (f) {
                    if (f != null) setState(() => _selectedExportFormat = f);
                  },
                  items: const [
                    DropdownMenuItem(
                      value: _ExportFormat.sunBom,
                      child: Text('Sun_BOM format'),
                    ),
                    DropdownMenuItem(
                      value: _ExportFormat.lumax,
                      child: Text('Lumax format'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Version: '),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedExportVersion,
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedExportVersion = v);
                  },
                  // Compact "vN" while closed; full "Export vN" in the menu.
                  selectedItemBuilder: (context) => [
                    for (var v = 1; v <= _latestVersion; v++) Text('v$v'),
                  ],
                  items: [
                    for (var v = 1; v <= _latestVersion; v++)
                      DropdownMenuItem(value: v, child: Text('Export v$v')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _showAllItemsToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Switch(
            value: _showAllItems,
            onChanged: (v) => setState(() => _showAllItems = v),
          ),
          const Text('Show all items (including zero quantity)'),
        ],
      ),
    );
  }

  Widget _noVisibleItemsMessage() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Nothing has a quantity greater than 0 yet.\n\n'
          'Toggle "Show all items" above to see the full catalog.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bom = _bom;
    final locked = _snapshot != null;
    final hasNoMaterials =
        !locked && bom != null && bom.values.every((l) => l.isEmpty);
    final canFinalize = !_loading && !locked && !hasNoMaterials;
    final runningTotal = _runningTotal;
    final visibleRunningTotal = _visibleRunningTotal(runningTotal);
    final visibleSnapshotLines = _visibleSnapshotLines(_snapshotLines);

    return Scaffold(
      appBar: AppBar(
        title: Text('BoM — ${widget.site.name}'),
        actions: [
          if (locked)
            PopupMenuButton<_VersionMenuAction>(
              tooltip: 'Version',
              onSelected: (action) {
                switch (action) {
                  case _VersionMenuAction.runningTotal:
                    setState(() => _showRunningTotal = true);
                  case _VersionMenuAction.v1Frozen:
                    setState(() => _showRunningTotal = false);
                  case _VersionMenuAction.history:
                    _openRevisions();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _VersionMenuAction.runningTotal,
                  child: Text('Running total'),
                ),
                PopupMenuItem(
                  value: _VersionMenuAction.v1Frozen,
                  child: Text('v1 (Frozen)'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: _VersionMenuAction.history,
                  child: Text('Version history'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_showRunningTotal ? 'Running total' : 'v1 (Frozen)'),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          // Format/version selectors live below the AppBar now — see
          // _exportOptionsRow. Keeping AppBar.actions to fixed-size icons
          // only guarantees it never overflows (AppBar.actions doesn't wrap
          // or scroll), so Export stays reachable with one visible tap.
          //
          // Export is only offered once finalized: it emits the selected
          // version's cumulative total in the selected format, zero-qty
          // lines excluded, which doesn't exist until there's a v1 snapshot.
          if (locked)
            IconButton(
              tooltip: 'Export BoM',
              onPressed: _exporting ? null : _exportBom,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
            ),
          IconButton(
            tooltip: 'Add materials (D/E/G)',
            onPressed: _openManualEntries,
            icon: const Icon(Icons.playlist_add_outlined),
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
                _exportOptionsRow(),
                _showAllItemsToggle(),
                Expanded(
                  child:
                      (_showRunningTotal
                          ? visibleRunningTotal.isEmpty
                          : visibleSnapshotLines.isEmpty)
                      ? _noVisibleItemsMessage()
                      : _showRunningTotal
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final group in MaterialGroup.values)
                              if (visibleRunningTotal.any(
                                (l) => l.group == group,
                              ))
                                _RunningTotalGroupSection(
                                  group: group,
                                  lines: visibleRunningTotal
                                      .where((l) => l.group == group)
                                      .toList(),
                                ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final group in MaterialGroup.values)
                              if (visibleSnapshotLines.any(
                                (l) => l.group == group,
                              ))
                                _SnapshotGroupSection(
                                  group: group,
                                  lines: visibleSnapshotLines
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
                  if (bom![group]!.isNotEmpty)
                    _GroupSection(
                      group: group,
                      lines: bom[group]!,
                      showAll: _showAllInGroup.contains(group),
                      onToggleShowAll: () => setState(() {
                        if (!_showAllInGroup.remove(group)) {
                          _showAllInGroup.add(group);
                        }
                      }),
                    ),
              ],
            ),
    );
  }
}

/// Live/unlocked group section. Hides zero-qty lines by default — bom_engine
/// emits every Material Master row regardless of computed quantity, so most
/// rows are zero — with a per-group "Show all (N)" button to reveal them.
class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.lines,
    required this.showAll,
    required this.onToggleShowAll,
  });

  final MaterialGroup group;
  final List<BomLine> lines;
  final bool showAll;
  final VoidCallback onToggleShowAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hiddenCount = lines.where((l) => l.quantity <= 0).length;
    final visibleLines = showAll
        ? lines
        : lines.where((l) => l.quantity > 0).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              color: scheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${group.code} — ${group.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  if (hiddenCount > 0)
                    TextButton(
                      onPressed: onToggleShowAll,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onSecondaryContainer,
                      ),
                      child: Text(
                        showAll ? 'Hide zero-qty' : 'Show all ($hiddenCount)',
                      ),
                    ),
                ],
              ),
            ),
            for (final line in visibleLines) _BomLineRow(line: line),
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
