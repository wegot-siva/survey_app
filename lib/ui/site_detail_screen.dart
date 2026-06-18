import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/client_inputs.dart';
import '../models/site.dart';
import 'client_inputs_screen.dart';

/// Shows one site: its blocks and the status of its Client inputs form.
class SiteDetailScreen extends StatefulWidget {
  const SiteDetailScreen({
    super.key,
    required this.repository,
    required this.siteId,
  });

  final SurveyRepository repository;
  final String siteId;

  @override
  State<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends State<SiteDetailScreen> {
  Site? _site;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final site = await widget.repository.getSiteById(widget.siteId);
    if (!mounted) return;
    setState(() {
      _site = site;
      _loading = false;
    });
  }

  Future<void> _openClientInputs() async {
    final site = _site;
    if (site == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ClientInputsScreen(repository: widget.repository, site: site),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    return Scaffold(
      appBar: AppBar(title: Text(site?.name ?? 'Site')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : site == null
          ? const Center(child: Text('Site not found.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionTitle('Blocks (${site.blocks.length})'),
                if (site.blocks.isEmpty)
                  const Text('No blocks recorded.')
                else
                  ...site.blocks.map(
                    (b) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.grid_view_outlined),
                      title: Text(b),
                    ),
                  ),
                const Divider(height: 32),
                _SectionTitle('Client inputs'),
                _ClientInputsSummary(inputs: site.clientInputs),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: _openClientInputs,
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    site.clientInputs == null
                        ? 'Fill client inputs'
                        : 'Edit client inputs',
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// A compact read-only summary of saved client inputs.
class _ClientInputsSummary extends StatelessWidget {
  const _ClientInputsSummary({required this.inputs});

  final ClientInputs? inputs;

  @override
  Widget build(BuildContext context) {
    final i = inputs;
    if (i == null) {
      return const Text('Not filled yet.');
    }

    String orDash(String s) => s.trim().isEmpty ? '—' : s;
    String yn(bool? v) => v == null ? '—' : (v ? 'Yes' : 'No');

    final waterSources = i.waterSources.isEmpty
        ? '—'
        : i.waterSources.map((w) => w.label).join(', ');

    final rows = <(String, String)>[
      ('Site name', orDash(i.siteName)),
      ('Information source', i.informationSource?.label ?? '—'),
      ('Client POC name', orDash(i.clientPocName)),
      ('Client POC phone/email', orDash(i.clientPocContact)),
      ('Goal of installation', orDash(i.goalOfInstallation)),
      ('Water sources', waterSources),
      ('OHT / HNS', i.ohtHns?.label ?? '—'),
      ('Finalised plumbing drawings', yn(i.finalisedPlumbingDrawings)),
      ('Points identified', i.pointsIdentified?.toString() ?? '—'),
      ('Max & continuous pressure', orDash(i.maxAndContinuousPressure)),
      ('Pressure boosters', yn(i.pressureBoosters)),
      ('Materials & brand guidelines', orDash(i.materialsAndBrandGuidelines)),
      ('Rework required', yn(i.reworkRequired)),
      if (i.reworkRequired == true) ('Rework details', orDash(i.reworkDetails)),
      ('Age of plumbing lines', orDash(i.ageOfPlumbingLines)),
      ('Aesthetic guidelines', yn(i.aestheticGuidelines)),
      if (i.aestheticGuidelines == true)
        ('Aesthetic details', orDash(i.aestheticDetails)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 180,
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(child: Text(value)),
              ],
            ),
          ),
      ],
    );
  }
}
