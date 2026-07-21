import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import '../models/survey_status.dart';
import '../services/session_controller.dart';
import 'bom_preview_screen.dart';
import 'client_inputs_screen.dart';
import 'duct_loras_list_screen.dart';
import 'footer_screen.dart';
import 'gateways_list_screen.dart';
import 'inlet_points_list_screen.dart';
import 'source_points_list_screen.dart';
import 'theme/app_theme.dart';

/// Completion state for one section row — mirrors [SiteHubScreen]'s
/// indicator so the review screen reads the same way the engineer's hub does.
enum _SectionStatus { empty, partial, complete }

/// Approver's read-only review of a submitted survey (Roles & Assignment —
/// Slice D). Opens the real section screens (Client inputs, Source points,
/// Inlet points, Duct LoRa, Gateway, Footer, BoM) in read-only mode so the
/// Approver reviews the engineer's actual entered data, not just a summary —
/// no editing happens here; edits stay in the engineer's Site Hub. Approving
/// sets status to "approved" then immediately "released", which is what
/// makes the survey visible to Sales as ready.
class ApproverReviewScreen extends StatefulWidget {
  const ApproverReviewScreen({
    super.key,
    required this.repository,
    required this.siteId,
    required this.session,
  });

  final SurveyRepository repository;
  final String siteId;
  final SessionController session;

  @override
  State<ApproverReviewScreen> createState() => _ApproverReviewScreenState();
}

