import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/inlet_point.dart';
import '../models/site.dart';
import '../models/survey_options.dart';
import '../models/survey_photo.dart';
import 'widgets/form_fields.dart';
import 'widgets/photo_capture_field.dart';

/// Add or edit a single inlet point. All fields optional (partial saves).
class InletPointFormScreen extends StatefulWidget {
  const InletPointFormScreen({
    super.key,
    required this.repository,
    required this.site,
    this.existing,
  });

  final SurveyRepository repository;
  final Site site;
  final InletPoint? existing;

  @override
  State<InletPointFormScreen> createState() => _InletPointFormScreenState();
}

class _InletPointFormScreenState extends State<InletPointFormScreen> {
  late final TextEditingController _apartmentBhk;
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

  /// Captured photos, keyed by slot. Loaded on edit; reconciled on save.
  final Map<String, PhotoDraft> _photos = {};

  bool _saving = false;

  // OHT/HNS shares the central enum; the inlet form offers only OHT and HNS.
  static const _ohtHnsOptions = [OhtHns.oht, OhtHns.hns];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) _loadPhotos(e.id);

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
  }

  @override
  void dispose() {
    _apartmentBhk.dispose();
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
        _photos[p.slot] = PhotoDraft(
          id: p.id,
          localPath: p.localPath,
          remotePath: p.remotePath,
        );
      }
    });
  }

  void _onPhotoCaptured(String slot, String localPath) {
    setState(() {
      final existing = _photos[slot];
      if (existing == null) {
        _photos[slot] = PhotoDraft(localPath: localPath);
      } else {
        existing.localPath = localPath;
        existing.remotePath = null; // retake — must re-upload
      }
    });
  }

  List<SurveyPhoto> _photoListFor(String ownerId) {
    final list = <SurveyPhoto>[];
    for (final entry in _photos.entries) {
      final draft = entry.value;
      if (draft.localPath == null) continue;
      list.add(
        SurveyPhoto(
          id: draft.id,
          ownerType: PhotoOwner.inletPoint,
          ownerId: ownerId,
          slot: entry.key,
          localPath: draft.localPath,
          remotePath: draft.remotePath,
        ),
      );
    }
    return list;
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final draft = InletPoint(
      id: widget.existing?.id ?? '',
      siteId: widget.site.id,
      block: _block,
      apartmentBhk: _apartmentBhk.text.trim(),
      sensorSize: _sensorSize,
      series: _series.text.trim(),
      sensorOd: _sensorOd,
      pipeSize: _pipeSize,
      pipeType: _pipeType,
      qty: int.tryParse(_qty.text.trim()),
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
          widget.existing == null ? 'Add inlet point' : 'Edit inlet point',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppDropdownField<String>(
            label: 'Block',
            value: _block,
            items: widget.site.blocks,
            itemLabel: (b) => b,
            emptyHint: 'No blocks on this site — add them via the site first.',
            onChanged: (v) => setState(() => _block = v),
          ),
          AppTextField(
            controller: _apartmentBhk,
            label: 'Apartment (BHK)',
          ),
          AppDropdownField<SensorSize>(
            label: 'Sensor size',
            value: _sensorSize,
            items: SensorSize.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _sensorSize = v),
          ),
          AppTextField(controller: _series, label: 'Series'),
          AppDropdownField<SensorOd>(
            label: 'Sensor OD',
            value: _sensorOd,
            items: SensorOd.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _sensorOd = v),
          ),
          AppDropdownField<PipeSize>(
            label: 'Pipe size',
            value: _pipeSize,
            items: PipeSize.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _pipeSize = v),
          ),
          AppDropdownField<PipeType>(
            label: 'Pipe type',
            value: _pipeType,
            items: PipeType.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _pipeType = v),
          ),
          AppTextField(
            controller: _qty,
            label: 'Qty',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          AppDropdownField<SensorType>(
            label: 'Sensor type',
            value: _sensorType,
            items: SensorType.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _sensorType = v),
          ),

          YesNoField(
            label: 'Rework',
            value: _rework,
            onChanged: (v) => setState(() => _rework = v),
          ),
          if (_rework == true)
            AppTextField(
              controller: _reworkDetails,
              label: 'Rework details',
              maxLines: 2,
            ),

          YesNoField(
            label: 'Linear distance & clearance 10X',
            value: _linearDistanceClearance10x,
            onChanged: (v) => setState(() => _linearDistanceClearance10x = v),
          ),
          YesNoField(
            label: 'Reverse flow',
            value: _reverseFlow,
            onChanged: (v) => setState(() => _reverseFlow = v),
          ),
          AppDropdownField<OhtHns>(
            label: 'OHT / HNS',
            value: _ohtHns,
            items: _ohtHnsOptions,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _ohtHns = v),
          ),
          YesNoField(
            label: 'Distance from motor/pump',
            value: _distanceFromMotorPump,
            onChanged: (v) => setState(() => _distanceFromMotorPump = v),
          ),
          AppTextField(
            controller: _pressure,
            label: 'Max & continuous pressure (bar)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          YesNoField(
            label: 'Strainer / screen filter',
            value: _strainerScreenFilter,
            onChanged: (v) => setState(() => _strainerScreenFilter = v),
          ),
          AppDropdownField<FlowDirection>(
            label: 'Flow direction',
            value: _flowDirection,
            items: FlowDirection.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _flowDirection = v),
          ),
          AppDropdownField<AccessMode>(
            label: 'Access mode',
            value: _accessMode,
            items: AccessMode.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _accessMode = v),
          ),
          AppDropdownField<CableRunLength>(
            label: 'Cable run length',
            value: _cableRunLength,
            items: CableRunLength.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _cableRunLength = v),
          ),
          YesNoField(
            label: 'Conduit clamping',
            value: _conduitClamping,
            onChanged: (v) => setState(() => _conduitClamping = v),
          ),
          YesNoField(
            label: 'Civil work needed',
            value: _civilWorkNeeded,
            onChanged: (v) => setState(() => _civilWorkNeeded = v),
          ),
          if (_civilWorkNeeded == true)
            AppTextField(
              controller: _civilWorkDetails,
              label: 'Civil work details',
              maxLines: 2,
            ),

          const FormSectionLabel('Photos'),
          PhotoCaptureField(
            label: 'Shaft / location marked',
            localPath: _photos[PhotoSlot.shaftLocationMarked]?.localPath,
            uploaded: _photos[PhotoSlot.shaftLocationMarked]?.uploaded ?? false,
            onCaptured: (p) =>
                _onPhotoCaptured(PhotoSlot.shaftLocationMarked, p),
          ),
          PhotoCaptureField(
            label: 'Cable routing',
            localPath: _photos[PhotoSlot.cableRouting]?.localPath,
            uploaded: _photos[PhotoSlot.cableRouting]?.uploaded ?? false,
            onCaptured: (p) => _onPhotoCaptured(PhotoSlot.cableRouting, p),
          ),
          PhotoCaptureField(
            label: 'Shaft access',
            localPath: _photos[PhotoSlot.shaftAccess]?.localPath,
            uploaded: _photos[PhotoSlot.shaftAccess]?.uploaded ?? false,
            onCaptured: (p) => _onPhotoCaptured(PhotoSlot.shaftAccess, p),
          ),
          PhotoCaptureField(
            label: 'Shaft internal',
            localPath: _photos[PhotoSlot.shaftInternal]?.localPath,
            uploaded: _photos[PhotoSlot.shaftInternal]?.uploaded ?? false,
            onCaptured: (p) => _onPhotoCaptured(PhotoSlot.shaftInternal, p),
          ),

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
      ),
    );
  }
}
