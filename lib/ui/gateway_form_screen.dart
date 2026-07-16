import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/gateway.dart';
import '../models/site.dart';
import '../models/survey_options.dart';
import '../models/survey_photo.dart';
import 'photo_markup_screen.dart';
import 'widgets/form_fields.dart';
import 'widgets/photo_capture_field.dart';

/// Add or edit a single gateway. Placement, blocks covered (at least one),
/// quantity, uplink type, and SIM coverage are mandatory (see `_save`);
/// every other field is optional (partial saves).
class GatewayFormScreen extends StatefulWidget {
  const GatewayFormScreen({
    super.key,
    required this.repository,
    required this.site,
    this.existing,
    this.readOnly = false,
    this.isAdmin = false,
  });

  final SurveyRepository repository;
  final Site site;
  final Gateway? existing;
  final bool readOnly;

  /// Shows the Admin-only "Fill test data" shortcut — a dev/QA tool that
  /// fills every mandatory field with a placeholder value so the section
  /// passes validation instantly. Never shown to any other role.
  final bool isAdmin;

  @override
  State<GatewayFormScreen> createState() => _GatewayFormScreenState();
}

class _GatewayFormScreenState extends State<GatewayFormScreen> {
  late final TextEditingController _locationDescription;
  late final TextEditingController _quantity;
  late final TextEditingController _wifiInterferenceDetails;
  late final TextEditingController _mountingHardware;

  GatewayPlacement? _placement;
  final Set<String> _blocksCovered = {};
  UplinkType? _uplinkType;
  bool? _wifiInterferenceCheck;
  SimCoverage? _simCoverage;
  bool? _uninterruptedPowerSource;

  /// Captured gateway-location photos (single slot, multiple allowed). Loaded
  /// on edit; reconciled on save.
  final List<PhotoDraft> _locationPhotos = [];

  bool _saving = false;

  // Mandatory-field errors, set on a failed save attempt and cleared on the
  // next one — see _save().
  String? _placementError;
  String? _blocksCoveredError;
  String? _quantityError;
  String? _uplinkTypeError;
  String? _simCoverageError;
  String? _locationDescriptionError;
  String? _wifiInterferenceCheckError;
  String? _wifiInterferenceDetailsError;
  String? _uninterruptedPowerSourceError;

  /// Starts false; flips true when the Edit button is tapped. Irrelevant
  /// unless [widget.readOnly] — see [_viewOnly].
  bool _editing = false;

  /// True while fields should be visible but non-interactive: opened
  /// read-only (Approver review) and Edit hasn't been tapped yet. Gates an
  /// [IgnorePointer], not each field's `enabled` — so the fields keep their
  /// normal (not greyed-out) styling in view mode.
  bool get _viewOnly => widget.readOnly && !_editing;

