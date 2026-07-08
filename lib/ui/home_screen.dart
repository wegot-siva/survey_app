import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import '../models/survey_status.dart';
import '../models/user_role.dart';
import '../services/session_controller.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import 'approver_review_screen.dart';
import 'assign_survey_screen.dart';
import 'create_site_screen.dart';
import 'material_master_screen.dart';
import 'site_hub_screen.dart';

/// Lists all sites and offers a button to create a new one.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.supabaseService,
    required this.syncService,
    required this.session,
  });

  final SurveyRepository repository;
  final SupabaseService supabaseService;
  final SyncService syncService;
  final SessionController session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Site> _sites = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sites = await widget.repository.getSites();
    if (!mounted) return;
    setState(() {
      _sites = _visibleSites(sites);
      _loading = false;
    });
  }

  /// Engineer sees only their own assigned surveys (Slice C); Sales, Admin,
  /// and Approver all see everything (Approver gained Sales-like create/
  /// assign/reassign capability, so it needs the same full visibility to
  /// find sites to manage — not just ones awaiting review; the row-tap logic
  /// below still routes a submitted survey to the read-only review screen).
  /// Admin has no survey-list filtering — only the Material Master entry
  /// point is role-gated to them.
  List<Site> _visibleSites(List<Site> sites) {
    switch (widget.session.currentRole) {
      case UserRole.engineer:
        final engineer = widget.session.currentEngineerName;
        if (engineer == null) return const [];
        return sites
            .where((s) => s.assignedTo == engineer)
            .toList(growable: false);
      case UserRole.approver:
      case UserRole.sales:
      case UserRole.admin:
      case null:
        return sites;
    }
  }

  Future<void> _openCreateSite() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateSiteScreen(repository: widget.repository),
      ),
    );
    await _load();
  }

  Future<void> _openAssignSurvey() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssignSurveyScreen(repository: widget.repository),
      ),
    );
    await _load();
  }

  Future<void> _openSite(Site site) async {
    // Engineer opening a freshly-assigned survey starts work on it. Guarded
    // to "assigned" only, so reopening an already in-progress/submitted
    // survey never regresses its status.
    if (widget.session.currentRole == UserRole.engineer &&
        site.status == SurveyStatus.assigned) {
      await widget.repository.updateSite(
        site.copyWith(status: SurveyStatus.inProgress),
      );
      if (!mounted) return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SiteHubScreen(
          repository: widget.repository,
          siteId: site.id,
          session: widget.session,
        ),
      ),
    );
    await _load();
  }

  /// Approver's read-only review (Slice D) — separate from [_openSite] so
  /// reviewing never triggers the engineer's "open == start work" transition
  /// and never offers edit access to the survey forms.
  Future<void> _openReview(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApproverReviewScreen(
          repository: widget.repository,
          siteId: site.id,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openMaterialMaster() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MaterialMasterScreen(
          repository: widget.repository,
          changedByRole: widget.session.currentRole?.label ?? 'Unknown',
        ),
      ),
    );
  }

  Future<void> _testSupabase() async {
    final messenger = ScaffoldMessenger.of(context)
      ..showSnackBar(
        const SnackBar(content: Text('Testing Supabase connection…')),
      );

    final result = await widget.supabaseService.testConnection();
    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          result.success ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        ),
        title: Text(result.success ? 'Supabase connected' : 'Connection failed'),
        content: SingleChildScrollView(child: SelectableText(result.message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(
          'You are signed in as ${widget.session.currentRole?.label ?? 'a role'}. '
          'Log out to switch roles?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.session.logout();
  }

  Future<void> _syncNow() async {
    final messenger = ScaffoldMessenger.of(context)
      ..showSnackBar(
        const SnackBar(content: Text('Syncing to Supabase…')),
      );

    final result = await widget.syncService.pushAll();
    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          result.success ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        ),
        title: Text(result.success ? 'Sync complete' : 'Sync failed'),
        content: SingleChildScrollView(
          child: result.success
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Synced ${_syncItemTotal(result)} item(s) to Supabase.',
                    ),
                    Theme(
                      // ExpansionTile paints its own divider lines; hide them
                      // so it sits flush inside the dialog.
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        title: const Text('Show details'),
                        children: [
                          Text(
                            '• ${result.sites} site(s)\n'
                            '• ${result.blocks} block(s)\n'
                            '• ${result.clientInputs} client input form(s)\n'
                            '• ${result.sourcePoints} source point(s)\n'
                            '• ${result.inletPoints} inlet point(s)\n'
                            '• ${result.ductLoras} Duct LoRa unit(s)\n'
                            '• ${result.gateways} gateway(s)\n'
                            '• ${result.footers} footer form(s)\n'
                            '• ${result.materialMasterItems} material master item(s)\n'
                            '• ${result.materialMasterAuditEntries} change log entr'
                            '${result.materialMasterAuditEntries == 1 ? 'y' : 'ies'}\n'
                            '• ${result.photos} photo(s)\n'
                            '• ${result.bomManualEntries} manual BoM entr'
                            '${result.bomManualEntries == 1 ? 'y' : 'ies'}\n'
                            '• ${result.bomSnapshots} finalized BoM snapshot'
                            '${result.bomSnapshots == 1 ? '' : 's'}\n'
                            '• ${result.bomRevisions} BoM revision'
                            '${result.bomRevisions == 1 ? '' : 's'}',
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : SelectableText(result.message ?? 'Unknown error.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Sum of every per-table push count in [result] — the single number the
  /// sync dialog leads with, before the itemized "Show details" breakdown.
  static int _syncItemTotal(SyncResult result) =>
      result.sites +
      result.blocks +
      result.clientInputs +
      result.sourcePoints +
      result.inletPoints +
      result.ductLoras +
      result.gateways +
      result.footers +
      result.materialMasterItems +
      result.materialMasterAuditEntries +
      result.photos +
      result.bomManualEntries +
      result.bomSnapshots +
      result.bomRevisions;

  /// Groups the Engineer's assigned surveys into three tabs by status —
  /// display only, no status transitions happen here. "Not started" is
  /// [SurveyStatus.assigned] (or no status at all, defensively); "In
  /// progress" is [SurveyStatus.inProgress] (set the moment the engineer
  /// opens an assigned survey — see [_openSite]); "Completed" covers
  /// [SurveyStatus.submitted] onward ([SurveyStatus.approved] /
  /// [SurveyStatus.released] included, since submitting is the engineer's
  /// last action on a survey — later Approver/Sales stages don't need their
  /// own engineer-facing tab).
  Widget _buildEngineerGroupedList() {
    final notStarted = _sites
        .where((s) => s.status == SurveyStatus.assigned || s.status == null)
        .toList(growable: false);
    final inProgress = _sites
        .where((s) => s.status == SurveyStatus.inProgress)
        .toList(growable: false);
    final completed = _sites
        .where(
          (s) =>
              s.status == SurveyStatus.submitted ||
              s.status == SurveyStatus.approved ||
              s.status == SurveyStatus.released,
        )
        .toList(growable: false);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              _tabLabelWithBadge(context, 'Not started', notStarted.length),
              _tabLabelWithBadge(context, 'In progress', inProgress.length),
              _tabLabelWithBadge(context, 'Completed', completed.length),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _engineerSiteGroupList(notStarted),
                _engineerSiteGroupList(inProgress),
                _engineerSiteGroupList(completed),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A tab label paired with a small Material [Badge] showing [count] —
  /// replaces baking the count into the label text itself, which could
  /// overflow a tab's narrow (1/3 of screen width) slot on small devices,
  /// especially at 2+ digits. The label is [Flexible] so it's the part that
  /// degrades (ellipsis) if a device is narrow enough to squeeze this row;
  /// the badge is a fixed-size sibling and always shows the full count.
  Tab _tabLabelWithBadge(BuildContext context, String label, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
          const SizedBox(width: 6),
          Badge(
            backgroundColor: scheme.primary,
            textColor: scheme.onPrimary,
            label: Text('$count'),
          ),
        ],
      ),
    );
  }

  Widget _engineerSiteGroupList(List<Site> sites) {
    return RefreshIndicator(
      onRefresh: _load,
      child: sites.isEmpty
          // Still wrapped in a scrollable, so pull-to-refresh works even on
          // an empty tab.
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No surveys in this group yet.')),
                ),
              ],
            )
          : ListView.separated(
              itemCount: sites.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _engineerSiteTile(sites[i]),
            ),
    );
  }

  /// Same row rendering the flat list already used for Engineer — extracted
  /// so the grouped tabs and the (untouched) flat list for other roles don't
  /// duplicate-and-drift.
  Widget _engineerSiteTile(Site site) {
    return ListTile(
      leading: const Icon(Icons.location_city_outlined),
      title: Text(site.name),
      subtitle: Text('Status: ${site.status ?? 'Not assigned'}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openSite(site),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sites'),
        actions: [
          if (widget.session.currentRole == UserRole.admin)
            IconButton(
              tooltip: 'Material Master',
              onPressed: _openMaterialMaster,
              icon: const Icon(Icons.inventory_2_outlined),
            ),
          // Developer diagnostic — compiled out of release builds entirely.
          // This is a build-type concern (dev vs field), not a role/permission
          // one, so kDebugMode is the right gate, not an admin-role check.
          if (kDebugMode)
            IconButton(
              tooltip: 'Test Supabase connection',
              onPressed: _testSupabase,
              icon: const Icon(Icons.cloud_outlined),
            ),
          IconButton(
            tooltip: 'Sync now (push to Supabase)',
            onPressed: _syncNow,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      // Admin and Approver get the same create+assign flow as Sales. Engineer
      // creates nothing — sites/surveys reach them already assigned — so no
      // FAB at all, rather than a "New site" action Engineer never uses.
      floatingActionButton: widget.session.currentRole == UserRole.engineer
          ? null
          : widget.session.currentRole == UserRole.sales ||
                widget.session.currentRole == UserRole.admin ||
                widget.session.currentRole == UserRole.approver
          ? FloatingActionButton.extended(
              onPressed: _openAssignSurvey,
              icon: const Icon(Icons.add_task),
              label: const Text('New survey'),
            )
          : FloatingActionButton.extended(
              onPressed: _openCreateSite,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('New site'),
            ),
      body: Column(
        children: [
          _RoleBanner(role: widget.session.currentRole),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sites.isEmpty
                ? _EmptyState(role: widget.session.currentRole)
                : widget.session.currentRole == UserRole.engineer
                ? _buildEngineerGroupedList()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: _sites.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final site = _sites[i];
                        final hasInputs = site.clientInputs != null;
                        final role = widget.session.currentRole;
                        final isSales = role == UserRole.sales;
                        final isEngineer = role == UserRole.engineer;
                        final isApprover = role == UserRole.approver;
                        final isReadyForSales =
                            site.status == SurveyStatus.approved ||
                            site.status == SurveyStatus.released;
                        return ListTile(
                          leading: const Icon(Icons.location_city_outlined),
                          title: Text(site.name),
                          subtitle: Text(
                            isSales
                                ? (isReadyForSales
                                      ? 'Approved · ready  ·  Assigned to: '
                                            '${site.assignedTo ?? 'Unassigned'}'
                                      : 'Assigned to: ${site.assignedTo ?? 'Unassigned'} '
                                            '· Status: ${site.status ?? 'Not assigned'}')
                                : isEngineer
                                ? 'Status: ${site.status ?? 'Not assigned'}'
                                : isApprover
                                ? 'Assigned to: ${site.assignedTo ?? 'Unassigned'} '
                                      '· Status: ${site.status ?? 'Not assigned'}'
                                : '${site.blocks.length} block(s)  •  '
                                      '${hasInputs ? 'Client inputs saved' : 'No client inputs yet'}',
                          ),
                          trailing: isSales && isReadyForSales
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : const Icon(Icons.chevron_right),
                          // Approver only gets the read-only review screen
                          // once a survey is actually submitted; for any
                          // earlier status (e.g. one they just created and
                          // assigned) they open the Site Hub, same as Sales,
                          // which is where reassignment lives.
                          onTap: () =>
                              (isApprover && site.status == SurveyStatus.submitted)
                              ? _openReview(site)
                              : _openSite(site),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A slim header showing which role is signed in.
class _RoleBanner extends StatelessWidget {
  const _RoleBanner({required this.role});

  final UserRole? role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Text(
            'Signed in as ${role?.label ?? 'Unknown'}',
            style: TextStyle(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.role});

  final UserRole? role;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String subtitle;
    switch (role) {
      case UserRole.sales:
        title = 'No sites yet';
        subtitle = 'Tap "New survey" to create and assign your first one.';
      case UserRole.engineer:
        title = 'No surveys assigned to you';
        subtitle = 'Sales hasn\'t assigned you a survey yet.';
      case UserRole.approver:
        title = 'Nothing to review';
        subtitle = 'No surveys have been submitted yet.';
      case UserRole.admin:
      case null:
        title = 'No sites yet';
        subtitle = 'Tap "New site" to add your first one.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 64),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
