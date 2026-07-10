import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/engineer.dart';
import '../models/site.dart';
import '../models/survey_status.dart';
import '../models/user_role.dart';
import '../services/session_controller.dart';
import 'bom_preview_screen.dart';
import 'client_inputs_screen.dart';
import 'duct_loras_list_screen.dart';
import 'edit_site_details_screen.dart';
import 'footer_screen.dart';
import 'gateways_list_screen.dart';
import 'inlet_points_list_screen.dart';
import 'manage_blocks_screen.dart';
import 'source_points_list_screen.dart';
import 'survey_assignment_audit_log_screen.dart';
import 'theme/app_theme.dart';

/// Completion state for one Site Hub section, shown as the row's trailing
/// indicator. For sections backed by an open-ended count (source points,
/// inlet points, duct LoRa, gateways) [partial] means at least one entry
/// exists but fewer than the site's block count — [complete] once the count
/// reaches or exceeds it. Binary sections (client inputs, footer, blocks,
/// BoM) only ever report [empty] or [complete].
enum _SectionStatus { empty, partial, complete }

/// Actions in Site Hub's "Manage site" overflow menu — see [canReassignRole].
enum _SiteManageAction { editDetails, delete }

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
  bool _bomGenerated = false;
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
    final role = widget.session.currentRole;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BomPreviewScreen(
          repository: widget.repository,
          site: site,
          addedByRole: role?.label ?? 'Unknown',
          canEditBom: role == UserRole.admin || role == UserRole.approver,
        ),
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
  /// Submits directly — no confirmation dialog (it only ever asked yes/no,
  /// it never validated anything, so there's nothing to preserve).
  Future<void> _markSubmitted(Site site) async {
    await widget.repository.updateSite(
      site.copyWith(status: SurveyStatus.submitted),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Survey submitted.')),
    );
    await _load();
  }

  /// Sales' "Edit assignee" action — only ever offered while [site] is still
  /// 'assigned' (gated by the caller), so a reassignment can never happen
  /// after an engineer has started work.
  Future<void> _editAssignee(Site site) async {
    final engineers = await widget.repository.getEngineers();
    if (!mounted) return;

    final newAssignee = await showDialog<String>(
      context: context,
      builder: (context) => _ReassignDialog(
        currentAssignee: site.assignedTo,
        engineers: engineers,
      ),
    );
    if (newAssignee == null || newAssignee == site.assignedTo) return;

    try {
      await widget.repository.reassignSurvey(
        siteId: site.id,
        newAssignee: newAssignee,
        changedByRole: widget.session.currentRole?.label ?? 'Unknown',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reassigned to $newAssignee.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reassign: $e')),
      );
    }
  }

  Future<void> _openAssignmentLog(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SurveyAssignmentAuditLogScreen(
          repository: widget.repository,
          siteId: site.id,
          siteName: site.name,
        ),
      ),
    );
  }

  /// Sales' "Edit site details" action — name/address/client contact only;
  /// never touches blocks or the Client Inputs survey section.
  Future<void> _openEditSiteDetails(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EditSiteDetailsScreen(repository: widget.repository, site: site),
      ),
    );
    await _load();
  }

  /// Sales' "Delete site" action — soft-delete only: sets [Site.archived] so
  /// the site drops off every active list, but its row and every FK'd
  /// survey/BoM/photo record are left exactly as they are. Available
  /// regardless of survey status (unlike reassignment).
  Future<void> _deleteSite(Site site) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete site?'),
        content: const Text(
          'This hides it from all site lists. Survey data, BoM, and photos '
          'are kept — nothing is permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.repository.updateSite(site.copyWith(archived: true));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Site deleted.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    final isEngineer = widget.session.currentRole == UserRole.engineer;
    final isSales = widget.session.currentRole == UserRole.sales;
    final isAdmin = widget.session.currentRole == UserRole.admin;
    final isApprover = widget.session.currentRole == UserRole.approver;
    // Admin and Approver get the same reassignment/config capabilities as
    // Sales — deliberately NOT Submit (Engineer-only). Approve never routes
    // through this screen at all (submitted surveys go to the Approver's
    // read-only review screen instead — see home_screen.dart's row-tap logic).
    final canReassignRole = isSales || isAdmin || isApprover;
    // Blocks are created during the survey, not at site creation (Sales
    // never enters them) — so block *management* follows the same roles
    // that touch surveyed content, not the create/assign role.
    final canManageBlocks = isEngineer || isAdmin || isApprover;
    final canSubmit =
        site?.status == SurveyStatus.assigned ||
        site?.status == SurveyStatus.inProgress;
    final canReassign = site?.status == SurveyStatus.assigned;

    return Scaffold(
      appBar: AppBar(
        title: Text(site?.name ?? 'Site'),
        actions: [
          if (site != null && canReassignRole)
            IconButton(
              tooltip: 'Reassignment history',
              onPressed: () => _openAssignmentLog(site),
              icon: const Icon(Icons.history),
            ),
          if (site != null && canReassignRole && canReassign)
            IconButton(
              tooltip: 'Edit assignee',
              onPressed: () => _editAssignee(site),
              icon: const Icon(Icons.person_outline),
            ),
          if (site != null && canReassignRole)
            PopupMenuButton<_SiteManageAction>(
              tooltip: 'Manage site',
              onSelected: (action) {
                switch (action) {
                  case _SiteManageAction.editDetails:
                    _openEditSiteDetails(site);
                  case _SiteManageAction.delete:
                    _deleteSite(site);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _SiteManageAction.editDetails,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit site details'),
                  ),
                ),
                PopupMenuItem(
                  value: _SiteManageAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete site'),
                  ),
                ),
              ],
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
                if (canManageBlocks)
                  _SectionTile(
                    icon: Icons.grid_view_outlined,
                    title: 'Blocks',
                    subtitle: site.blocks.isEmpty
                        ? 'No blocks — tap to add'
                        : site.blocks.join(', '),
                    status: site.blocks.isEmpty
                        ? _SectionStatus.empty
                        : _SectionStatus.complete,
                    onTap: () => _openManageBlocks(site),
                  ),
                _SectionTile(
                  icon: Icons.assignment_outlined,
                  title: 'Client inputs',
                  subtitle: site.clientInputs != null
                      ? 'Filled'
                      : 'Not filled yet',
                  status: site.clientInputs != null
                      ? _SectionStatus.complete
                      : _SectionStatus.empty,
                  onTap: () => _openClientInputs(site),
                ),
                _SectionTile(
                  icon: Icons.water_drop_outlined,
                  title: 'Source points',
                  subtitle: '$_sourcePointCount recorded',
                  status: _countStatus(_sourcePointCount, site.blocks.length),
                  onTap: () => _openSourcePoints(site),
                ),
                _SectionTile(
                  icon: Icons.input_outlined,
                  title: 'Inlet points',
                  subtitle: '$_inletPointCount recorded',
                  status: _countStatus(_inletPointCount, site.blocks.length),
                  onTap: () => _openInletPoints(site),
                ),
                _SectionTile(
                  icon: Icons.router_outlined,
                  title: 'Duct LoRa',
                  subtitle: '$_ductLoraCount recorded',
                  status: _countStatus(_ductLoraCount, site.blocks.length),
                  onTap: () => _openDuctLoras(site),
                ),
                _SectionTile(
                  icon: Icons.cell_tower_outlined,
                  title: 'Gateway',
                  subtitle: '$_gatewayCount recorded',
                  status: _countStatus(_gatewayCount, site.blocks.length),
                  onTap: () => _openGateways(site),
                ),
                _SectionTile(
                  icon: Icons.notes_outlined,
                  title: 'Footer',
                  subtitle: _footerFilled ? 'Filled' : 'Not filled yet',
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
                      : 'Preview the computed bill of materials',
                  status: _bomGenerated
                      ? _SectionStatus.complete
                      : _SectionStatus.empty,
                  onTap: () => _openBomPreview(site),
                ),
                if (isEngineer && canSubmit) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _markSubmitted(site),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Submit for Approval'),
                    ),
                  ),
                ],
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
  final VoidCallback? onTap;

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
        enabled: onTap != null,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: statusIcon,
        onTap: onTap,
      ),
    );
  }
}

/// Sales' "Edit assignee" dialog — a dropdown of the engineer roster, seeded
/// with the survey's current assignee. Pops the chosen name, or null if
/// cancelled.
class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({required this.currentAssignee, required this.engineers});

  final String? currentAssignee;
  final List<Engineer> engineers;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentAssignee;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit assignee'),
      content: DropdownButtonFormField<String>(
        initialValue: _selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Assign to engineer',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final engineer in widget.engineers)
            DropdownMenuItem(value: engineer.name, child: Text(engineer.name)),
        ],
        onChanged: (v) => setState(() => _selected = v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Reassign'),
        ),
      ],
    );
  }
}
