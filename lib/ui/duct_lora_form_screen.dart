import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/duct_lora.dart';
import '../models/site.dart';
import '../models/survey_photo.dart';
import 'photo_markup_screen.dart';
import 'widgets/form_fields.dart';
import 'widgets/photo_capture_field.dart';

/// Add or edit a single Duct LoRa unit. Series served (at least one) and
/// cable length are mandatory (see `_save`); every other field is optional
/// (partial saves).
///
/// [availableSeries] are the distinct Series values entered on this site's
/// inlet points — the unit's "series served" is chosen from those.
class DuctLoraFormScreen extends StatefulWidget {
  const DuctLoraFormScreen({
    super.key,
    required this.repository,
    required this.site,
    required this.availableSeries,
    this.existing,
    this.readOnly = false,
    this.isAdmin = false,
  });

  final SurveyRepository repository;
  final Site site;
  final List<String> availableSeries;
  final DuctLora? existing;
  final bool readOnly;

  /// Shows the Admin-only "Fill test data" shortcut — a dev/QA tool that
  /// fills every mandatory field with a placeholder value so the section
  /// passes validation instantly. Never shown to any other role.
  final bool isAdmin;

  @override
  State<DuctLoraFormScreen> createState() => _DuctLoraFormScreenState();
}

class _DuctLoraFormScreenState extends State<DuctLoraFormScreen> {
  late final TextEditingController _rssi;
  late final TextEditingController _cableLength;

  String? _block;
  final Set<String> _seriesServed = {};

  bool? _accessibleForService;
  bool? _powerPointAvailableShielded;
  bool? _separateMcbForSeries;
  bool? _upsPowerSupply;

  /// Captured placement photos (single slot, multiple allowed). Loaded on
  /// edit; reconciled on save.
  final List<PhotoDraft> _placementPhotos = [];

  bool _saving = false;

  // Mandatory-field errors, set on a failed save attempt and cleared on the
  // next one — see _save().
  String? _seriesServedError;
  String? _cableLengthError;
  String? _blockError;
  String? _accessibleForServiceError;
  String? _rssiError;
  String? _powerPointAvailableShieldedError;
  String? _separateMcbForSeriesError;
  String? _upsPowerSupplyError;

  /// Starts false; flips true when the Edit button is tapped. Irrelevant
  /// unless [widget.readOnly] — see [_viewOnly].
  bool _editing = false;

  /// True while fields should be visible but non-interactive: opened
  /// read-only (Approver review) and Edit hasn't been tapped yet. Gates an
  /// [IgnorePointer], not each field's `enabled` — so the fields keep their
  /// normal (not greyed-out) styling in view mode.
  bool get _viewOnly => widget.readOnly && !_editing;

