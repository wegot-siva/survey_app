import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/survey_repository.dart';
import '../models/bom_line.dart';
import '../models/bom_manual_edit_snapshot.dart';
import '../models/bom_manual_edit_snapshot_line.dart';
import '../models/bom_manual_entry.dart';
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
import 'bom_group_a_section_screen.dart';
import 'bom_group_manual_section_screen.dart';
import 'bom_manual_edit_screen.dart';
import 'bom_revision_form_screen.dart';
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
    this.readOnly = false,
    this.canEditBom = false,
  });

  final SurveyRepository repository;
  final Site site;

  /// Label of the signed-in role (e.g. "Engineer"), recorded on manual BoM
  /// entries added from this screen.
  final String addedByRole;

  /// When true: no "Add materials" action and no Finalize FAB — a reviewer
  /// can inspect the computed BoM (and Export/version history once locked)
  /// without being able to change it.
  final bool readOnly;

  /// Whether the signed-in role (Admin/Approver only) may open "Edit BoM" —
  /// independent of [readOnly], since a manual BoM edit is an Admin/Approver
  /// action available even on an otherwise read-only review (e.g. Approver's
  /// review of a submitted survey).
  final bool canEditBom;

  @override
  State<BomPreviewScreen> createState() => _BomPreviewScreenState();
}

class _BomPreviewScreenState extends State<BomPreviewScreen> {
  Map<MaterialGroup, List<BomLine>>? _bom;
  List<BomManualEntry> _manualEntries = const [];
  bool _loading = true;

  /// Whether Material Master has zero rows *at all* — the raw
  /// `getMaterialMasterItems()` result, before the B/C/F auto-only filter
  /// below narrows it down to what BomEngine actually sees. Deliberately not
  /// derived from [_bom]: most groups are manual-only now, so `_bom` having
  /// no lines for a group reflects that group having no auto-eligible rows
  /// (normal, expected), not Material Master being unpopulated.
  bool _materialMasterEmpty = true;
  bool _exporting = false;
  bool _finalizing = false;

  /// Source/inlet points whose sensor selection doesn't resolve to a
  /// currently-active Group A material — see [BomEngine.generate].
  /// Non-empty blocks Finalize (see [canFinalize] in build) and drives the
  /// banner shown above the section list; no other group's incompleteness
  /// is tracked this way.
  List<GroupAUnresolvedPoint> _groupAUnresolvedPoints = const [];

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

  // Every manual-edit snapshot (Admin/Approver full-version edit) for this
  // survey, oldest first, plus its full line list keyed by snapshot id.
  // Each one is a possible *base* for version resolution — see
  // _resolveBaseForVersion.
  List<BomManualEditSnapshot> _manualEditSnapshots = const [];
  Map<String, List<BomManualEditSnapshotLine>> _manualEditLinesBySnapshot =
      const {};

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
  // on its own. The unlocked/live view's own per-group "show all" toggle
  // lives on each section screen now (BomGroupASectionScreen /
  // BomGroupManualSectionScreen) instead of here.
  bool _showAllItems = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    final materials = await widget.repository.getMaterialMasterItems();
    // B (DCU/Duct LoRa/cable), C (Plumbing accessories), and F (Consumables)
    // moved to manual-picker-only entry — excluded here so the engine stops
    // auto-generating lines for them, but the rows themselves stay in
    // Material Master for the picker to read from. A is now the only fully
    // auto-generated group.
    final autoMaterials = materials
        .where(
          (m) =>
              m.group != MaterialGroup.b &&
              m.group != MaterialGroup.c &&
              m.group != MaterialGroup.f,
        )
        .toList();
    final sourcePoints = await widget.repository.getSourcePoints(
      widget.site.id,
    );
    final inletPoints = await widget.repository.getInletPoints(
      widget.site.id,
    );
    final ductLoras = await widget.repository.getDuctLoras(widget.site.id);

    final generated = const BomEngine().generate(
      materials: autoMaterials,
      sourcePoints: sourcePoints,
      inletPoints: inletPoints,
      ductLoras: ductLoras,
    );
    final bom = generated.lines;
    // Fetched here (rather than lazily per section) so the section-list
    // overview can show each group's running count without a per-tile fetch.
    final manualEntries = await widget.repository.getBomManualEntries(
      widget.site.id,
    );

