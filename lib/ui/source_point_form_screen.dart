import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_options.dart';
import '../models/survey_photo.dart';
import 'photo_markup_screen.dart';
import 'widgets/form_fields.dart';
import 'widgets/photo_capture_field.dart';

/// Add or edit a single source point. Apartment, sensor size, sensor type,
/// and qty are mandatory (see `_save`); every other field is optional
/// (partial saves).
class SourcePointFormScreen extends StatefulWidget {
  const SourcePointFormScreen({
    super.key,
    required this.repository,
    required this.site,
    this.existing,
    this.duplicateFrom,
    this.readOnly = false,
    this.isAdmin = false,
  });

  final SurveyRepository repository;
  final Site site;
  final SourcePoint? existing;

  /// Shows the Admin-only "Fill test data" shortcut — a dev/QA tool that
  /// fills every mandatory field with a placeholder value so the section
  /// passes validation instantly. Never shown to any other role.
  final bool isAdmin;

  /// Pre-fills the form from this record — via [SourcePoint.copyAsDuplicate]
  /// — while still saving as a brand new record. Mutually exclusive with
  /// [existing]; ignored if both are set. Unlike [existing], never triggers
  /// a photo load.
  final SourcePoint? duplicateFrom;

  final bool readOnly;

  @override
  State<SourcePointFormScreen> createState() => _SourcePointFormScreenState();
}

class _SourcePointFormScreenState extends State<SourcePointFormScreen> {
  late final TextEditingController _apartment;
  final _apartmentFocusNode = FocusNode();
  late final TextEditingController _inletDescription;
  late final TextEditingController _qty;
  late final TextEditingController _reworkDetails;
  late final TextEditingController _reducerSpecDetails;
  late final TextEditingController _pressure;

  String? _block;
  SensorSize? _sensorSize;
  SensorOd? _sensorOd;
  PipeSize? _pipeSize;
  PipeType? _pipeType;
  SensorType? _sensorType;
  FlowDirection? _flowDirection;

  bool? _rework;
  bool? _clearance10x;
  bool? _pipeFull;
  bool? _valveDownstream;
  bool? _reducerSpec;
  bool? _downstreamOutletAbovePipeFig1;
  bool? _airVentNeededFig2;
  bool? _reverseFlow;
  bool? _distanceFromMotorPumpFig3;
  bool? _noFlexiblePipeWithin20x;
  bool? _strainerScreenFilter;
  bool? _chamberInstallation;
  bool? _antennaRequired;
  bool? _transmittingPartOpenToAir;
  bool? _nrvFeasibility;

  /// Captured photos, keyed by slot (each slot allows multiple). Loaded from
  /// the repository on edit; reconciled back via setPhotos on save.
  final Map<String, List<PhotoDraft>> _photos = {};

  bool _saving = false;

  // Mandatory-field errors, set on a failed save attempt and cleared on the
  // next one — see _save().
  String? _apartmentError;
  String? _sensorSizeError;
  String? _sensorTypeError;
  String? _qtyError;
  String? _blockError;
  String? _sensorOdError;
  String? _pipeSizeError;
  String? _pipeTypeError;
  String? _reworkError;
  String? _reworkDetailsError;
  String? _flowDirectionError;
  String? _clearance10xError;
  String? _pipeFullError;
  String? _valveDownstreamError;
  String? _reducerSpecError;
  String? _reducerSpecDetailsError;
  String? _downstreamOutletAbovePipeFig1Error;
  String? _airVentNeededFig2Error;
  String? _reverseFlowError;
  String? _distanceFromMotorPumpFig3Error;
  String? _noFlexiblePipeWithin20xError;
  String? _pressureError;
  String? _strainerScreenFilterError;
  String? _chamberInstallationError;
  String? _antennaRequiredError;
  String? _transmittingPartOpenToAirError;
  String? _nrvFeasibilityError;

  /// Starts false; flips true when the Edit button is tapped. Irrelevant
  /// unless [widget.readOnly] — see [_viewOnly].
  bool _editing = false;

  /// True while fields should be visible but non-interactive: opened
  /// read-only (Approver review) and Edit hasn't been tapped yet. Gates an
  /// [IgnorePointer], not each field's `enabled` — so the fields keep their
  /// normal (not greyed-out) styling in view mode.
  bool get _viewOnly => widget.readOnly && !_editing;

