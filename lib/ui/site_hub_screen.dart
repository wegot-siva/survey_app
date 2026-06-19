import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import 'client_inputs_screen.dart';
import 'duct_loras_list_screen.dart';
import 'footer_screen.dart';
import 'gateways_list_screen.dart';
import 'inlet_points_list_screen.dart';
import 'manage_blocks_screen.dart';
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
  int _inletPointCount = 0;
  int _ductLoraCount = 0;
  int _gatewayCount = 0;
  bool _footerFilled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final site = await widget.repository.getSiteById(widget.siteId);
    final sourcePoints = await widget.repository.getSourcePoints(widget.siteId);
    final inletPoints = await widget.repository.getInletPoints(widget.siteId);
    final ductLoras = await widget.repository.getDuctLoras(widget.siteId);
    final gateways = await widget.repository.getGateways(widget.siteId);
    final footer = await widget.repository.getFooter(widget.siteId);
    if (!mounted) return;
    setState(() {
      _site = site;
      _sourcePointCount = sourcePoints.length;
      _inletPointCount = inletPoints.length;
      _ductLoraCount = ductLoras.length;
      _gatewayCount = gateways.length;
      _footerFilled = footer != null;
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

  Future<void> _openInletPoints(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InletPointsListScreen(repository: widget.repository, site: site),
      ),
    );
    await _load();
  }

  Future<void> _openDuctLoras(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DuctLorasListScreen(repository: widget.repository, site: site),
      ),
    );
    await _load();
  }

  Future<void> _openGateways(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GatewaysListScreen(repository: widget.repository, site: site),
      ),
    );
    await _load();
  }

  Future<void> _openFooter(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FooterScreen(repository: widget.repository, site: site),
      ),
    );
    await _load();
  }

  Future<void> _openManageBlocks(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ManageBlocksScreen(repository: widget.repository, site: site),
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
                _SectionTile(
                  icon: Icons.grid_view_outlined,
                  title: 'Blocks',
                  subtitle: site.blocks.isEmpty
                      ? 'No blocks — tap to add'
                      : site.blocks.join(', '),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openManageBlocks(site),
                ),
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
                  subtitle: '$_inletPointCount recorded',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openInletPoints(site),
                ),
                _SectionTile(
                  icon: Icons.router_outlined,
                  title: 'Duct LoRa',
                  subtitle: '$_ductLoraCount recorded',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openDuctLoras(site),
                ),
                _SectionTile(
                  icon: Icons.cell_tower_outlined,
                  title: 'Gateway',
                  subtitle: '$_gatewayCount recorded',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openGateways(site),
                ),
                _SectionTile(
                  icon: Icons.notes_outlined,
                  title: 'Footer',
                  subtitle: _footerFilled ? 'Filled' : 'Not filled yet',
                  trailing: _footerFilled
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.chevron_right),
                  onTap: () => _openFooter(site),
                ),
              ],
            ),
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