  bool get _usesRouter =>
      _uplinkType == UplinkType.router || _uplinkType == UplinkType.both;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) _loadPhotos(e.id);

    _locationDescription = TextEditingController(
      text: e?.locationDescription ?? '',
    );
    _quantity = TextEditingController(text: e?.quantity?.toString() ?? '');
    _wifiInterferenceDetails = TextEditingController(
      text: e?.wifiInterferenceDetails ?? '',
    );
    _mountingHardware = TextEditingController(
      text: e?.mountingHardwareNeeded ?? '',
    );

    _placement = e?.placement;
    _blocksCovered.addAll(
      (e?.blocksCovered ?? const {}).where(widget.site.blocks.contains),
    );
    _uplinkType = e?.uplinkType;
    _wifiInterferenceCheck = e?.wifiInterferenceCheck;
    _simCoverage = e?.simCoverage;
    _uninterruptedPowerSource = e?.uninterruptedPowerSource;
  }

  @override
  void dispose() {
    _locationDescription.dispose();
    _quantity.dispose();
    _wifiInterferenceDetails.dispose();
    _mountingHardware.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos(String ownerId) async {
    final loaded = await widget.repository.getPhotos(
      PhotoOwner.gateway,
      ownerId,
    );
    if (!mounted) return;
    setState(() {
      for (final p in loaded) {
        if (p.slot == PhotoSlot.gatewayLocation) {
          _locationPhotos.add(
            PhotoDraft(id: p.id, localPath: p.localPath, remotePath: p.remotePath),
          );
        }
      }
    });
  }

  void _onLocationAdded(String localPath) {
    setState(() => _locationPhotos.add(PhotoDraft(localPath: localPath)));
  }

  void _onLocationRemoved(int index) {
    setState(() => _locationPhotos.removeAt(index));
  }

  /// Opens the markup screen for an existing photo. The photo keeps its id
  /// (so saving updates the same record/Storage object instead of creating an
  /// orphan); only its local path changes, and remotePath resets to null so
  /// the marked-up version is re-uploaded on the next sync.
  Future<void> _onLocationEdit(int index) async {
    final draft = _locationPhotos[index];
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

  /// Read-only counterpart to [_onLocationEdit] — opens the photo
  /// full-screen with no markup/edit capability. Used when the form is
  /// view-only.
  Future<void> _onLocationView(int index) async {
    final path = _locationPhotos[index].localPath;
    if (path == null) return;
    await openPhotoViewer(context, path);
  }

  List<SurveyPhoto> _photoListFor(String ownerId) {
    final list = <SurveyPhoto>[];
    for (var i = 0; i < _locationPhotos.length; i++) {
      final draft = _locationPhotos[i];
      if (draft.localPath == null) continue;
      list.add(
        SurveyPhoto(
          id: draft.id,
          ownerType: PhotoOwner.gateway,
          ownerId: ownerId,
          slot: PhotoSlot.gatewayLocation,
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
  /// "Blocks covered" can only be filled if the site already has at least
  /// one block — if there isn't one yet, this fills what it can and says so.
  void _fillTestData() {
    setState(() {
      _placement = GatewayPlacement.values.first;
      _locationDescription.text = 'Test location';
      if (widget.site.blocks.isNotEmpty) {
        _blocksCovered
          ..clear()
          ..add(widget.site.blocks.first);
        _blocksCoveredError = null;
      }
      _quantity.text = '1';
      _uplinkType = UplinkType.values.first;
      if (_usesRouter) {
        _wifiInterferenceCheck = false;
      }
      _simCoverage = SimCoverage.values.first;
      _uninterruptedPowerSource = true;
      _placementError = null;
      _quantityError = null;
      _uplinkTypeError = null;
      _simCoverageError = null;
      _locationDescriptionError = null;
      _wifiInterferenceCheckError = null;
      _wifiInterferenceDetailsError = null;
      _uninterruptedPowerSourceError = null;
    });
    if (widget.site.blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Other fields filled — add a block to the site first to '
                'also fill Blocks covered.',
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    final quantity = int.tryParse(_quantity.text.trim());
    final locationDescription = _locationDescription.text.trim();
    final wifiInterferenceDetails = _wifiInterferenceDetails.text.trim();

    setState(() {
      _placementError = _placement == null ? 'Required' : null;
      _blocksCoveredError = _blocksCovered.isEmpty
          ? 'Select at least one block.'
          : null;
      _quantityError = (quantity == null || quantity <= 0) ? 'Required' : null;
      _uplinkTypeError = _uplinkType == null ? 'Required' : null;
      _simCoverageError = _simCoverage == null ? 'Required' : null;
      _locationDescriptionError =
          locationDescription.isEmpty ? 'Required' : null;
      _wifiInterferenceCheckError =
          (_usesRouter && _wifiInterferenceCheck == null) ? 'Required' : null;
      _wifiInterferenceDetailsError =
          (_usesRouter &&
              _wifiInterferenceCheck == true &&
              wifiInterferenceDetails.isEmpty)
          ? 'Required'
          : null;
      _uninterruptedPowerSourceError =
          _uninterruptedPowerSource == null ? 'Required' : null;
    });
    if (_placementError != null ||
        _blocksCoveredError != null ||
        _quantityError != null ||
        _uplinkTypeError != null ||
        _simCoverageError != null ||
        _locationDescriptionError != null ||
        _wifiInterferenceCheckError != null ||
        _wifiInterferenceDetailsError != null ||
        _uninterruptedPowerSourceError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the required fields.')),
      );
      return;
    }

    setState(() => _saving = true);

    // Drop the WiFi answer if the uplink no longer involves a router.
    final wifiCheck = _usesRouter ? _wifiInterferenceCheck : null;
    final wifiDetails = (_usesRouter && wifiCheck == true)
        ? _wifiInterferenceDetails.text.trim()
        : '';

    final draft = Gateway(
      id: widget.existing?.id ?? '',
      siteId: widget.site.id,
      placement: _placement,
      locationDescription: _locationDescription.text.trim(),
      blocksCovered: Set.unmodifiable(_blocksCovered),
      quantity: quantity,
      uplinkType: _uplinkType,
      wifiInterferenceCheck: wifiCheck,
      wifiInterferenceDetails: wifiDetails,
      simCoverage: _simCoverage,
      uninterruptedPowerSource: _uninterruptedPowerSource,
      mountingHardwareNeeded: _mountingHardware.text.trim(),
    );

    final String ownerId;
    if (widget.existing == null) {
      final stored = await widget.repository.addGateway(draft);
      ownerId = stored.id;
    } else {
      await widget.repository.updateGateway(draft);
      ownerId = widget.existing!.id;
    }
    await widget.repository.setPhotos(
      PhotoOwner.gateway,
      ownerId,
      _photoListFor(ownerId),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gateway saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _viewOnly
              ? 'Gateway'
              : widget.existing == null
              ? 'Add gateway'
              : 'Edit gateway',
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
                AppDropdownField<GatewayPlacement>(
                  label: 'Indoor / outdoor *',
                  value: _placement,
                  items: GatewayPlacement.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _placement = v),
                  errorText: _placementError,
                ),
                AppTextField(
                  controller: _locationDescription,
                  label: 'Location description *',
                  maxLines: 2,
                  errorText: _locationDescriptionError,
                ),
                MultiSelectChips<String>(
                  label: 'Blocks covered *',
                  items: widget.site.blocks,
                  itemLabel: (b) => b,
                  selected: _blocksCovered,
                  emptyHint:
                      'No blocks on this site — add them via the site first.',
                  onChanged: (next) => setState(() {
                    _blocksCovered
                      ..clear()
                      ..addAll(next);
                  }),
                  errorText: _blocksCoveredError,
                ),
                AppTextField(
                  controller: _quantity,
                  label: 'Quantity *',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  errorText: _quantityError,
                ),
                AppDropdownField<UplinkType>(
                  label: 'Uplink type *',
                  value: _uplinkType,
                  items: UplinkType.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _uplinkType = v),
                  errorText: _uplinkTypeError,
                ),
                if (_usesRouter) ...[
                  YesNoField(
                    label: 'WiFi interference check *',
                    value: _wifiInterferenceCheck,
                    onChanged: (v) =>
                        setState(() => _wifiInterferenceCheck = v),
                    errorText: _wifiInterferenceCheckError,
                  ),
                  if (_wifiInterferenceCheck == true)
                    AppTextField(
                      controller: _wifiInterferenceDetails,
                      label: 'WiFi interference details *',
                      maxLines: 2,
                      errorText: _wifiInterferenceDetailsError,
                    ),
                ],
                AppDropdownField<SimCoverage>(
                  label: 'SIM coverage *',
                  value: _simCoverage,
                  items: SimCoverage.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _simCoverage = v),
                  errorText: _simCoverageError,
                ),
                YesNoField(
                  label: 'Uninterrupted power source *',
                  value: _uninterruptedPowerSource,
                  onChanged: (v) =>
                      setState(() => _uninterruptedPowerSource = v),
                  errorText: _uninterruptedPowerSourceError,
                ),
                AppTextField(
                  controller: _mountingHardware,
                  label: 'Mounting hardware needed',
                  maxLines: 2,
                ),
              ],
            ),
          ),

          const FormSectionLabel('Photos'),
          MultiPhotoCaptureField(
            label: 'Gateway location',
            photos: [
              for (final d in _locationPhotos)
                if (d.localPath != null)
                  PhotoView(d.localPath!, uploaded: d.uploaded),
            ],
            onAdded: _onLocationAdded,
            onRemoved: _onLocationRemoved,
            onEdit: _viewOnly ? null : _onLocationEdit,
            onView: _onLocationView,
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
              label: const Text('Save gateway'),
            ),
          ],
        ],
      ),
    );
  }
}
