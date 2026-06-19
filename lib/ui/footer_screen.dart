import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/footer.dart';
import '../models/site.dart';
import 'widgets/form_fields.dart';

/// The per-site "Footer" form — closing, site-wide details. One per site (like
/// Client inputs). All fields optional; partial saves allowed.
class FooterScreen extends StatefulWidget {
  const FooterScreen({
    super.key,
    required this.repository,
    required this.site,
  });

  final SurveyRepository repository;
  final Site site;

  @override
  State<FooterScreen> createState() => _FooterScreenState();
}

class _FooterScreenState extends State<FooterScreen> {
  final TextEditingController _tds = TextEditingController();
  final TextEditingController _tss = TextEditingController();
  final TextEditingController _tclServiceDetails = TextEditingController();
  final TextEditingController _generalRemarks = TextEditingController();
  final TextEditingController _surveyorName = TextEditingController();

  bool? _tclService;
  DateTime? _surveyDate;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final existing = await widget.repository.getFooter(widget.site.id);
    if (!mounted) return;
    setState(() {
      if (existing != null) {
        _tds.text = existing.tdsPpm?.toString() ?? '';
        _tss.text = existing.tssPpm?.toString() ?? '';
        _tclServiceDetails.text = existing.tclServiceDetails;
        _generalRemarks.text = existing.generalRemarks;
        _surveyorName.text = existing.surveyorName;
        _tclService = existing.tclService;
        _surveyDate = existing.surveyDate;
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tds.dispose();
    _tss.dispose();
    _tclServiceDetails.dispose();
    _generalRemarks.dispose();
    _surveyorName.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _surveyDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _surveyDate = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final footer = Footer(
      tdsPpm: double.tryParse(_tds.text.trim()),
      tssPpm: double.tryParse(_tss.text.trim()),
      tclService: _tclService,
      tclServiceDetails: _tclService == true
          ? _tclServiceDetails.text.trim()
          : '',
      generalRemarks: _generalRemarks.text.trim(),
      surveyDate: _surveyDate,
      surveyorName: _surveyorName.text.trim(),
    );

    await widget.repository.saveFooter(widget.site.id, footer);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Footer saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _surveyDate == null
        ? 'Survey date — not set'
        : 'Survey date: ${_surveyDate!.toIso8601String().split('T').first}';

    return Scaffold(
      appBar: AppBar(title: const Text('Footer')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppTextField(
                  controller: _tds,
                  label: 'TDS (ppm)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                AppTextField(
                  controller: _tss,
                  label: 'TSS (ppm)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                YesNoField(
                  label: 'TCL service',
                  value: _tclService,
                  onChanged: (v) => setState(() => _tclService = v),
                ),
                if (_tclService == true)
                  AppTextField(
                    controller: _tclServiceDetails,
                    label: 'TCL service details',
                    maxLines: 2,
                  ),
                AppTextField(
                  controller: _generalRemarks,
                  label: 'General remarks',
                  maxLines: 3,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(dateLabel),
                    ),
                  ),
                ),
                AppTextField(controller: _surveyorName, label: 'Surveyor name'),

                const FormSectionLabel('Photos / videos'),
                const DisabledPhotoField(label: 'Site photos / videos'),

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
                  label: const Text('Save footer'),
                ),
              ],
            ),
    );
  }
}