    // Loaded unconditionally alongside the live compute above — a locked
    // survey has no snapshot removed later, so this is just "does one exist".
    final snapshot = await widget.repository.getBomSnapshot(widget.site.id);
    final snapshotLines = snapshot == null
        ? const <BomSnapshotLine>[]
        : await widget.repository.getBomSnapshotLines(snapshot.id);

    var revisions = const <BomRevision>[];
    var revisionLinesByRevision = const <String, List<BomRevisionLine>>{};
    var manualEditSnapshots = const <BomManualEditSnapshot>[];
    var manualEditLinesBySnapshot = const <String, List<BomManualEditSnapshotLine>>{};
    if (snapshot != null) {
      revisions = await widget.repository.getBomRevisions(widget.site.id);
      final byRevision = <String, List<BomRevisionLine>>{};
      for (final revision in revisions) {
        byRevision[revision.id] = await widget.repository.getBomRevisionLines(
          revision.id,
        );
      }
      revisionLinesByRevision = byRevision;

      manualEditSnapshots = await widget.repository.getBomManualEditSnapshots(
        widget.site.id,
      );
      final byManualEdit = <String, List<BomManualEditSnapshotLine>>{};
      for (final edit in manualEditSnapshots) {
        byManualEdit[edit.id] = await widget.repository
            .getBomManualEditSnapshotLines(edit.id);
      }
      manualEditLinesBySnapshot = byManualEdit;
    }

