import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import '../models/survey_status.dart';
import '../models/user_role.dart';
import '../services/session_controller.dart';
import 'bom_preview_screen.dart';
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
    required this.session,
  });

  final SurveyRepository repository;
  final String siteId;
  final SessionController session;

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

  Future<void> _openBomPreview(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BomPreviewScreen(repository: widget.repository, site: site),
      ),
    );
    // Read-only — no need to reload the hub afterwards.
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

  /// Engineer's "I'm done" action — moves the survey to "submitted", which is
  /// what the Approver will act on in a later slice. Available any time before
  /// submission (covers re-opening a survey that's still "assigned" too, in
  /// case the auto in-progress transition didn't fire for some reason).
  Future<void> _markSubmitted(Site site) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit survey?'),
        content: const Text(
          'This marks the survey as submitted and ready for approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.repository.updateSite(
      site.copyWith(status: SurveyStatus.submitted),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Survey submitted.')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    final isEngineer = widget.session.currentRole == UserRole.engineer;
    final canSubmit =
        site?.status == SurveyStatus.assigned ||
        site?.status == SurveyStatus.inProgress;

    return Scaffold(
      appBar: AppBar(
        title: Text(site?.name ?? 'Site'),
        actions: [
          if (site != null && isEngineer && canSubmit)
            TextButton.icon(
              onPressed: () => _markSubmitted(site),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Submit'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : site == null
          ? const Center(child: Text('Site not found.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (site.status != null) _StatusBanner(status: site.status!),
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
                _SectionTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Generate BoM',
                  subtitle: 'Preview the computed bill of materials',
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openBomPreview(site),
                ),
              ],
            ),
    );
  }
}

/// Shows the survey's current lifecycle stage at the top of the Hub.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.timeline_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Text(
              'Status: ${SurveyStatus.label(status)}',
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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
