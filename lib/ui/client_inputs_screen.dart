import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/client_inputs.dart';
import '../models/site.dart';
import '../models/survey_options.dart';

/// The per-site "Client inputs" form. All fields are optional — partial
/// entries can be saved. Pre-fills from any previously saved inputs.
class ClientInputsScreen extends StatefulWidget {
  const ClientInputsScreen({
    super.key,
    required this.repository,
    required this.site,
  });

  final SurveyRepository repository;
  final Site site;

  @override
  State<ClientInputsScreen> createState() => _ClientInputsScreenState();
}

class _ClientInputsScreenState extends State<ClientInputsScreen> {
  // Text controllers
  late final TextEditingController _siteName;
  late final TextEditingController _pocName;
  late final TextEditingController _pocContact;
  late final TextEditingController _goal;
  late final TextEditingController _pointsIdentified;
  late final TextEditingController _pressure;
  late final TextEditingController _materials;
  late final TextEditingController _reworkDetails;
  late final TextEditingController _ageOfLines;
  late final TextEditingController _aestheticDetails;

  // Choice fields
  InformationSource? _informationSource;
  final Set<WaterSource> _waterSources = {};
  OhtHns? _ohtHns;
  bool? _finalisedDrawings;
  bool? _pressureBoosters;
  bool? _reworkRequired;
  bool? _aestheticGuidelines;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.site.clientInputs;

    _siteName = TextEditingController(
      text: existing?.siteName.isNotEmpty == true
          ? existing!.siteName
          : widget.site.name,
    );
    _pocName = TextEditingController(text: existing?.clientPocName ?? '');
    _pocContact = TextEditingController(text: existing?.clientPocContact ?? '');
    _goal = TextEditingController(text: existing?.goalOfInstallation ?? '');
    _pointsIdentified = TextEditingController(
      text: existing?.pointsIdentified?.toString() ?? '',
    );
    _pressure = TextEditingController(
      text: existing?.maxAndContinuousPressure ?? '',
    );
    _materials = TextEditingController(
      text: existing?.materialsAndBrandGuidelines ?? '',
    );
    _reworkDetails = TextEditingController(text: existing?.reworkDetails ?? '');
    _ageOfLines = TextEditingController(
      text: existing?.ageOfPlumbingLines ?? '',
    );
    _aestheticDetails = TextEditingController(
      text: existing?.aestheticDetails ?? '',
    );

    _informationSource = existing?.informationSource;
    _waterSources.addAll(existing?.waterSources ?? const {});
    _ohtHns = existing?.ohtHns;
    _finalisedDrawings = existing?.finalisedPlumbingDrawings;
    _pressureBoosters = existing?.pressureBoosters;
    _reworkRequired = existing?.reworkRequired;
    _aestheticGuidelines = existing?.aestheticGuidelines;
  }

  @override
  void dispose() {
    _siteName.dispose();
    _pocName.dispose();
    _pocContact.dispose();
    _goal.dispose();
    _pointsIdentified.dispose();
    _pressure.dispose();
    _materials.dispose();
    _reworkDetails.dispose();
    _ageOfLines.dispose();
    _aestheticDetails.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final inputs = ClientInputs(
      siteName: _siteName.text.trim(),
      informationSource: _informationSource,
      clientPocName: _pocName.text.trim(),
      clientPocContact: _pocContact.text.trim(),
      goalOfInstallation: _goal.text.trim(),
      waterSources: Set.unmodifiable(_waterSources),
      ohtHns: _ohtHns,
      finalisedPlumbingDrawings: _finalisedDrawings,
      pointsIdentified: int.tryParse(_pointsIdentified.text.trim()),
      maxAndContinuousPressure: _pressure.text.trim(),
      pressureBoosters: _pressureBoosters,
      materialsAndBrandGuidelines: _materials.text.trim(),
      reworkRequired: _reworkRequired,
      reworkDetails: _reworkDetails.text.trim(),
      ageOfPlumbingLines: _ageOfLines.text.trim(),
      aestheticGuidelines: _aestheticGuidelines,
      aestheticDetails: _aestheticDetails.text.trim(),
    );

    await widget.repository.saveClientInputs(widget.site.id, inputs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Client inputs saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client inputs')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Hint('All fields are optional — you can save a partial form.'),
          const SizedBox(height: 16),

          _text(_siteName, 'Site name'),
          _dropdown<InformationSource>(
            label: 'Information source',
            value: _informationSource,
            items: InformationSource.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _informationSource = v),
          ),
          _text(_pocName, 'Client POC name'),
          _text(_pocContact, 'Client POC phone/email'),
          _text(_goal, 'Goal of installation', maxLines: 2),

          _Label('Water sources present'),
          Wrap(
            spacing: 8,
            children: [
              for (final source in WaterSource.values)
                FilterChip(
                  label: Text(source.label),
                  selected: _waterSources.contains(source),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _waterSources.add(source);
                    } else {
                      _waterSources.remove(source);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),

          _dropdown<OhtHns>(
            label: 'OHT / HNS',
            value: _ohtHns,
            items: OhtHns.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _ohtHns = v),
          ),

          _yesNo(
            'Finalised plumbing drawings',
            _finalisedDrawings,
            (v) => setState(() => _finalisedDrawings = v),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              // Disabled placeholder for Phase 0 — file attach comes later.
              onPressed: null,
              icon: const Icon(Icons.attach_file),
              label: const Text('Attach drawings (coming soon)'),
            ),
          ),

          _text(
            _pointsIdentified,
            'No. of points identified by client (optional)',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _text(_pressure, 'Max & continuous pressure at all points'),

          _yesNo(
            'Pressure boosters in system',
            _pressureBoosters,
            (v) => setState(() => _pressureBoosters = v),
          ),

          _text(_materials, 'Materials & brand guidelines', maxLines: 2),

          _yesNo(
            'Rework requirements',
            _reworkRequired,
            (v) => setState(() => _reworkRequired = v),
          ),
          if (_reworkRequired == true)
            _text(_reworkDetails, 'Rework details', maxLines: 2),

          _text(_ageOfLines, 'Age of plumbing lines'),

          _yesNo(
            'Aesthetic guidelines',
            _aestheticGuidelines,
            (v) => setState(() => _aestheticGuidelines = v),
          ),
          if (_aestheticGuidelines == true)
            _text(_aestheticDetails, 'Aesthetic details', maxLines: 2),

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
            label: const Text('Save client inputs'),
          ),
        ],
      ),
    );
  }

  // ---- Field builders -------------------------------------------------------

  Widget _text(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final item in items)
            DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _yesNo(String label, bool? value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          SegmentedButton<bool>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Yes')),
              ButtonSegment(value: false, label: Text('No')),
            ],
            selected: value == null ? const {} : {value},
            onSelectionChanged: (sel) =>
                onChanged(sel.isEmpty ? null : sel.first),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
    );
  }
}