    if (!mounted) return;
    setState(() {
      _bom = bom;
      _materialMasterEmpty = materials.isEmpty;
      _groupAUnresolvedPoints = generated.groupAUnresolvedPoints;
      _manualEntries = manualEntries;
      _snapshot = snapshot;
      _snapshotLines = snapshotLines;
      _revisions = revisions;
      _revisionLinesByRevision = revisionLinesByRevision;
      _manualEditSnapshots = manualEditSnapshots;
      _manualEditLinesBySnapshot = manualEditLinesBySnapshot;
      // Reset to the latest version on every (re)load — see the field doc.
      _selectedExportVersion = _latestVersionOf(revisions, manualEditSnapshots);
      _loading = false;
    });
  }

  static int _latestVersionOf(
    List<BomRevision> revisions,
    List<BomManualEditSnapshot> manualEdits,
  ) {
    final versions = [
      1,
      for (final r in revisions) r.version,
      for (final m in manualEdits) m.version,
    ];
    return versions.reduce((a, b) => a > b ? a : b);
  }

  int get _latestVersion => _latestVersionOf(_revisions, _manualEditSnapshots);

  /// The full [BomRunningTotalLine] base at [version], normalized from
  /// whichever snapshot (the original v1, or a later manual-edit snapshot)
  /// has the highest version at or before [version] — the "nearest full
  /// snapshot at or before N" step of version resolution.
  ({int version, List<BomRunningTotalLine> lines}) _resolveBaseForVersion(
    int version,
  ) {
    const engine = BomRevisionEngine();
    var bestVersion = 1;
    var bestLines = engine.baseFromSnapshotLines(_snapshotLines);
    for (final edit in _manualEditSnapshots) {
      if (edit.version <= version && edit.version > bestVersion) {
        bestVersion = edit.version;
        bestLines = engine.baseFromManualEditLines(
          _manualEditLinesBySnapshot[edit.id] ?? const [],
        );
      }
    }
    return (version: bestVersion, lines: bestLines);
  }

  /// The cumulative total *as of* [version]: the nearest full base (v1, or a
  /// later manual-edit snapshot) at or before [version], plus every revision
  /// strictly after that base up through (and including) [version] — not
  /// just that revision's own delta. [version] 1 yields the v1 snapshot
  /// alone (there's nothing to layer, since no revision or manual edit can
  /// have version 1).
  List<BomRunningTotalLine> _cumulativeTotalForVersion(int version) {
    final base = _resolveBaseForVersion(version);
    final lines = <BomRevisionLine>[
      for (final revision in _revisions)
        if (revision.version > base.version && revision.version <= version)
          ...(_revisionLinesByRevision[revision.id] ?? const []),
    ];
    return const BomRevisionEngine().computeRunningTotal(
      baseLines: base.lines,
      revisionLines: lines,
    );
  }

  /// Opens the tapped group's own BoM section — the unlocked-view entry
  /// point, available any time regardless of survey status. A (fully
  /// auto-computed) gets a bespoke read-only-biased screen; B/C/D/E/F/G share
  /// [BomGroupManualSectionScreen], pre-scoped so the engineer never
  /// re-selects the group. Always refreshes on return — a manual entry may
  /// have been added/edited/deleted, and the section-list overview's counts
  /// need to reflect that.
  Future<void> _openSection(MaterialGroup group) async {
    final bom = _bom;
    final autoLines = bom?[group] ?? const <BomLine>[];
    switch (group) {
      case MaterialGroup.a:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BomGroupASectionScreen(lines: autoLines),
          ),
        );
      case MaterialGroup.b:
      case MaterialGroup.c:
      case MaterialGroup.d:
      case MaterialGroup.e:
      case MaterialGroup.f:
      case MaterialGroup.g:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BomGroupManualSectionScreen(
              repository: widget.repository,
              surveyId: widget.site.id,
              surveyName: widget.site.name,
              addedByRole: widget.addedByRole,
              group: group,
              autoLines: autoLines,
              readOnly: widget.readOnly,
            ),
          ),
        );
    }
    await _generate();
  }

  /// Opens the version history (v1 + every revision + every manual edit),
  /// each viewable, with its own "Add revision" action. Only reachable once
  /// the survey is locked.
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
    // A revision or manual edit may have been added — refresh the running
    // total.
    await _generate();
  }

  /// Jumps straight to "Add revision" — a fast path from the BoM overview
  /// (the FAB below), added alongside (not replacing) the AppBar's "Version
  /// history" -> [_openRevisions] path, which still works exactly as before
  /// for browsing v1/past revisions/manual edits. Only shown once locked —
  /// see the FAB in [build].
  Future<void> _addRevision() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomRevisionFormScreen(
          repository: widget.repository,
          surveyId: widget.site.id,
          surveyName: widget.site.name,
          createdByRole: widget.addedByRole,
        ),
      ),
    );
    await _generate();
  }

  /// Opens "Edit BoM": an editable table of the *current* (latest) version's
  /// full line items. Saving creates a new [BomManualEditSnapshot] — the new
  /// latest version — never touching any existing snapshot/revision row.
  /// Admin/Approver only — see [widget.canEditBom].
  Future<void> _openEditBom() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomManualEditScreen(
          repository: widget.repository,
          surveyId: widget.site.id,
          surveyName: widget.site.name,
          basedOnVersion: _latestVersion,
          currentLines: _cumulativeTotalForVersion(_latestVersion),
          editedByRole: widget.addedByRole,
        ),
      ),
    );
    // A new version may have been created — refresh the running total.
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

  /// Exports the cumulative total as of [_selectedExportVersion], in
  /// whichever format [_selectedExportFormat] has selected, and opens the
  /// system share sheet — reached only via [_openExportSheet], which sets
  /// both right before calling this. One shared data fetch
  /// (_cumulativeTotalForVersion) feeds both formatters — only the output
  /// layout differs.
  Future<void> _exportBom() async {
    setState(() => _exporting = true);
    final formatName = _selectedExportFormat == _ExportFormat.lumax
        ? 'Standard'
        : 'Zoho Import';
    try {
      final lines = _cumulativeTotalForVersion(_selectedExportVersion);
      final path = switch (_selectedExportFormat) {
        _ExportFormat.sunBom => await const SunBomExporter().export(
          siteName: widget.site.name,
          lines: lines,
          version: _selectedExportVersion,
        ),
        _ExportFormat.lumax => await const LumaxExporter().export(
          siteName: widget.site.name,
          lines: lines,
          version: _selectedExportVersion,
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

  /// The single AppBar Export action's entry point — collects format and
  /// version (Running Total vs the frozen v1 snapshot) in one bottom sheet,
  /// then calls [_exportBom] exactly once, which opens the normal Android
  /// share sheet (WhatsApp, Gmail, Drive, Files, ...) — this sheet is the
  /// only export UI now; the main body shows BoM content only.
  Future<void> _openExportSheet() async {
    var format = _selectedExportFormat;
    var runningTotal = _showRunningTotal;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Export BoM',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Format',
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                RadioGroup<_ExportFormat>(
                  groupValue: format,
                  onChanged: (v) => setSheetState(() => format = v!),
                  child: const Column(
                    children: [
                      RadioListTile<_ExportFormat>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('Standard (Lumax)'),
                        value: _ExportFormat.lumax,
                      ),
                      RadioListTile<_ExportFormat>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('Zoho Import'),
                        value: _ExportFormat.sunBom,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Version',
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                RadioGroup<bool>(
                  groupValue: runningTotal,
                  onChanged: (v) => setSheetState(() => runningTotal = v!),
                  child: const Column(
                    children: [
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('Running Total'),
                        value: true,
                      ),
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('V1 (Frozen)'),
                        value: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _selectedExportFormat = format;
      _selectedExportVersion = runningTotal ? _latestVersion : 1;
    });
    await _exportBom();
  }

  List<BomRunningTotalLine> _visibleRunningTotal(List<BomRunningTotalLine> lines) =>
      _showAllItems ? lines : lines.where((l) => l.rawQty > 0).toList();

  List<BomSnapshotLine> _visibleSnapshotLines(List<BomSnapshotLine> lines) =>
      _showAllItems ? lines : lines.where((l) => l.qty > 0).toList();

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
    final hasNoMaterials = !locked && bom != null && _materialMasterEmpty;
    final hasGroupAIssues = _groupAUnresolvedPoints.isNotEmpty;
    final canFinalize =
        !_loading &&
        !locked &&
        !hasNoMaterials &&
        !hasGroupAIssues &&
        !widget.readOnly;
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
          // Format/version/share-method are all collected in the bottom
          // sheet _openExportSheet opens — the only export UI now; the main
          // body shows BoM content only.
          //
          // Export is only offered once finalized: it emits the selected
          // version's cumulative total in the selected format, zero-qty
          // lines excluded, which doesn't exist until there's a v1 snapshot.
          if (locked)
            IconButton(
              tooltip: 'Export BoM',
              onPressed: _exporting ? null : _openExportSheet,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
            ),
          if (locked && widget.canEditBom)
            IconButton(
              tooltip: 'Edit BoM',
              onPressed: _openEditBom,
              icon: const Icon(Icons.edit),
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
          // Fast path to "Add revision" — one tap from the BoM overview,
          // once locked (mirrors canFinalize's own "!locked" gate, so the
          // two FABs never overlap). "Version history" still exists in the
          // AppBar above for browsing v1/past revisions/manual edits;
          // nothing about that path changed.
          : locked
          ? FloatingActionButton.extended(
              onPressed: _addRevision,
              icon: const Icon(Icons.add),
              label: const Text('Add revision'),
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
                if (hasGroupAIssues) _groupAIssuesBanner(),
                for (final group in MaterialGroup.values)
                  _BomSectionTile(
                    group: group,
                    count: _sectionCount(bom!, group),
                    onTap: () => _openSection(group),
                  ),
              ],
            ),
    );
  }

  /// Names every source/inlet point currently blocking Finalize because its
  /// sensor selection doesn't resolve to an active Group A material — never
  /// a generic "catalog incomplete" message. Only Group A's incompleteness
  /// is surfaced this way; no other group blocks Finalize.
  Widget _groupAIssuesBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Group A sensor selection issues — Finalize is blocked '
                  'until these points are reopened and a material is picked.',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (final point in _groupAUnresolvedPoints)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No active Group A material selected for ${point.description} '
                '— reopen it and pick one.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
        ],
      ),
    );
  }

  /// How many lines currently count as "in" [group], for the section-list
  /// overview only — auto lines with a positive quantity (BomEngine emits
  /// every Material Master row regardless of quantity, so a zero-qty row
  /// isn't "current"), plus, for B/C/D/E/F/G, that group's manual entries.
  /// Group A never has manual entries of its own (no add action at all), so
  /// its count is auto-only.
  int _sectionCount(Map<MaterialGroup, List<BomLine>> bom, MaterialGroup group) {
    final autoCount = (bom[group] ?? const []).where((l) => l.quantity > 0).length;
    if (group == MaterialGroup.a) return autoCount;
    return autoCount + _manualEntries.where((e) => e.group == group).length;
  }
}

/// One row of the section-list overview (unlocked/live view only) — tapping
/// opens that group's own BoM section screen (see [_BomPreviewScreenState._openSection]).
class _BomSectionTile extends StatelessWidget {
  const _BomSectionTile({
    required this.group,
    required this.count,
    required this.onTap,
  });

  final MaterialGroup group;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(child: Text(group.code)),
          title: Text(group.label),
          subtitle: Text('$count item${count == 1 ? '' : 's'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
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
