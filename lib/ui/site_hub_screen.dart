import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import 'client_inputs_screen.dart';
import 'source_points_list_screen.dart';

/// The hub for one site: jump to any section (Client inputs, Source points,
/// Inlet points). No locked wizard — sections can be done in any order and
/// left partially complete.
class SiteHubScreen extends StatefulWidget {
  const SiteHubScreen({
    super.key,
    required this.repository,
    required this.siteId,
  });

  final SurveyRepository repository;
  final String siteId;

  @override
  State<SiteHubScreen> createState() => _SiteHubScreenState();
}

class _SiteHubScreenState extends State<SiteHubScreen> {
  Site? _site;
  int _sourcePointCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final site = await widget.repository.getSiteById(widget.siteId);
    final points = await widget.repository.getSourcePoints(widget.siteId);
    if (!mounted) return;
    setState(() {
      _site = site;
      _sourcePointCount = points.length;
      _loading = false;
    });
  }

  Future<void> _openClientInputs(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ClientInputsScreen(repository: widget.repository, site: site),
      ),
    );
    await _load();
  }

  Future<void> _openSourcePoints(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SourcePointsListScreen(repository: widget.repository, site: site),
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
                _BlocksHeader(blocks: site.blocks),
                const Divider(height: 24),

                _SectionTile(
                  icon: Icons.assignment_outlined,
                  title: 'Client inputs',
                  subtitle: site.clientInputs != null
                      ? 'Filled'
                      : 'Not filled yet',
                  trailing: site.clientInputs != null
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.chevron_right),
                  onTap: () => _openClientInputs(site),
                ),
                _SectionTile(
                  icon: Icons.water_drop_outlined,
                  title: 'Source points',
                  subtitle: '$_sourcePointCount recorded',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openSourcePoints(site),
                ),
                _SectionTile(
                  icon: Icons.input_outlined,
                  title: 'Inlet points',
                  subtitle: 'Coming soon',
                  trailing: const Icon(Icons.lock_outline),
                  onTap: null,
                ),
              ],
            ),
    );
  }
}

class _BlocksHeader extends StatelessWidget {
  const _BlocksHeader({required this.blocks});

  final List<String> blocks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Blocks', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (blocks.isEmpty)
          const Text('No blocks recorded.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [for (final b in blocks) Chip(label: Text(b))],
          ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: onTap != null,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