class _ApproverReviewScreenState extends State<ApproverReviewScreen> {
  Site? _site;
  int _sourcePointCount = 0;
  int _inletPointCount = 0;
  int _ductLoraCount = 0;
  int _gatewayCount = 0;
  bool _footerFilled = false;
  bool _bomGenerated = false;
  bool _loading = true;
  bool _approving = false;

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
    final bomSnapshot = await widget.repository.getBomSnapshot(widget.siteId);
    if (!mounted) return;
    setState(() {
      _site = site;
      _sourcePointCount = sourcePoints.length;
      _inletPointCount = inletPoints.length;
      _ductLoraCount = ductLoras.length;
      _gatewayCount = gateways.length;
      _footerFilled = footer != null;
      _bomGenerated = bomSnapshot != null;
      _loading = false;
    });
  }

  /// Status for an open-ended count section: complete once [count] reaches
  /// the number of blocks on the site (or once it's non-zero, if the site
  /// has no blocks defined yet).
  _SectionStatus _countStatus(int count, int blockCount) {
    if (count == 0) return _SectionStatus.empty;
    final target = blockCount > 0 ? blockCount : 1;
    return count >= target ? _SectionStatus.complete : _SectionStatus.partial;
  }

  Future<void> _openClientInputs(Site site) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClientInputsScreen(
          repository: widget.repository,
          site: site,
          readOnly: true,
        ),
      ),
    );
  }

  Future<void> _openSourcePoints(Site site) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourcePointsListScreen(
          repository: widget.repository,
          site: site,
          readOnly: true,
        ),
      ),
    );
  }

  Future<void> _openInletPoints(Site site) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InletPointsListScreen(
          repository: widget.repository,
          site: site,
          readOnly: true,
        ),
      ),
    );
  }

  Future<void> _openDuctLoras(Site site) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DuctLorasListScreen(
          repository: widget.repository,
          site: site,
          readOnly: true,
        ),
      ),
    );
  }

  Future<void> _openGateways(Site site) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GatewaysListScreen(
          repository: widget.repository,
          site: site,
          readOnly: true,
        ),
      ),
    );
  }

  Future<void> _openFooter(Site site) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FooterScreen(
          repository: widget.repository,
          site: site,
          readOnly: true,
        ),
      ),
    );
  }

  Future<void> _openBomPreview(Site site) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomPreviewScreen(
          repository: widget.repository,
          site: site,
          addedByRole: widget.session.currentUserName ??
              widget.session.currentRole?.label ??
              'Approver',
          addedByUserId: widget.session.currentUserId,
          readOnly: true,
          canEditBom: true,
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final site = _site;
    if (site == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve survey?'),
        content: const Text(
          'This releases the survey back to Sales as ready.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _approving = true);
    // Two real transitions, matching the lifecycle: approved, then released.
    await widget.repository.updateSite(
      site.copyWith(status: SurveyStatus.approved),
    );
    await widget.repository.updateSite(
      site.copyWith(status: SurveyStatus.released),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Survey approved and released to Sales.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    return Scaffold(
      appBar: AppBar(title: Text(site?.name ?? 'Review survey')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : site == null
          ? const Center(child: Text('Site not found.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (site.status != null) _ReviewStatusBanner(status: site.status!),
                const SizedBox(height: 8),
                _ReviewTile(
                  icon: Icons.person_outline,
                  title: 'Assigned to',
                  value: site.assignedTo ?? 'Unassigned',
                ),
                _ReviewTile(
                  icon: Icons.grid_view_outlined,
                  title: 'Blocks',
                  value: site.blocks.isEmpty ? 'None' : site.blocks.join(', '),
                ),
                _SectionTile(
                  icon: Icons.assignment_outlined,
                  title: 'Client inputs',
                  subtitle: site.clientInputs != null
                      ? 'Filled — tap to view'
                      : 'Not filled',
                  status: site.clientInputs != null
                      ? _SectionStatus.complete
                      : _SectionStatus.empty,
                  onTap: () => _openClientInputs(site),
                ),
                _SectionTile(
                  icon: Icons.water_drop_outlined,
                  title: 'Source points',
                  subtitle: '$_sourcePointCount recorded — tap to view',
                  status: _countStatus(_sourcePointCount, site.blocks.length),
                  onTap: () => _openSourcePoints(site),
                ),
                _SectionTile(
                  icon: Icons.input_outlined,
                  title: 'Inlet points',
                  subtitle: '$_inletPointCount recorded — tap to view',
                  status: _countStatus(_inletPointCount, site.blocks.length),
                  onTap: () => _openInletPoints(site),
                ),
                _SectionTile(
                  icon: Icons.router_outlined,
                  title: 'Duct LoRa',
                  subtitle: '$_ductLoraCount recorded — tap to view',
                  status: _countStatus(_ductLoraCount, site.blocks.length),
                  onTap: () => _openDuctLoras(site),
                ),
                _SectionTile(
                  icon: Icons.cell_tower_outlined,
                  title: 'Gateway',
                  subtitle: '$_gatewayCount recorded — tap to view',
                  status: _countStatus(_gatewayCount, site.blocks.length),
                  onTap: () => _openGateways(site),
                ),
                _SectionTile(
                  icon: Icons.notes_outlined,
                  title: 'Footer',
                  subtitle: _footerFilled
                      ? 'Filled — tap to view'
                      : 'Not filled',
                  status: _footerFilled
                      ? _SectionStatus.complete
                      : _SectionStatus.empty,
                  onTap: () => _openFooter(site),
                ),
                _SectionTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Generate BoM',
                  subtitle: _bomGenerated
                      ? 'Generated — tap to view'
                      : 'Not generated yet — tap to preview',
                  status: _bomGenerated
                      ? _SectionStatus.complete
                      : _SectionStatus.empty,
                  onTap: () => _openBomPreview(site),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _approving ? null : _approve,
                  icon: _approving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Approve'),
                ),
              ],
            ),
    );
  }
}

class _ReviewStatusBanner extends StatelessWidget {
  const _ReviewStatusBanner({required this.status});

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
            Icon(Icons.pending_actions_outlined, color: scheme.onSecondaryContainer),
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

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(value)),
    );
  }
}

/// A tappable section row that opens the real section screen in read-only
/// mode — mirrors [SiteHubScreen]'s `_SectionTile` look so the review screen
/// reads the same way the engineer's hub does.
class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _SectionStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget statusIcon = switch (status) {
      _SectionStatus.empty => Icon(
        Icons.radio_button_unchecked,
        color: scheme.outline,
      ),
      _SectionStatus.partial => const Icon(
        Icons.adjust,
        color: AppStatusColors.partial,
      ),
      _SectionStatus.complete => const Icon(
        Icons.check_circle,
        color: AppStatusColors.complete,
      ),
    };

    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: statusIcon,
        onTap: onTap,
      ),
    );
  }
}
