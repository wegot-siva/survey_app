import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/engineer.dart';
import '../models/site.dart';
import '../models/survey_status.dart';
import '../models/user_role.dart';
import '../services/session_controller.dart';
import '../services/survey_completeness.dart';
import '../services/sync_service.dart';
import 'approver_review_screen.dart';
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
import 'sync_scope.dart';
import 'widgets/refresh_bar.dart';
import 'theme/app_theme.dart';
import 'widgets/load_error_view.dart';

/// Completion state for one Site Hub section, shown as the row's trailing
/// indicator: [empty] means nothing has been recorded, [complete] means
/// something has.
///
/// Deliberately two states, matching [evaluateSurveyCompleteness] exactly —
/// the one rule that decides whether Submit warns about a section. There used
/// to be a third, `partial`, for the count-backed sections (source points,
/// inlet points, duct LoRa, gateways): "at least one entry, but fewer than
/// the site's block count". It was removed because the one-record-per-block
/// assumption behind it was never a real domain rule and produced states no
/// engineer could act on:
///
///   * Gateways can't reach it. [Gateway.blocksCovered] is a Set — one
///     gateway deliberately covers many blocks — so a correctly surveyed site
///     showed amber forever, and the only way to "fix" it was to invent
///     redundant hardware records.
///   * Adding a block silently downgraded finished sections, since the target
///     moved while the section itself hadn't changed.
///   * It contradicted Submit, which only ever flags sections with nothing at
///     all in them: an amber section submitted with no warning, so the hub
///     said "incomplete" while Submit said "fine".
///
/// How many records exist is still shown — as the row's subtitle ("3
/// recorded"), which states the count outright instead of encoding it in a
/// colour.
enum _SectionStatus { empty, complete }

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
    required this.syncService,
  });

  final SurveyRepository repository;
  final String siteId;
  final SessionController session;
  final SyncService syncService;

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
  /// True only until the very first read completes — after that the
  /// screen already has content worth keeping on screen, and a reload
  /// shows [RefreshBar] instead of replacing it. See [_load].
  bool _loading = true;
  Object? _loadError;
  bool _loadedOnce = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _refreshing = true);
    try {
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
        _loadedOnce = true;
        _loadError = null;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      // A failed refresh keeps whatever is already on screen — only a
      // first load, which has nothing to fall back to, hands over to
      // LoadErrorView.
      final hadContent = _loadedOnce;
      setState(() {
        _loading = false;
        _refreshing = false;
        _loadError = hadContent ? null : error;
      });
      if (hadContent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't refresh: $error")),
        );
      }
    }
  }

  /// Status for a count-backed section: anything recorded counts as done.
  /// Same rule [evaluateSurveyCompleteness] applies, so this indicator and
  /// the Submit warning can never disagree — see [_SectionStatus].
  _SectionStatus _countStatus(int count) =>
      count == 0 ? _SectionStatus.empty : _SectionStatus.complete;

  /// Gates the Admin-only "Fill test data" dev/QA shortcut on every survey
  /// section screen — see e.g. [ClientInputsScreen.isAdmin].
  bool get _isAdmin => widget.session.currentRole == UserRole.admin;

  Future<void> _openClientInputs(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClientInputsScreen(
          repository: widget.repository,
          site: site,
          isAdmin: _isAdmin,
        ),
      ),
    );
    await _load();
  }

  /// Opens the same read-only review screen the home list routes to, so
  /// approval has exactly one implementation regardless of how the Approver
  /// got here. Reloads afterwards, since approving changes the status this
  /// screen displays (and hides the button that opened it).
  Future<void> _openReview(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApproverReviewScreen(
          repository: widget.repository,
          siteId: site.id,
          session: widget.session,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openSourcePoints(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourcePointsListScreen(
          repository: widget.repository,
          site: site,
          isAdmin: _isAdmin,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openInletPoints(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InletPointsListScreen(
          repository: widget.repository,
          site: site,
          isAdmin: _isAdmin,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openDuctLoras(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DuctLorasListScreen(
          repository: widget.repository,
          site: site,
          isAdmin: _isAdmin,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openGateways(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GatewaysListScreen(
          repository: widget.repository,
          site: site,
          isAdmin: _isAdmin,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openFooter(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FooterScreen(
          repository: widget.repository,
          site: site,
          isAdmin: _isAdmin,
        ),
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
          addedByRole: widget.session.currentUserName ?? role?.label ?? 'Unknown',
          addedByUserId: widget.session.currentUserId,
          canEditBom: role == UserRole.admin || role == UserRole.approver,
        ),
      ),
    );
    // Read-only — no need to reload the hub afterwards.
  }

  Future<void> _openManageBlocks(Site site, {bool readOnly = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManageBlocksScreen(
          repository: widget.repository,
          site: site,
          readOnly: readOnly,
        ),
      ),
    );
    await _load();
  }

  /// Engineer's "I'm done" action — moves the survey to "submitted", which is
  /// what the Approver will act on in a later slice. Available any time before
  /// submission (covers re-opening a survey that's still "assigned" too, in
  /// case the auto in-progress transition didn't fire for some reason).
  ///
  /// Warns about empty sections and names them, but lets the engineer
  /// override. Deliberately a warning rather than a hard block, unlike
  /// Finalize's Group A safety net (BomPreviewScreen's `canFinalize`): that
  /// rule is unambiguous — a point either resolves to an active Group A
  /// material or it doesn't — whereas which survey sections are genuinely
  /// mandatory is not settled (see evaluateSurveyCompleteness's doc). A
  /// wrong blocking rule would strand an engineer on-site, unable to submit
  /// real work; a wrong warning is just a dialog they dismiss. The
  /// override also keeps legitimately-unusual sites workable — one with no
  /// Duct LoRa run, say.
  ///
  /// If nothing is empty the survey submits straight through, so the common
  /// case is unchanged: no dialog, one tap.
  Future<void> _markSubmitted(Site site) async {
    final completeness = evaluateSurveyCompleteness(
      site: site,
      sourcePointCount: _sourcePointCount,
      inletPointCount: _inletPointCount,
      ductLoraCount: _ductLoraCount,
      gatewayCount: _gatewayCount,
      footerFilled: _footerFilled,
    );
    if (!completeness.isComplete) {
      final proceed = await _confirmIncompleteSubmission(completeness);
      if (proceed != true) return;
      if (!mounted) return;
    }

    await widget.repository.updateSite(
      site.copyWith(status: SurveyStatus.submitted),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Survey submitted.')),
    );
    await _load();
  }

  /// Lists exactly which sections are empty and asks whether to submit
  /// anyway — the same "name what's missing" shape as the Group A banner on
  /// the BoM screen, so the two read consistently.
  Future<bool?> _confirmIncompleteSubmission(
    SurveyCompletenessResult completeness,
  ) {
    final count = completeness.gaps.length;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Some sections are empty'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count section${count == 1 ? ' has' : 's have'} nothing '
              'recorded:',
            ),
            const SizedBox(height: 12),
            for (final gap in completeness.gaps)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${gap.description}'),
              ),
            const SizedBox(height: 12),
            const Text(
              'You can still submit — only do so if these genuinely do not '
              'apply to this site.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit anyway'),
          ),
        ],
      ),
    );
  }

  /// Sales' "Edit assignee" action — offered in every status, so a survey can
  /// be handed over mid-work (see SurveyRepository's reassignment doc for why
  /// the old 'assigned'-only gate was removed). The engineer roster is a live
  /// Supabase query (real accounts — see SyncService.fetchEngineerRoster),
  /// so loading it can fail (no network); shown as an error dialog rather
  /// than silently offering an empty picker.
  ///
  /// Reassigning a survey the engineer has already started carries a real
  /// risk of losing anything they haven't synced yet, so that case asks for
  /// confirmation first — see [_confirmReassignInProgress].
  Future<void> _editAssignee(Site site) async {
    final List<Engineer> engineers;
    try {
      engineers = await widget.syncService.fetchEngineerRoster();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load the engineer list: $e')),
      );
      return;
    }
    if (!mounted) return;

    final newEngineer = await showDialog<Engineer>(
      context: context,
      builder: (context) => _ReassignDialog(
        currentAssigneeUserId: site.assignedToUserId,
        engineers: engineers,
      ),
    );
    if (newEngineer == null || newEngineer.id == site.assignedToUserId) return;

    // Only 'assigned' means the outgoing engineer definitely has nothing in
    // progress — every later status means they may have unsynced work that
    // the handover will strand.
    if (site.status != null && site.status != SurveyStatus.assigned) {
      final proceed = await _confirmReassignInProgress(site, newEngineer);
      if (proceed != true) return;
    }

    try {
      await widget.repository.reassignSurvey(
        siteId: site.id,
        newAssigneeUserId: newEngineer.id,
        newAssignee: newEngineer.name,
        changedByRole: widget.session.currentUserName ??
            widget.session.currentRole?.label ??
            'Unknown',
        changedByUserId: widget.session.currentUserId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reassigned to ${newEngineer.name}.')),
      );
      // Same reasoning as assign_survey_screen.dart's _assign: a
      // reassignment is a cross-device handoff to a different engineer's
      // account, and _load() below only re-reads local state — it doesn't
      // push anything.
      unawaited(SyncScope.read(context).requestSync(manual: false));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reassign: $e')),
      );
    }
  }

  /// Confirms handing over a survey the current engineer has already started.
  ///
  /// The warning is specific rather than generic because the risk is real and
  /// not obvious: every survey table's RLS is scoped by can_access_site(), so
  /// the moment this lands, anything the outgoing engineer recorded but hasn't
  /// synced can never be pushed — their writes are rejected and the rows are
  /// reconciled off their device. Their already-synced work is safe and stays
  /// on the survey; it does not follow them.
  Future<bool?> _confirmReassignInProgress(Site site, Engineer newEngineer) {
    final current = site.assignedTo ?? 'the current engineer';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hand over a started survey?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$current has already started this survey. '
              'Everything they have synced stays on the survey and '
              '${newEngineer.name} will see it.',
            ),
            const SizedBox(height: 12),
            Text(
              "Anything still only on $current's device — recorded while "
              'offline and not synced yet — will be lost. Ask them to sync '
              'before you continue if you are not sure.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Reassign to ${newEngineer.name}'),
          ),
        ],
      ),
    );
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
    // that touch surveyed content, not the create/assign role. Sales still
    // gets read-only visibility (canViewBlocks) — they already see all
    // sites, and the blocks RLS policy already permits them to read (see
    // can_access_site() in supabase/schema.sql); this only adds the app-side
    // view for it. Never grants Sales write access — that's a deliberate
    // app-level restriction on top of what RLS would technically allow.
    final canManageBlocks = isEngineer || isAdmin || isApprover;
    final canViewBlocks = canManageBlocks || isSales;
    final canSubmit =
        site?.status == SurveyStatus.assigned ||
        site?.status == SurveyStatus.inProgress;
    // No status gate: a survey can be handed over at any point in its life
    // (see _editAssignee). Reassigning a started survey warns first rather
    // than being blocked.
    // Approve is offered here only for a survey actually awaiting approval —
    // `submitted` is the one status that means that. Admin is included
    // alongside Approver deliberately: Admin already has every other
    // site-management capability on this screen, and had no way to unblock a
    // survey otherwise. Engineer and Sales never see it.
    final canApproveHere =
        site != null &&
        (isApprover || isAdmin) &&
        site.status == SurveyStatus.submitted;

    return Scaffold(
      appBar: AppBar(
        title: Text(site?.name ?? 'Site'),
        bottom: RefreshBar(active: _refreshing),
        actions: [
          if (site != null && canReassignRole)
            IconButton(
              tooltip: 'Reassignment history',
              onPressed: () => _openAssignmentLog(site),
              icon: const Icon(Icons.history),
            ),
          if (site != null && canReassignRole)
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
          : _loadError != null
          ? LoadErrorView(onRetry: _load, details: _loadError)
          : site == null
          ? const Center(child: Text('Site not found.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (site.status != null) _StatusBanner(status: site.status!),
                if (canViewBlocks)
                  _SectionTile(
                    icon: Icons.grid_view_outlined,
                    title: 'Blocks',
                    subtitle: site.blocks.isEmpty
                        ? (canManageBlocks
                              ? 'No blocks — tap to add'
                              : 'No blocks yet')
                        : site.blocks.join(', '),
                    status: site.blocks.isEmpty
                        ? _SectionStatus.empty
                        : _SectionStatus.complete,
                    onTap: () => _openManageBlocks(
                      site,
                      readOnly: !canManageBlocks,
                    ),
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
                  status: _countStatus(_sourcePointCount),
                  onTap: () => _openSourcePoints(site),
                ),
                _SectionTile(
                  icon: Icons.input_outlined,
                  title: 'Inlet points',
                  subtitle: '$_inletPointCount recorded',
                  status: _countStatus(_inletPointCount),
                  onTap: () => _openInletPoints(site),
                ),
                _SectionTile(
                  icon: Icons.router_outlined,
                  title: 'Duct LoRa',
                  subtitle: '$_ductLoraCount recorded',
                  status: _countStatus(_ductLoraCount),
                  onTap: () => _openDuctLoras(site),
                ),
                _SectionTile(
                  icon: Icons.cell_tower_outlined,
                  title: 'Gateway',
                  subtitle: '$_gatewayCount recorded',
                  status: _countStatus(_gatewayCount),
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
                // Approve path for a submitted survey. Previously the ONLY
                // route to the review screen was tapping the row on the home
                // list, and only while the status was exactly `submitted` —
                // so an Approver who arrived here any other way found no
                // Approve action and no explanation. Opens the same
                // ApproverReviewScreen rather than duplicating the approval
                // logic, so there stays exactly one place a survey can be
                // approved.
                if (canApproveHere) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openReview(site),
                      icon: const Icon(Icons.rule),
                      label: const Text('Review & Approve'),
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
/// with the survey's current assignee where possible. Pops the chosen
/// [Engineer], or null if cancelled.
class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({
    required this.currentAssigneeUserId,
    required this.engineers,
  });

  final String? currentAssigneeUserId;
  final List<Engineer> engineers;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  Engineer? _selected;

  @override
  void initState() {
    super.initState();
    // Falls back to no pre-selection (rather than a dropdown assertion
    // error) when the current assignee isn't in this roster — e.g. a
    // pre-Slice-1c site with no real assignedToUserId yet, or an engineer
    // account since deactivated.
    for (final engineer in widget.engineers) {
      if (engineer.id == widget.currentAssigneeUserId) {
        _selected = engineer;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit assignee'),
      content: DropdownButtonFormField<Engineer>(
        initialValue: _selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Assign to engineer',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final engineer in widget.engineers)
            DropdownMenuItem(value: engineer, child: Text(engineer.name)),
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