  /// [widget.site.blocks] deduplicated, preserving first-occurrence order.
  /// Block names are free text with no uniqueness enforcement (see
  /// ManageBlocksScreen), so a site can end up with the same label twice.
  /// [DropdownButtonFormField] (which AppDropdownField wraps) requires its
  /// `value` to match *exactly* one item — a duplicate label matches two
  /// and crashes, which is what "Fill test data" hit by setting `_block` to
  /// `widget.site.blocks.first` against a duplicate-containing list. Using
  /// this everywhere the Block dropdown reads or sets a value keeps it
  /// crash-proof regardless of what's actually stored.
  List<String> get _uniqueBlocks => {...widget.site.blocks}.toList();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) _loadPhotos(e.id);

    _rssi = TextEditingController(text: e?.rssiIfTcl?.toString() ?? '');
    _cableLength = TextEditingController(
      text: e?.cableLength?.toString() ?? '',
    );

    _block = (e?.block != null && widget.site.blocks.contains(e!.block))
        ? e.block
        : null;
    _seriesServed.addAll(e?.seriesServed ?? const {});

    _accessibleForService = e?.accessibleForService;
    _powerPointAvailableShielded = e?.powerPointAvailableShielded;
    _separateMcbForSeries = e?.separateMcbForSeries;
    _upsPowerSupply = e?.upsPowerSupply;
  }

  @override
  void dispose() {
    _rssi.dispose();
    _cableLength.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos(String ownerId) async {
    final loaded = await widget.repository.getPhotos(
      PhotoOwner.ductLora,
      ownerId,
    );
    if (!mounted) return;
    setState(() {
      for (final p in loaded) {
        if (p.slot == PhotoSlot.ductLoraPlacement) {
          _placementPhotos.add(
            PhotoDraft(id: p.id, localPath: p.localPath, remotePath: p.remotePath),
          );
        }
      }
    });
  }

  void _onPlacementAdded(String localPath) {
    setState(() => _placementPhotos.add(PhotoDraft(localPath: localPath)));
  }

  void _onPlacementRemoved(int index) {
    setState(() => _placementPhotos.removeAt(index));
  }

  /// Opens the markup screen for an existing photo. The photo keeps its id
  /// (so saving updates the same record/Storage object instead of creating an
  /// orphan); only its local path changes, and remotePath resets to null so
  /// the marked-up version is re-uploaded on the next sync.
  Future<void> _onPlacementEdit(int index) async {
    final draft = _placementPhotos[index];
    final path = draft.localPath;
    if (path == null) return;

    final newPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => PhotoMarkupScreen(imagePath: path)),
    );
    if (newPath == null || !mounted) return;
    setState(() {
      draft.localPath = newPath;
      draft.remotePath = null;
    });
  }

  /// Read-only counterpart to [_onPlacementEdit] — opens the photo
  /// full-screen with no markup/edit capability. Used when the form is
  /// view-only.
  Future<void> _onPlacementView(int index) async {
    final path = _placementPhotos[index].localPath;
    if (path == null) return;
    await openPhotoViewer(context, path);
  }

  List<SurveyPhoto> _photoListFor(String ownerId) {
    final list = <SurveyPhoto>[];
    for (var i = 0; i < _placementPhotos.length; i++) {
      final draft = _placementPhotos[i];
      if (draft.localPath == null) continue;
      list.add(
        SurveyPhoto(
          id: draft.id,
          ownerType: PhotoOwner.ductLora,
          ownerId: ownerId,
          slot: PhotoSlot.ductLoraPlacement,
          position: i,
          localPath: draft.localPath,
          remotePath: draft.remotePath,
        ),
      );
    }
    return list;
  }

  /// Admin-only dev/QA shortcut — fills every mandatory field with a
  /// placeholder value so the section passes validation immediately.
  /// "Series served" can only be filled if the site already has at least
  /// one inlet-point Series to pick from (see [widget.availableSeries]) —
  /// if there isn't one yet, this fills what it can and says so.
  void _fillTestData() {
    setState(() {
      if (_uniqueBlocks.isNotEmpty) _block = _uniqueBlocks.first;
      if (widget.availableSeries.isNotEmpty) {
        _seriesServed
          ..clear()
          ..add(widget.availableSeries.first);
        _seriesServedError = null;
      }
      _accessibleForService = true;
      _rssi.text = '1';
      _powerPointAvailableShielded = true;
      _separateMcbForSeries = false;
      _upsPowerSupply = true;
      _cableLength.text = '1';
      _cableLengthError = null;
      _blockError = null;
      _accessibleForServiceError = null;
      _rssiError = null;
      _powerPointAvailableShieldedError = null;
      _separateMcbForSeriesError = null;
      _upsPowerSupplyError = null;
    });
    final missing = <String>[
      if (widget.availableSeries.isEmpty) 'Series served (add an inlet point with a Series first)',
      if (_uniqueBlocks.isEmpty) 'Block (add a block to the site first)',
    ];
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Other fields filled — ${missing.join(', ')}.')),
      );
    }
  }

  Future<void> _save() async {
    final cableLength = double.tryParse(_cableLength.text.trim());
    final rssi = _rssi.text.trim();

    setState(() {
      _seriesServedError = _seriesServed.isEmpty
          ? 'Select at least one series.'
          : null;
      _cableLengthError = (cableLength == null || cableLength <= 0)
          ? 'Required'
          : null;
      _blockError = _block == null ? 'Required' : null;
      _accessibleForServiceError =
          _accessibleForService == null ? 'Required' : null;
      _rssiError = rssi.isEmpty ? 'Required' : null;
      _powerPointAvailableShieldedError =
          _powerPointAvailableShielded == null ? 'Required' : null;
      _separateMcbForSeriesError =
          _separateMcbForSeries == null ? 'Required' : null;
      _upsPowerSupplyError = _upsPowerSupply == null ? 'Required' : null;
    });
    if (_seriesServedError != null ||
        _cableLengthError != null ||
        _blockError != null ||
        _accessibleForServiceError != null ||
        _rssiError != null ||
        _powerPointAvailableShieldedError != null ||
        _separateMcbForSeriesError != null ||
        _upsPowerSupplyError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the required fields.')),
      );
      return;
    }

    setState(() => _saving = true);

    final draft = DuctLora(
      id: widget.existing?.id ?? '',
      siteId: widget.site.id,
      block: _block,
      seriesServed: Set.unmodifiable(_seriesServed),
      accessibleForService: _accessibleForService,
      rssiIfTcl: double.tryParse(_rssi.text.trim()),
      powerPointAvailableShielded: _powerPointAvailableShielded,
      separateMcbForSeries: _separateMcbForSeries,
      upsPowerSupply: _upsPowerSupply,
      cableLength: cableLength,
    );

    final String ownerId;
    if (widget.existing == null) {
      final stored = await widget.repository.addDuctLora(draft);
      ownerId = stored.id;
    } else {
      await widget.repository.updateDuctLora(draft);
      ownerId = widget.existing!.id;
    }
    await widget.repository.setPhotos(
      PhotoOwner.ductLora,
      ownerId,
      _photoListFor(ownerId),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Duct LoRa unit saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _viewOnly
              ? 'Duct LoRa'
              : widget.existing == null
              ? 'Add Duct LoRa'
              : 'Edit Duct LoRa',
        ),
        actions: [
          if (widget.isAdmin && !_viewOnly)
            IconButton(
              tooltip: 'Fill test data (Admin only)',
              onPressed: _fillTestData,
              icon: const Icon(Icons.auto_fix_high),
            ),
          if (_viewOnly)
            IconButton(
              tooltip: 'Edit',
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IgnorePointer(
            ignoring: _viewOnly,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppDropdownField<String>(
                  label: 'Block *',
                  value: _block,
                  items: _uniqueBlocks,
                  itemLabel: (b) => b,
                  emptyHint:
                      'No blocks on this site — add them via the site first.',
                  onChanged: (v) => setState(() => _block = v),
                  errorText: _blockError,
                ),
                MultiSelectChips<String>(
                  label: 'Series served *',
                  items: widget.availableSeries,
                  itemLabel: (s) => s,
                  selected: _seriesServed,
                  emptyHint:
                      'No series found — add inlet points with a Series first.',
                  helperText: 'Max 20 sensors per unit.',
                  onChanged: (next) => setState(() {
                    _seriesServed
                      ..clear()
                      ..addAll(next);
                  }),
                  errorText: _seriesServedError,
                ),
                YesNoField(
                  label: 'Accessible for service *',
                  value: _accessibleForService,
                  onChanged: (v) => setState(() => _accessibleForService = v),
                  errorText: _accessibleForServiceError,
                ),
                AppTextField(
                  controller: _rssi,
                  label: 'RSSI value (if TCL) *',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')),
                  ],
                  errorText: _rssiError,
                ),
                YesNoField(
                  label: 'Power point available / shielded *',
                  value: _powerPointAvailableShielded,
                  onChanged: (v) =>
                      setState(() => _powerPointAvailableShielded = v),
                  errorText: _powerPointAvailableShieldedError,
                ),
                YesNoField(
                  label: 'Separate MCB for series (max 4) *',
                  value: _separateMcbForSeries,
                  onChanged: (v) => setState(() => _separateMcbForSeries = v),
                  errorText: _separateMcbForSeriesError,
                ),
                YesNoField(
                  label: 'UPS power supply *',
                  value: _upsPowerSupply,
                  onChanged: (v) => setState(() => _upsPowerSupply = v),
                  errorText: _upsPowerSupplyError,
                ),
                AppTextField(
                  controller: _cableLength,
                  label: 'Duct LoRa cable length (pending confirmation) *',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  errorText: _cableLengthError,
                ),
              ],
            ),
          ),

          const FormSectionLabel('Photos'),
          MultiPhotoCaptureField(
            label: 'Duct LoRa location / placement',
            photos: [
              for (final d in _placementPhotos)
                if (d.localPath != null)
                  PhotoView(d.localPath!, uploaded: d.uploaded),
            ],
            onAdded: _onPlacementAdded,
            onRemoved: _onPlacementRemoved,
            onEdit: _viewOnly ? null : _onPlacementEdit,
            onView: _onPlacementView,
            readOnly: _viewOnly,
          ),

          if (!_viewOnly) ...[
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
              label: const Text('Save Duct LoRa unit'),
            ),
          ],
        ],
      ),
    );
  }
}
