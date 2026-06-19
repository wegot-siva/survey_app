import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/duct_lora.dart';
import '../models/site.dart';
import 'widgets/form_fields.dart';

/// Add or edit a single Duct LoRa unit. All fields optional (partial saves).
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
  });

  final SurveyRepository repository;
  final Site site;
  final List<String> availableSeries;
  final DuctLora? existing;

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

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

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

  Future<void> _save() async {
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
      cableLength: double.tryParse(_cableLength.text.trim()),
    );

    if (widget.existing == null) {
      await widget.repository.addDuctLora(draft);
    } else {
      await widget.repository.updateDuctLora(draft);
    }

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
          widget.existing == null ? 'Add Duct LoRa' : 'Edit Duct LoRa',
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
          MultiSelectChips<String>(
            label: 'Series served',
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
          ),
          YesNoField(
            label: 'Accessible for service',
            value: _accessibleForService,
            onChanged: (v) => setState(() => _accessibleForService = v),
          ),
          AppTextField(
            controller: _rssi,
            label: 'RSSI value (if TCL)',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')),
            ],
          ),
          YesNoField(
            label: 'Power point available / shielded',
            value: _powerPointAvailableShielded,
            onChanged: (v) =>
                setState(() => _powerPointAvailableShielded = v),
          ),
          YesNoField(
            label: 'Separate MCB for series (max 4)',
            value: _separateMcbForSeries,
            onChanged: (v) => setState(() => _separateMcbForSeries = v),
          ),
          YesNoField(
            label: 'UPS power supply',
            value: _upsPowerSupply,
            onChanged: (v) => setState(() => _upsPowerSupply = v),
          ),
          AppTextField(
            controller: _cableLength,
            label: 'Duct LoRa cable length (pending confirmation)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),

          const FormSectionLabel('Photos'),
          const DisabledPhotoField(label: 'Duct LoRa location / placement'),

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
      ),
    );
  }
}