  @override
  void initState() {
    super.initState();
    // duplicateFrom only supplies prefill values (see SourcePoint.
    // copyAsDuplicate for exactly what carries over) — existing is what
    // drives photo loading and the save-path decision (add vs update)
    // further down.
    final e = widget.existing ?? widget.duplicateFrom;
    if (widget.existing != null) _loadPhotos(widget.existing!.id);

    _apartment = TextEditingController(text: e?.apartment ?? '');
    _inletDescription = TextEditingController(text: e?.inletDescription ?? '');
    _qty = TextEditingController(text: e?.qty?.toString() ?? '');
    _reworkDetails = TextEditingController(text: e?.reworkDetails ?? '');
    _reducerSpecDetails = TextEditingController(
      text: e?.reducerSpecDetails ?? '',
    );
    _pressure = TextEditingController(
      text: e?.maxAndContinuousPressureBar?.toString() ?? '',
    );

    // Keep the block only if it still exists in the site's block list.
    _block = (e?.block != null && widget.site.blocks.contains(e!.block))
        ? e.block
        : null;
    _sensorSize = e?.sensorSize;
    _sensorOd = e?.sensorOd;
    _pipeSize = e?.pipeSize;
    _pipeType = e?.pipeType;
    _sensorType = e?.sensorType;
    _flowDirection = e?.flowDirection;

    _rework = e?.rework;
    _clearance10x = e?.clearance10x;
    _pipeFull = e?.pipeFull;
    _valveDownstream = e?.valveDownstream;
    _reducerSpec = e?.reducerSpec;
    _downstreamOutletAbovePipeFig1 = e?.downstreamOutletAbovePipeFig1;
    _airVentNeededFig2 = e?.airVentNeededFig2;
    _reverseFlow = e?.reverseFlow;
    _distanceFromMotorPumpFig3 = e?.distanceFromMotorPumpFig3;
    _noFlexiblePipeWithin20x = e?.noFlexiblePipeWithin20x;
    _strainerScreenFilter = e?.strainerScreenFilter;
    _chamberInstallation = e?.chamberInstallation;
    _antennaRequired = e?.antennaRequired;
    _transmittingPartOpenToAir = e?.transmittingPartOpenToAir;
    _nrvFeasibility = e?.nrvFeasibility;

    // Duplicating pre-fills Apartment (see SourcePoint.copyAsDuplicate) —
    // auto-focus and select it so the pre-filled value is the first thing
    // the user reviews, a nudge to check/edit it rather than a block.
    if (widget.duplicateFrom != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _apartmentFocusNode.requestFocus();
        _apartment.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _apartment.text.length,
        );
      });
    }
  }

  @override
  void dispose() {
    _apartment.dispose();
    _apartmentFocusNode.dispose();
    _inletDescription.dispose();
    _qty.dispose();
    _reworkDetails.dispose();
    _reducerSpecDetails.dispose();
    _pressure.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos(String ownerId) async {
    final loaded = await widget.repository.getPhotos(
      PhotoOwner.sourcePoint,
      ownerId,
    );
    if (!mounted) return;
    setState(() {
      for (final p in loaded) {
        (_photos[p.slot] ??= []).add(
          PhotoDraft(id: p.id, localPath: p.localPath, remotePath: p.remotePath),
        );
      }
    });
  }

  void _onPhotoAdded(String slot, String localPath) {
    setState(() => (_photos[slot] ??= []).add(PhotoDraft(localPath: localPath)));
  }

  void _onPhotoRemoved(String slot, int index) {
    setState(() => _photos[slot]?.removeAt(index));
  }

  /// Opens the markup screen for an existing photo. The photo keeps its id
  /// (so saving updates the same record/Storage object instead of creating an
  /// orphan); only its local path changes, and remotePath resets to null so
  /// the marked-up version is re-uploaded on the next sync.
  Future<void> _onPhotoEdit(String slot, int index) async {
    final drafts = _photos[slot];
    if (drafts == null || index >= drafts.length) return;
    final draft = drafts[index];
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

  /// Read-only counterpart to [_onPhotoEdit] — opens the photo full-screen
  /// with no markup/edit capability. Used when the form is view-only.
  Future<void> _onPhotoView(String slot, int index) async {
    final drafts = _photos[slot];
    if (drafts == null || index >= drafts.length) return;
    final path = drafts[index].localPath;
    if (path == null) return;
    await openPhotoViewer(context, path);
  }

  List<SurveyPhoto> _photoListFor(String ownerId) {
    final list = <SurveyPhoto>[];
    for (final entry in _photos.entries) {
      final drafts = entry.value;
      for (var i = 0; i < drafts.length; i++) {
        final draft = drafts[i];
        if (draft.localPath == null) continue;
        list.add(
          SurveyPhoto(
            id: draft.id,
            ownerType: PhotoOwner.sourcePoint,
            ownerId: ownerId,
            slot: entry.key,
            position: i,
            localPath: draft.localPath,
            remotePath: draft.remotePath,
          ),
        );
      }
    }
    return list;
  }

  /// Builds the multi-photo capture widget for one slot.
  Widget _photoField(String slot, String label) {
    final drafts = _photos[slot] ?? const <PhotoDraft>[];
    return MultiPhotoCaptureField(
      label: label,
      photos: [
        for (final d in drafts)
          if (d.localPath != null) PhotoView(d.localPath!, uploaded: d.uploaded),
      ],
      onAdded: (p) => _onPhotoAdded(slot, p),
      onRemoved: (i) => _onPhotoRemoved(slot, i),
      onEdit: _viewOnly ? null : (i) => _onPhotoEdit(slot, i),
      onView: (i) => _onPhotoView(slot, i),
      readOnly: _viewOnly,
    );
  }

  /// Admin-only dev/QA shortcut — fills every mandatory field with a
  /// placeholder value so the section passes validation immediately. Never
  /// touches optional/free-text fields (Inlet description). Block can only
  /// be filled if the site already has at least one block.
  void _fillTestData() {
    setState(() {
      _apartment.text = 'Test Apartment';
      if (widget.site.blocks.isNotEmpty) _block = widget.site.blocks.first;
      _sensorSize = SensorSize.values.first;
      _sensorOd = SensorOd.values.first;
      _pipeSize = PipeSize.values.first;
      _pipeType = PipeType.values.first;
      _qty.text = '1';
      _sensorType = SensorType.values.first;
      _rework = false;
      _flowDirection = FlowDirection.values.first;
      _clearance10x = true;
      _pipeFull = true;
      _valveDownstream = false;
      _reducerSpec = false;
      _downstreamOutletAbovePipeFig1 = true;
      _airVentNeededFig2 = false;
      _reverseFlow = false;
      _distanceFromMotorPumpFig3 = true;
      _noFlexiblePipeWithin20x = true;
      _pressure.text = '1';
      _strainerScreenFilter = true;
      _chamberInstallation = true;
      if (_sensorType == SensorType.wireless) {
        _antennaRequired = true;
        _transmittingPartOpenToAir = false;
        _nrvFeasibility = true;
      }
      _apartmentError = null;
      _sensorSizeError = null;
      _sensorTypeError = null;
      _qtyError = null;
      _blockError = null;
      _sensorOdError = null;
      _pipeSizeError = null;
      _pipeTypeError = null;
      _reworkError = null;
      _flowDirectionError = null;
      _clearance10xError = null;
      _pipeFullError = null;
      _valveDownstreamError = null;
      _reducerSpecError = null;
      _downstreamOutletAbovePipeFig1Error = null;
      _airVentNeededFig2Error = null;
      _reverseFlowError = null;
      _distanceFromMotorPumpFig3Error = null;
      _noFlexiblePipeWithin20xError = null;
      _pressureError = null;
      _strainerScreenFilterError = null;
      _chamberInstallationError = null;
      _antennaRequiredError = null;
      _transmittingPartOpenToAirError = null;
      _nrvFeasibilityError = null;
    });
    if (widget.site.blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Other fields filled — add a block to the site first to '
                'also fill Block.',
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    final apartment = _apartment.text.trim();
    final qty = int.tryParse(_qty.text.trim());
    final pressure = _pressure.text.trim();
    final isWireless = _sensorType == SensorType.wireless;

    setState(() {
      _apartmentError = apartment.isEmpty ? 'Required' : null;
      _sensorSizeError = _sensorSize == null ? 'Required' : null;
      _sensorTypeError = _sensorType == null ? 'Required' : null;
      _qtyError = (qty == null || qty <= 0) ? 'Required' : null;
      _blockError = _block == null ? 'Required' : null;
      _sensorOdError = _sensorOd == null ? 'Required' : null;
      _pipeSizeError = _pipeSize == null ? 'Required' : null;
      _pipeTypeError = _pipeType == null ? 'Required' : null;
      _reworkError = _rework == null ? 'Required' : null;
      _reworkDetailsError =
          (_rework == true && _reworkDetails.text.trim().isEmpty)
          ? 'Required'
          : null;
      _flowDirectionError = _flowDirection == null ? 'Required' : null;
      _clearance10xError = _clearance10x == null ? 'Required' : null;
      _pipeFullError = _pipeFull == null ? 'Required' : null;
      _valveDownstreamError = _valveDownstream == null ? 'Required' : null;
      _reducerSpecError = _reducerSpec == null ? 'Required' : null;
      _reducerSpecDetailsError =
          (_reducerSpec == true && _reducerSpecDetails.text.trim().isEmpty)
          ? 'Required'
          : null;
      _downstreamOutletAbovePipeFig1Error =
          _downstreamOutletAbovePipeFig1 == null ? 'Required' : null;
      _airVentNeededFig2Error = _airVentNeededFig2 == null
          ? 'Required'
          : null;
      _reverseFlowError = _reverseFlow == null ? 'Required' : null;
      _distanceFromMotorPumpFig3Error = _distanceFromMotorPumpFig3 == null
          ? 'Required'
          : null;
      _noFlexiblePipeWithin20xError = _noFlexiblePipeWithin20x == null
          ? 'Required'
          : null;
      _pressureError = pressure.isEmpty ? 'Required' : null;
      _strainerScreenFilterError = _strainerScreenFilter == null
          ? 'Required'
          : null;
      _chamberInstallationError = _chamberInstallation == null
          ? 'Required'
          : null;
      _antennaRequiredError = (isWireless && _antennaRequired == null)
          ? 'Required'
          : null;
      _transmittingPartOpenToAirError =
          (isWireless && _transmittingPartOpenToAir == null)
          ? 'Required'
          : null;
      _nrvFeasibilityError = (isWireless && _nrvFeasibility == null)
          ? 'Required'
          : null;
    });
    if (_apartmentError != null ||
        _sensorSizeError != null ||
        _sensorTypeError != null ||
        _qtyError != null ||
        _blockError != null ||
        _sensorOdError != null ||
        _pipeSizeError != null ||
        _pipeTypeError != null ||
        _reworkError != null ||
        _reworkDetailsError != null ||
        _flowDirectionError != null ||
        _clearance10xError != null ||
        _pipeFullError != null ||
        _valveDownstreamError != null ||
        _reducerSpecError != null ||
        _reducerSpecDetailsError != null ||
        _downstreamOutletAbovePipeFig1Error != null ||
        _airVentNeededFig2Error != null ||
        _reverseFlowError != null ||
        _distanceFromMotorPumpFig3Error != null ||
        _noFlexiblePipeWithin20xError != null ||
        _pressureError != null ||
        _strainerScreenFilterError != null ||
        _chamberInstallationError != null ||
        _antennaRequiredError != null ||
        _transmittingPartOpenToAirError != null ||
        _nrvFeasibilityError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the required fields.')),
      );
      return;
    }

    setState(() => _saving = true);

    final draft = SourcePoint(
      id: widget.existing?.id ?? '',
      siteId: widget.site.id,
      block: _block,
      apartment: apartment,
      inletDescription: _inletDescription.text.trim(),
      sensorSize: _sensorSize,
      sensorOd: _sensorOd,
      pipeSize: _pipeSize,
      pipeType: _pipeType,
      qty: qty,
      sensorType: _sensorType,
      rework: _rework,
      reworkDetails: _reworkDetails.text.trim(),
      flowDirection: _flowDirection,
      clearance10x: _clearance10x,
      pipeFull: _pipeFull,
      valveDownstream: _valveDownstream,
      reducerSpec: _reducerSpec,
      reducerSpecDetails: _reducerSpecDetails.text.trim(),
      downstreamOutletAbovePipeFig1: _downstreamOutletAbovePipeFig1,
      airVentNeededFig2: _airVentNeededFig2,
      reverseFlow: _reverseFlow,
      distanceFromMotorPumpFig3: _distanceFromMotorPumpFig3,
      noFlexiblePipeWithin20x: _noFlexiblePipeWithin20x,
      maxAndContinuousPressureBar: double.tryParse(_pressure.text.trim()),
      strainerScreenFilter: _strainerScreenFilter,
      chamberInstallation: _chamberInstallation,
      antennaRequired: _antennaRequired,
      transmittingPartOpenToAir: _transmittingPartOpenToAir,
      nrvFeasibility: _nrvFeasibility,
    );

    final String ownerId;
    if (widget.existing == null) {
      final stored = await widget.repository.addSourcePoint(draft);
      ownerId = stored.id;
    } else {
      await widget.repository.updateSourcePoint(draft);
      ownerId = widget.existing!.id;
    }
    await widget.repository.setPhotos(
      PhotoOwner.sourcePoint,
      ownerId,
      _photoListFor(ownerId),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Source point saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isWireless = _sensorType == SensorType.wireless;
    final isWired = _sensorType == SensorType.wired;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _viewOnly
              ? 'Source point'
              : widget.existing == null
              ? 'Add source point'
              : 'Edit source point',
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
                  items: widget.site.blocks,
                  itemLabel: (b) => b,
                  emptyHint:
                      'No blocks on this site — add them via the site first.',
                  onChanged: (v) => setState(() => _block = v),
                  errorText: _blockError,
                ),
                AppTextField(
                  controller: _apartment,
                  focusNode: _apartmentFocusNode,
                  label: 'Apartment *',
                  errorText: _apartmentError,
                ),
                AppTextField(
                  controller: _inletDescription,
                  label: 'Inlet description',
                  maxLines: 2,
                ),

                AppDropdownField<SensorSize>(
                  label: 'Sensor size *',
                  value: _sensorSize,
                  items: SensorSize.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _sensorSize = v),
                  errorText: _sensorSizeError,
                ),
                AppDropdownField<SensorOd>(
                  label: 'Sensor OD *',
                  value: _sensorOd,
                  items: SensorOd.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _sensorOd = v),
                  errorText: _sensorOdError,
                ),
                AppDropdownField<PipeSize>(
                  label: 'Pipe size *',
                  value: _pipeSize,
                  items: PipeSize.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _pipeSize = v),
                  errorText: _pipeSizeError,
                ),
                AppDropdownField<PipeType>(
                  label: 'Pipe type *',
                  value: _pipeType,
                  items: PipeType.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _pipeType = v),
                  errorText: _pipeTypeError,
                ),
                AppTextField(
                  controller: _qty,
                  label: 'Qty *',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  errorText: _qtyError,
                ),
                AppDropdownField<SensorType>(
                  label: 'Sensor type *',
                  value: _sensorType,
                  items: SensorType.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _sensorType = v),
                  errorText: _sensorTypeError,
                ),

                YesNoField(
                  label: 'Rework *',
                  value: _rework,
                  onChanged: (v) => setState(() => _rework = v),
                  errorText: _reworkError,
                ),
                if (_rework == true)
                  AppTextField(
                    controller: _reworkDetails,
                    label: 'Rework details *',
                    maxLines: 2,
                    errorText: _reworkDetailsError,
                  ),

                AppDropdownField<FlowDirection>(
                  label: 'Flow direction *',
                  value: _flowDirection,
                  items: FlowDirection.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _flowDirection = v),
                  errorText: _flowDirectionError,
                ),

                YesNoField(
                  label: '10X clearance *',
                  value: _clearance10x,
                  onChanged: (v) => setState(() => _clearance10x = v),
                  errorText: _clearance10xError,
                ),
                YesNoField(
                  label: 'Pipe full *',
                  value: _pipeFull,
                  onChanged: (v) => setState(() => _pipeFull = v),
                  errorText: _pipeFullError,
                ),
                YesNoField(
                  label: 'Valve downstream *',
                  value: _valveDownstream,
                  onChanged: (v) => setState(() => _valveDownstream = v),
                  errorText: _valveDownstreamError,
                ),

                YesNoField(
                  label: 'Reducer spec *',
                  value: _reducerSpec,
                  onChanged: (v) => setState(() => _reducerSpec = v),
                  errorText: _reducerSpecError,
                ),
                if (_reducerSpec == true)
                  AppTextField(
                    controller: _reducerSpecDetails,
                    label: 'Reducer spec details *',
                    maxLines: 2,
                    errorText: _reducerSpecDetailsError,
                  ),

                YesNoField(
                  label: 'Downstream outlet above pipe (FIG1) *',
                  labelTrailing: const ReferenceLink(
                    asset: 'assets/figures/FIG1_pipe_full_outlet_above.png',
                    title: 'FIG1',
                  ),
                  value: _downstreamOutletAbovePipeFig1,
                  onChanged: (v) =>
                      setState(() => _downstreamOutletAbovePipeFig1 = v),
                  errorText: _downstreamOutletAbovePipeFig1Error,
                ),
                YesNoField(
                  label: 'Air vent needed (FIG2) *',
                  labelTrailing: const ReferenceLink(
                    asset: 'assets/figures/FIG2_air_vent.png',
                    title: 'FIG2',
                  ),
                  value: _airVentNeededFig2,
                  onChanged: (v) => setState(() => _airVentNeededFig2 = v),
                  errorText: _airVentNeededFig2Error,
                ),
                YesNoField(
                  label: 'Reverse flow *',
                  value: _reverseFlow,
                  onChanged: (v) => setState(() => _reverseFlow = v),
                  errorText: _reverseFlowError,
                ),
                YesNoField(
                  label: 'Distance from motor/pump (FIG3) *',
                  labelTrailing: const ReferenceLink(
                    asset:
                        'assets/figures/FIG3_distance_motor_reducer_valve.png',
                    title: 'FIG3',
                  ),
                  value: _distanceFromMotorPumpFig3,
                  onChanged: (v) =>
                      setState(() => _distanceFromMotorPumpFig3 = v),
                  errorText: _distanceFromMotorPumpFig3Error,
                ),
                YesNoField(
                  label: 'No flexible pipe within 20X *',
                  value: _noFlexiblePipeWithin20x,
                  onChanged: (v) =>
                      setState(() => _noFlexiblePipeWithin20x = v),
                  errorText: _noFlexiblePipeWithin20xError,
                ),

                AppTextField(
                  controller: _pressure,
                  label: 'Max & continuous pressure (bar) *',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  errorText: _pressureError,
                ),

                YesNoField(
                  label: 'Strainer / screen filter *',
                  value: _strainerScreenFilter,
                  onChanged: (v) => setState(() => _strainerScreenFilter = v),
                  errorText: _strainerScreenFilterError,
                ),
                YesNoField(
                  label: 'Chamber installation *',
                  value: _chamberInstallation,
                  onChanged: (v) => setState(() => _chamberInstallation = v),
                  errorText: _chamberInstallationError,
                ),

                if (isWireless) ...[
                  const FormSectionLabel('Wireless'),
                  YesNoField(
                    label: 'Antenna required *',
                    value: _antennaRequired,
                    onChanged: (v) => setState(() => _antennaRequired = v),
                    errorText: _antennaRequiredError,
                  ),
                  YesNoField(
                    label: 'Transmitting part open to air *',
                    value: _transmittingPartOpenToAir,
                    onChanged: (v) =>
                        setState(() => _transmittingPartOpenToAir = v),
                    errorText: _transmittingPartOpenToAirError,
                  ),
                  YesNoField(
                    label: 'NRV feasibility *',
                    value: _nrvFeasibility,
                    onChanged: (v) => setState(() => _nrvFeasibility = v),
                    errorText: _nrvFeasibilityError,
                  ),
                ],
              ],
            ),
          ),

          const FormSectionLabel('Photos'),
          _photoField(PhotoSlot.inletMarked, 'Inlet marked'),
          _photoField(PhotoSlot.powerSource, 'Power source'),
          if (isWired) _photoField(PhotoSlot.wiringRouting, 'Wiring routing'),
          if (isWireless)
            _photoField(PhotoSlot.antennaRouting, 'Antenna routing'),

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
              label: const Text('Save source point'),
            ),
          ],
        ],
      ),
    );
  }
}
