import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/inlet_point.dart';
import '../models/site.dart';
import '../models/survey_options.dart';
import '../models/survey_photo.dart';
import 'photo_markup_screen.dart';
import 'widgets/form_fields.dart';
import 'widgets/photo_capture_field.dart';

/// Add or edit a single inlet point. Apartment (BHK), sensor size, sensor
/// type, qty, and series are mandatory (see `_save`); every other field is
/// optional (partial saves).
class InletPointFormScreen extends StatefulWidget {
  const InletPointFormScreen({
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
  final InletPoint? existing;

  /// Shows the Admin-only "Fill test data" shortcut — a dev/QA tool that
  /// fills every mandatory field with a placeholder value so the section
  /// passes validation instantly. Never shown to any other role.
  final bool isAdmin;

  /// Pre-fills the form from this record — via [InletPoint.copyAsDuplicate]
  /// — while still saving as a brand new record. Mutually exclusive with
  /// [existing]; ignored if both are set. Unlike [existing], never triggers
  /// a photo load.
  final InletPoint? duplicateFrom;

  final bool readOnly;

  @override
  State<InletPointFormScreen> createState() => _InletPointFormScreenState();
}

class _InletPointFormScreenState extends State<InletPointFormScreen> {
  late final TextEditingController _apartmentBhk;
  final _apartmentBhkFocusNode = FocusNode();
  late final TextEditingController _series;
  late final TextEditingController _qty;
  late final TextEditingController _reworkDetails;
  late final TextEditingController _pressure;
  late final TextEditingController _civilWorkDetails;

  String? _block;
  SensorSize? _sensorSize;
  SensorOd? _sensorOd;
  PipeSize? _pipeSize;
  PipeType? _pipeType;
  SensorType? _sensorType;
  OhtHns? _ohtHns;
  FlowDirection? _flowDirection;
  AccessMode? _accessMode;
  CableRunLength? _cableRunLength;

  bool? _rework;
  bool? _linearDistanceClearance10x;
  bool? _reverseFlow;
  bool? _distanceFromMotorPump;
  bool? _strainerScreenFilter;
  bool? _conduitClamping;
  bool? _civilWorkNeeded;

  /// Captured photos, keyed by slot (each slot allows multiple). Loaded on
  /// edit; reconciled on save.
  final Map<String, List<PhotoDraft>> _photos = {};

  bool _saving = false;

  // Mandatory-field errors, set on a failed save attempt and cleared on the
  // next one — see _save().
  String? _apartmentBhkError;
  String? _sensorSizeError;
  String? _sensorTypeError;
  String? _qtyError;
  String? _seriesError;
  String? _blockError;
  String? _sensorOdError;
  String? _pipeSizeError;
  String? _pipeTypeError;
  String? _reworkError;
  String? _reworkDetailsError;
  String? _linearDistanceClearance10xError;
  String? _reverseFlowError;
  String? _ohtHnsError;
  String? _distanceFromMotorPumpError;
  String? _pressureError;
  String? _strainerScreenFilterError;
  String? _flowDirectionError;
  String? _accessModeError;
  String? _cableRunLengthError;
  String? _conduitClampingError;
  String? _civilWorkNeededError;
  String? _civilWorkDetailsError;

  /// Starts false; flips true when the Edit button is tapped. Irrelevant
  /// unless [widget.readOnly] — see [_viewOnly].
  bool _editing = false;

  /// True while fields should be visible but non-interactive: opened
  /// read-only (Approver review) and Edit hasn't been tapped yet. Gates an
  /// [IgnorePointer], not each field's `enabled` — so the fields keep their
  /// normal (not greyed-out) styling in view mode.
  bool get _viewOnly => widget.readOnly && !_editing;

  // OHT/HNS shares the central enum; the inlet form offers only OHT and HNS.
  static const _ohtHnsOptions = [OhtHns.oht, OhtHns.hns];

  @override
  void initState() {
    super.initState();
    // duplicateFrom only supplies prefill values (see InletPoint.
    // copyAsDuplicate for exactly what carries over) — existing is what
    // drives photo loading and the save-path decision (add vs update)
    // further down.
    final e = widget.existing ?? widget.duplicateFrom;
    if (widget.existing != null) _loadPhotos(widget.existing!.id);

    _apartmentBhk = TextEditingController(text: e?.apartmentBhk ?? '');
    _series = TextEditingController(text: e?.series ?? '');
    _qty = TextEditingController(text: e?.qty?.toString() ?? '');
    _reworkDetails = TextEditingController(text: e?.reworkDetails ?? '');
    _pressure = TextEditingController(
      text: e?.maxAndContinuousPressureBar?.toString() ?? '',
    );
    _civilWorkDetails = TextEditingController(text: e?.civilWorkDetails ?? '');

    _block = (e?.block != null && widget.site.blocks.contains(e!.block))
        ? e.block
        : null;
    _sensorSize = e?.sensorSize;
    _sensorOd = e?.sensorOd;
    _pipeSize = e?.pipeSize;
    _pipeType = e?.pipeType;
    _sensorType = e?.sensorType;
    _ohtHns = e?.ohtHns;
    _flowDirection = e?.flowDirection;
    _accessMode = e?.accessMode;
    _cableRunLength = e?.cableRunLength;

    _rework = e?.rework;
    _linearDistanceClearance10x = e?.linearDistanceClearance10x;
    _reverseFlow = e?.reverseFlow;
    _distanceFromMotorPump = e?.distanceFromMotorPump;
    _strainerScreenFilter = e?.strainerScreenFilter;
    _conduitClamping = e?.conduitClamping;
    _civilWorkNeeded = e?.civilWorkNeeded;

    // Duplicating pre-fills Apartment (BHK) (see InletPoint.copyAsDuplicate)
    // — auto-focus and select it so the pre-filled value is the first thing
    // the user reviews, a nudge to check/edit it rather than a block.
    if (widget.duplicateFrom != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _apartmentBhkFocusNode.requestFocus();
        _apartmentBhk.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _apartmentBhk.text.length,
        );
      });
    }
  }

  @override
  void dispose() {
    _apartmentBhk.dispose();
    _apartmentBhkFocusNode.dispose();
    _series.dispose();
    _qty.dispose();
    _reworkDetails.dispose();
    _pressure.dispose();
    _civilWorkDetails.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos(String ownerId) async {
    final loaded = await widget.repository.getPhotos(
      PhotoOwner.inletPoint,
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
            ownerType: PhotoOwner.inletPoint,
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
  /// placeholder value so the section passes validation immediately.
  void _fillTestData() {
    setState(() {
      _apartmentBhk.text = 'Test Apartment';
      if (widget.site.blocks.isNotEmpty) _block = widget.site.blocks.first;
      _sensorSize = SensorSize.values.first;
      _sensorOd = SensorOd.values.first;
      _pipeSize = PipeSize.values.first;
      _pipeType = PipeType.values.first;
      _sensorType = SensorType.values.first;
      _qty.text = '1';
      _series.text = 'Test Series';
      _rework = false;
      _linearDistanceClearance10x = true;
      _reverseFlow = false;
      _ohtHns = _ohtHnsOptions.first;
      _distanceFromMotorPump = true;
      _pressure.text = '1';
      _strainerScreenFilter = true;
      _flowDirection = FlowDirection.values.first;
      _accessMode = AccessMode.values.first;
      _cableRunLength = CableRunLength.values.first;
      _conduitClamping = true;
      _civilWorkNeeded = false;

      _apartmentBhkError = null;
      _sensorSizeError = null;
      _sensorTypeError = null;
      _qtyError = null;
      _seriesError = null;
      _blockError = null;
      _sensorOdError = null;
      _pipeSizeError = null;
      _pipeTypeError = null;
      _reworkError = null;
      _reworkDetailsError = null;
      _linearDistanceClearance10xError = null;
      _reverseFlowError = null;
      _ohtHnsError = null;
      _distanceFromMotorPumpError = null;
      _pressureError = null;
      _strainerScreenFilterError = null;
      _flowDirectionError = null;
      _accessModeError = null;
      _cableRunLengthError = null;
      _conduitClampingError = null;
      _civilWorkNeededError = null;
      _civilWorkDetailsError = null;
    });
    if (widget.site.blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Other fields filled — add a block to the site first to also fill Block.',
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    final apartmentBhk = _apartmentBhk.text.trim();
    final series = _series.text.trim();
    final qty = int.tryParse(_qty.text.trim());
    final reworkDetails = _reworkDetails.text.trim();
    final pressure = _pressure.text.trim();
    final civilWorkDetails = _civilWorkDetails.text.trim();

    setState(() {
      _apartmentBhkError = apartmentBhk.isEmpty ? 'Required' : null;
      _sensorSizeError = _sensorSize == null ? 'Required' : null;
      _sensorTypeError = _sensorType == null ? 'Required' : null;
      _qtyError = (qty == null || qty <= 0) ? 'Required' : null;
      _seriesError = series.isEmpty ? 'Required' : null;
      _blockError = _block == null ? 'Required' : null;
      _sensorOdError = _sensorOd == null ? 'Required' : null;
      _pipeSizeError = _pipeSize == null ? 'Required' : null;
      _pipeTypeError = _pipeType == null ? 'Required' : null;
      _reworkError = _rework == null ? 'Required' : null;
      _reworkDetailsError =
          (_rework == true && reworkDetails.isEmpty) ? 'Required' : null;
      _linearDistanceClearance10xError =
          _linearDistanceClearance10x == null ? 'Required' : null;
      _reverseFlowError = _reverseFlow == null ? 'Required' : null;
      _ohtHnsError = _ohtHns == null ? 'Required' : null;
      _distanceFromMotorPumpError =
          _distanceFromMotorPump == null ? 'Required' : null;
      _pressureError = pressure.isEmpty ? 'Required' : null;
      _strainerScreenFilterError =
          _strainerScreenFilter == null ? 'Required' : null;
      _flowDirectionError = _flowDirection == null ? 'Required' : null;
      _accessModeError = _accessMode == null ? 'Required' : null;
      _cableRunLengthError = _cableRunLength == null ? 'Required' : null;
      _conduitClampingError = _conduitClamping == null ? 'Required' : null;
      _civilWorkNeededError = _civilWorkNeeded == null ? 'Required' : null;
      _civilWorkDetailsError =
          (_civilWorkNeeded == true && civilWorkDetails.isEmpty)
          ? 'Required'
          : null;
    });
    if (_apartmentBhkError != null ||
        _sensorSizeError != null ||
        _sensorTypeError != null ||
        _qtyError != null ||
        _seriesError != null ||
        _blockError != null ||
        _sensorOdError != null ||
        _pipeSizeError != null ||
        _pipeTypeError != null ||
        _reworkError != null ||
        _reworkDetailsError != null ||
        _linearDistanceClearance10xError != null ||
        _reverseFlowError != null ||
        _ohtHnsError != null ||
        _distanceFromMotorPumpError != null ||
        _pressureError != null ||
        _strainerScreenFilterError != null ||
        _flowDirectionError != null ||
        _accessModeError != null ||
        _cableRunLengthError != null ||
        _conduitClampingError != null ||
        _civilWorkNeededError != null ||
        _civilWorkDetailsError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the required fields.')),
      );
      return;
    }

    setState(() => _saving = true);

    final draft = InletPoint(
      id: widget.existing?.id ?? '',
      siteId: widget.site.id,
      block: _block,
      apartmentBhk: apartmentBhk,
      sensorSize: _sensorSize,
      series: series,
      sensorOd: _sensorOd,
      pipeSize: _pipeSize,
      pipeType: _pipeType,
      qty: qty,
      sensorType: _sensorType,
      rework: _rework,
      reworkDetails: _reworkDetails.text.trim(),
      linearDistanceClearance10x: _linearDistanceClearance10x,
      reverseFlow: _reverseFlow,
      ohtHns: _ohtHns,
      distanceFromMotorPump: _distanceFromMotorPump,
      maxAndContinuousPressureBar: double.tryParse(_pressure.text.trim()),
      strainerScreenFilter: _strainerScreenFilter,
      flowDirection: _flowDirection,
      accessMode: _accessMode,
      cableRunLength: _cableRunLength,
      conduitClamping: _conduitClamping,
      civilWorkNeeded: _civilWorkNeeded,
      civilWorkDetails: _civilWorkDetails.text.trim(),
    );

    final String ownerId;
    if (widget.existing == null) {
      final stored = await widget.repository.addInletPoint(draft);
      ownerId = stored.id;
    } else {
      await widget.repository.updateInletPoint(draft);
      ownerId = widget.existing!.id;
    }
    await widget.repository.setPhotos(
      PhotoOwner.inletPoint,
      ownerId,
      _photoListFor(ownerId),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inlet point saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _viewOnly
              ? 'Inlet point'
              : widget.existing == null
              ? 'Add inlet point'
              : 'Edit inlet point',
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
                  controller: _apartmentBhk,
                  focusNode: _apartmentBhkFocusNode,
                  label: 'Apartment (BHK) *',
                  errorText: _apartmentBhkError,
                ),
                AppDropdownField<SensorSize>(
                  label: 'Sensor size *',
                  value: _sensorSize,
                  items: SensorSize.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _sensorSize = v),
                  errorText: _sensorSizeError,
                ),
                AppTextField(
                  controller: _series,
                  label: 'Series *',
                  errorText: _seriesError,
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

                YesNoField(
                  label: 'Linear distance & clearance 10X *',
                  value: _linearDistanceClearance10x,
                  onChanged: (v) =>
                      setState(() => _linearDistanceClearance10x = v),
                  errorText: _linearDistanceClearance10xError,
                ),
                YesNoField(
                  label: 'Reverse flow *',
                  value: _reverseFlow,
                  onChanged: (v) => setState(() => _reverseFlow = v),
                  errorText: _reverseFlowError,
                ),
                AppDropdownField<OhtHns>(
                  label: 'OHT / HNS *',
                  value: _ohtHns,
                  items: _ohtHnsOptions,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _ohtHns = v),
                  errorText: _ohtHnsError,
                ),
                YesNoField(
                  label: 'Distance from motor/pump *',
                  value: _distanceFromMotorPump,
                  onChanged: (v) => setState(() => _distanceFromMotorPump = v),
                  errorText: _distanceFromMotorPumpError,
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
                AppDropdownField<FlowDirection>(
                  label: 'Flow direction *',
                  value: _flowDirection,
                  items: FlowDirection.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _flowDirection = v),
                  errorText: _flowDirectionError,
                ),
                AppDropdownField<AccessMode>(
                  label: 'Access mode *',
                  value: _accessMode,
                  items: AccessMode.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _accessMode = v),
                  errorText: _accessModeError,
                ),
                AppDropdownField<CableRunLength>(
                  label: 'Cable run length *',
                  value: _cableRunLength,
                  items: CableRunLength.values,
                  itemLabel: (v) => v.label,
                  onChanged: (v) => setState(() => _cableRunLength = v),
                  errorText: _cableRunLengthError,
                ),
                YesNoField(
                  label: 'Conduit clamping *',
                  value: _conduitClamping,
                  onChanged: (v) => setState(() => _conduitClamping = v),
                  errorText: _conduitClampingError,
                ),
                YesNoField(
                  label: 'Civil work needed *',
                  value: _civilWorkNeeded,
                  onChanged: (v) => setState(() => _civilWorkNeeded = v),
                  errorText: _civilWorkNeededError,
                ),
                if (_civilWorkNeeded == true)
                  AppTextField(
                    controller: _civilWorkDetails,
                    label: 'Civil work details *',
                    maxLines: 2,
                    errorText: _civilWorkDetailsError,
                  ),
              ],
            ),
          ),

          const FormSectionLabel('Photos'),
          _photoField(
            PhotoSlot.shaftLocationMarked,
            'Shaft / location marked',
          ),
          _photoField(PhotoSlot.cableRouting, 'Cable routing'),
          _photoField(PhotoSlot.shaftAccess, 'Shaft access'),
          _photoField(PhotoSlot.shaftInternal, 'Shaft internal'),

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
              label: const Text('Save inlet point'),
            ),
          ],
        ],
      ),
    );
  }
}
