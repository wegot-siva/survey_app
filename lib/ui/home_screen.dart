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
import 'theme/app_theme.dart';

/// State of the AppBar's Sync control — drives its icon/label/color. Session
/// only: resets to [idle] on app restart (see [_HomeScreenState._syncStatus]).
enum _SyncStatus { idle, syncing, success, failure }

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

  _SyncStatus _syncStatus = _SyncStatus.idle;

  /// Session-only — resets on app restart, not persisted.
  DateTime? _lastSyncedAt;

  final _searchController = TextEditingController();

  /// Lowercased, trimmed live from [_searchController] — see [_filteredSites].
  String _query = '';

  /// Whether the AppBar search field is showing in place of the "Sites"
  /// title — collapsed by default so it never takes up screen space until
  /// the user actually taps the search icon (see [_openSearch]).
  bool _searchOpen = false;

  /// [_sites] (the role-scoped list — unchanged) narrowed by [_query],
  /// case-insensitive substring match on site name only. Never bypasses
  /// role-based visibility: it only ever filters what [_visibleSites]
  /// already returned.
  List<Site> get _filteredSites => _query.isEmpty
      ? _sites
      : _sites
            .where((s) => s.name.toLowerCase().contains(_query))
            .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _load();
    // Catches the recurring "built without --dart-define-from-file=.env"
    // mistake at launch instead of a confusing sync-time error later — see
    // scripts/build_debug.ps1 / scripts/run_debug.ps1.
    if (!widget.supabaseService.isConfigured) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showMissingCredentialsDialog(),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showMissingCredentialsDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Built without credentials.'),
        content: const Text('Rebuild using scripts/build_debug.ps1.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
    setState(() => _syncStatus = _SyncStatus.syncing);

    final result = await widget.syncService.pushAll();
    if (!mounted) return;

    if (result.success) {
      setState(() {
        _syncStatus = _SyncStatus.success;
        _lastSyncedAt = DateTime.now();
      });
      final records = _syncRecordTotal(result);
      final photos = result.photos;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'All synced — $records record${records == 1 ? '' : 's'} and '
            '$photos photo${photos == 1 ? '' : 's'} backed up.',
          ),
        ),
      );
    } else {
      setState(() => _syncStatus = _SyncStatus.failure);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "Couldn't sync. Check your connection and try again.",
          ),
          action: SnackBarAction(label: 'Retry', onPressed: _syncNow),
        ),
      );
    }
  }

  /// Every per-table push count in [result] except photos, which the sync
  /// SnackBar reports as its own separate figure (see [_syncNow]).
  static int _syncRecordTotal(SyncResult result) =>
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
      result.bomManualEntries +
      result.bomSnapshots +
      result.bomRevisions +
      result.bomManualEditSnapshots;

  /// Whole-minute relative time since [_lastSyncedAt] — no new package,
  /// simple Duration math is enough at this granularity.
  String _lastSyncedLabel() {
    final at = _lastSyncedAt;
    if (at == null) return 'Synced';
    final minutes = DateTime.now().difference(at).inMinutes;
    return minutes < 1 ? 'Synced just now' : 'Synced ${minutes}m ago';
  }

  /// AppBar sync control — a single tappable status widget (replacing a
  /// plain "Sync now" icon button) that reflects [_syncStatus] and retriggers
  /// [_syncNow] on tap in every state.
  Widget _syncStatusButton() {
    final scheme = Theme.of(context).colorScheme;
    switch (_syncStatus) {
      case _SyncStatus.idle:
        return TextButton.icon(
          onPressed: _syncNow,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Sync'),
        );
      case _SyncStatus.syncing:
        return TextButton.icon(
          onPressed: null,
          icon: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('Syncing…'),
        );
      case _SyncStatus.success:
        return TextButton.icon(
          onPressed: _syncNow,
          icon: Icon(Icons.cloud_done, color: AppStatusColors.complete),
          label: Text(
            _lastSyncedLabel(),
            style: const TextStyle(color: AppStatusColors.complete),
          ),
        );
      case _SyncStatus.failure:
        return TextButton.icon(
          onPressed: _syncNow,
          icon: Icon(Icons.cloud_off, color: scheme.error),
          label: Text(
            'Sync failed — tap to retry',
            style: TextStyle(color: scheme.error),
          ),
        );
    }
  }

  /// Groups the Engineer's assigned surveys into three tabs by status —
  /// display only, no status transitions happen here. "Not started" is
  /// [SurveyStatus.assigned] (or no status at all, defensively); "In
  /// progress" is [SurveyStatus.inProgress] (set the moment the engineer
  /// opens an assigned survey — see [_openSite]); "Completed" covers
  /// [SurveyStatus.submitted] onward ([SurveyStatus.approved] /
  /// [SurveyStatus.released] included, since submitting is the engineer's
  /// last action on a survey — later Approver/Sales stages don't need their
  /// own engineer-facing tab).
  Widget _buildEngineerGroupedList(List<Site> sites) {
    final notStarted = sites
        .where((s) => s.status == SurveyStatus.assigned || s.status == null)
        .toList(growable: false);
    final inProgress = sites
        .where((s) => s.status == SurveyStatus.inProgress)
        .toList(growable: false);
    final completed = sites
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
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No surveys in this group yet.'
                          : 'No sites found.',
                    ),
                  ),
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

  /// Groups Sales' surveys into two tabs by status — display only, no status
  /// transitions happen here (mirrors [_buildEngineerGroupedList]). "Assigned"
  /// covers everything not yet fully approved ([SurveyStatus.assigned],
  /// [SurveyStatus.inProgress], [SurveyStatus.submitted], or no status at
  /// all, defensively); "Completed" is [SurveyStatus.approved] /
  /// [SurveyStatus.released] — the same two statuses the existing row
  /// subtitle already treats as "ready" (see [_salesSiteTile]).
  Widget _buildSalesGroupedList(List<Site> sites) {
    final assigned = sites
        .where(
          (s) =>
              s.status == SurveyStatus.assigned ||
              s.status == SurveyStatus.inProgress ||
              s.status == SurveyStatus.submitted ||
              s.status == null,
        )
        .toList(growable: false);
    final completed = sites
        .where(
          (s) =>
              s.status == SurveyStatus.approved ||
              s.status == SurveyStatus.released,
        )
        .toList(growable: false);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              _tabLabelWithBadge(context, 'Assigned', assigned.length),
              _tabLabelWithBadge(context, 'Completed', completed.length),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _salesSiteGroupList(assigned),
                _salesSiteGroupList(completed),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _salesSiteGroupList(List<Site> sites) {
    return RefreshIndicator(
      onRefresh: _load,
      child: sites.isEmpty
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No surveys in this group yet.'
                          : 'No sites found.',
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              itemCount: sites.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _salesSiteTile(sites[i]),
            ),
    );
  }

  /// Same row rendering the flat list already used for Sales — extracted so
  /// the grouped tabs and the (untouched) flat list for other roles don't
  /// duplicate-and-drift.
  Widget _salesSiteTile(Site site) {
    final isReadyForSales =
        site.status == SurveyStatus.approved ||
        site.status == SurveyStatus.released;
    return ListTile(
      leading: const Icon(Icons.location_city_outlined),
      title: Text(site.name),
      subtitle: Text(
        isReadyForSales
            ? 'Approved · ready  ·  Assigned to: '
                  '${site.assignedTo ?? 'Unassigned'}'
            : 'Assigned to: ${site.assignedTo ?? 'Unassigned'} '
                  '· Status: ${site.status ?? 'Not assigned'}',
      ),
      trailing: isReadyForSales
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.chevron_right),
      onTap: () => _openSite(site),
    );
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
  }

  /// Closes the AppBar search field and clears whatever was typed, restoring
  /// the full role-scoped list — collapsing back to the icon is also how the
  /// user "clears" the search, not just the field's own clear button.
  void _closeSearch() {
    _searchController.clear();
    setState(() => _searchOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(
                  color: Theme.of(context).appBarTheme.foregroundColor ??
                      Theme.of(context).colorScheme.onSurface,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search sites by name',
                  border: InputBorder.none,
                ),
              )
            : const Text('Sites'),
        actions: _searchOpen
            ? [
                IconButton(
                  tooltip: 'Close search',
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.close),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Search sites',
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search),
                ),
                if (widget.session.currentRole == UserRole.admin)
                  IconButton(
                    tooltip: 'Material Master',
                    onPressed: _openMaterialMaster,
                    icon: const Icon(Icons.inventory_2_outlined),
                  ),
                // Developer diagnostic — compiled out of release builds
                // entirely. This is a build-type concern (dev vs field), not
                // a role/permission one, so kDebugMode is the right gate,
                // not an admin-role check.
                if (kDebugMode)
                  IconButton(
                    tooltip: 'Test Supabase connection',
                    onPressed: _testSupabase,
                    icon: const Icon(Icons.cloud_outlined),
                  ),
                _syncStatusButton(),
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
              icon: const Icon(Icons.post_add),
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
                : _filteredSites.isEmpty
                ? const Center(child: Text('No sites found.'))
                : widget.session.currentRole == UserRole.engineer
                ? _buildEngineerGroupedList(_filteredSites)
                : widget.session.currentRole == UserRole.sales
                ? _buildSalesGroupedList(_filteredSites)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: _filteredSites.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final site = _filteredSites[i];
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
