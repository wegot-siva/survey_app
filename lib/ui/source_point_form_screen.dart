import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_options.dart';
import 'widgets/form_fields.dart';

/// Add or edit a single source point. All fields optional (partial saves).
class SourcePointFormScreen extends StatefulWidget {
  const SourcePointFormScreen({
    super.key,
    required this.repository,
    required this.site,
    this.existing,
  });

  final SurveyRepository repository;
  final Site site;
  final SourcePoint? existing;

  @override
  State<SourcePointFormScreen> createState() => _SourcePointFormScreenState();
}

class _SourcePointFormScreenState extends State<SourcePointFormScreen> {
  late final TextEditingController _apartment;
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

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

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
  }

  @override
  void dispose() {
    _apartment.dispose();
    _inletDescription.dispose();
    _qty.dispose();
    _reworkDetails.dispose();
    _reducerSpecDetails.dispose();
    _pressure.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final draft = SourcePoint(
      id: widget.existing?.id ?? '',
      siteId: widget.site.id,
      block: _block,
      apartment: _apartment.text.trim(),
      inletDescription: _inletDescription.text.trim(),
      sensorSize: _sensorSize,
      sensorOd: _sensorOd,
      pipeSize: _pipeSize,
      pipeType: _pipeType,
      qty: int.tryParse(_qty.text.trim()),
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

    if (widget.existing == null) {
      await widget.repository.addSourcePoint(draft);
    } else {
      await widget.repository.updateSourcePoint(draft);
    }

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
          widget.existing == null ? 'Add source point' : 'Edit source point',
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
          AppTextField(controller: _apartment, label: 'Apartment'),
          AppTextField(
            controller: _inletDescription,
            label: 'Inlet description',
            maxLines: 2,
          ),

          AppDropdownField<SensorSize>(
            label: 'Sensor size',
            value: _sensorSize,
            items: SensorSize.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _sensorSize = v),
          ),
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

          AppDropdownField<FlowDirection>(
            label: 'Flow direction',
            value: _flowDirection,
            items: FlowDirection.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _flowDirection = v),
          ),

          YesNoField(
            label: '10X clearance',
            value: _clearance10x,
            onChanged: (v) => setState(() => _clearance10x = v),
          ),
          YesNoField(
            label: 'Pipe full',
            value: _pipeFull,
            onChanged: (v) => setState(() => _pipeFull = v),
          ),
          YesNoField(
            label: 'Valve downstream',
            value: _valveDownstream,
            onChanged: (v) => setState(() => _valveDownstream = v),
          ),

          YesNoField(
            label: 'Reducer spec',
            value: _reducerSpec,
            onChanged: (v) => setState(() => _reducerSpec = v),
          ),
          if (_reducerSpec == true)
            AppTextField(
              controller: _reducerSpecDetails,
              label: 'Reducer spec details',
              maxLines: 2,
            ),

          YesNoField(
            label: 'Downstream outlet above pipe (FIG1)',
            value: _downstreamOutletAbovePipeFig1,
            onChanged: (v) => setState(() => _downstreamOutletAbovePipeFig1 = v),
          ),
          YesNoField(
            label: 'Air vent needed (FIG2)',
            value: _airVentNeededFig2,
            onChanged: (v) => setState(() => _airVentNeededFig2 = v),
          ),
          YesNoField(
            label: 'Reverse flow',
            value: _reverseFlow,
            onChanged: (v) => setState(() => _reverseFlow = v),
          ),
          YesNoField(
            label: 'Distance from motor/pump (FIG3)',
            value: _distanceFromMotorPumpFig3,
            onChanged: (v) => setState(() => _distanceFromMotorPumpFig3 = v),
          ),
          YesNoField(
            label: 'No flexible pipe within 20X',
            value: _noFlexiblePipeWithin20x,
            onChanged: (v) => setState(() => _noFlexiblePipeWithin20x = v),
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
          YesNoField(
            label: 'Chamber installation',
            value: _chamberInstallation,
            onChanged: (v) => setState(() => _chamberInstallation = v),
          ),

          if (isWireless) ...[
            const FormSectionLabel('Wireless'),
            YesNoField(
              label: 'Antenna required',
              value: _antennaRequired,
              onChanged: (v) => setState(() => _antennaRequired = v),
            ),
            YesNoField(
              label: 'Transmitting part open to air',
              value: _transmittingPartOpenToAir,
              onChanged: (v) => setState(() => _transmittingPartOpenToAir = v),
            ),
            YesNoField(
              label: 'NRV feasibility',
              value: _nrvFeasibility,
              onChanged: (v) => setState(() => _nrvFeasibility = v),
            ),
          ],

          const FormSectionLabel('Photos'),
          const DisabledPhotoField(label: 'Inlet marked'),
          const DisabledPhotoField(label: 'Power source'),
          if (isWired) const DisabledPhotoField(label: 'Wiring routing'),
          if (isWireless) const DisabledPhotoField(label: 'Antenna routing'),

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
      ),
    );
  }
}
