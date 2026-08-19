import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import '../models/survey_status.dart';
import '../models/user_role.dart';
import '../services/session_controller.dart';
import '../services/supabase_service.dart';
import '../services/sync_controller.dart';
import '../services/sync_service.dart';
import 'approver_review_screen.dart';
import 'assign_survey_screen.dart';
import 'create_site_screen.dart';
import 'edit_site_details_screen.dart';
import 'material_master_group_list_screen.dart';
import 'site_hub_screen.dart';
import 'sync_scope.dart';
import 'widgets/refresh_bar.dart';
import 'theme/app_theme.dart';
import 'widgets/load_error_view.dart';

/// Entries in the AppBar's overflow menu — Search and Sync stay directly
/// visible (Sync via [_syncStatusButton], not a menu entry); everything else
/// moves in here to keep the AppBar from getting crowded, same pattern as
/// Material Master's own AppBar. Each item is individually conditional
/// (role/build-type gated) in [_HomeScreenState.build] — new admin actions
/// added later go here too, rather than back onto the AppBar itself.
enum _HomeMoreMenuAction { materialMaster, testConnection, logout }

/// Which quick action a Site card's long-press bottom sheet resolved to —
/// null means the user tapped Cancel or dismissed it.
enum _SiteQuickAction { edit, delete }

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
  /// True only until the very first read completes — after that the
  /// screen already has content worth keeping on screen, and a reload
  /// shows [RefreshBar] instead of replacing it. See [_load].
  bool _loading = true;
  Object? _loadError;
  bool _loadedOnce = false;
  bool _refreshing = false;

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
    // Auto-sync on login: this screen is only ever built fresh right after a
    // successful login, a fresh install's first login, or an account switch
    // (main.dart's _AuthGateState builds a brand-new HomeScreen +
    // SyncController per signed-in account), so triggering here covers all
    // three. Routed through SyncController — not SyncService directly — so
    // this run shares the exact same single-flight/debounce/cooldown gates
    // as the manual Sync button and every other automatic trigger: a manual
    // tap that lands while this is still debouncing supersedes it, and one
    // that lands once it's already running just joins it, so there's never a
    // duplicate/overlapping run. Offline-first: [_load] above already showed
    // local data synchronously, so this never blocks getting into the app —
    // it only refreshes what's on screen once the pull half lands, exactly
    // like every other automatic trigger reported nowhere but the AppBar
    // indicator (see [SyncController]'s doc and [_presentSyncOutcome]'s —
    // a failure here degrades to that same non-intrusive indicator, never a
    // dialog or SnackBar).
    unawaited(
      SyncScope.read(context).requestSync(manual: false).then((_) {
        if (mounted) _load();
      }),
    );
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
    if (!_loading) setState(() => _refreshing = true);
    try {
      final sites = await widget.repository.getSites();
      if (!mounted) return;
      setState(() {
        _sites = _visibleSites(sites);
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

  /// Engineer sees only their own assigned surveys (Slice C, now matched by
  /// real account id — Slice 1c — not the old free-text name string); Sales,
  /// Admin, and Approver all see everything (Approver gained Sales-like
  /// create/assign/reassign capability, so it needs the same full visibility
  /// to find sites to manage — not just ones awaiting review; the row-tap
  /// logic below still routes a submitted survey to the read-only review
  /// screen). Admin has no survey-list filtering — only the Material Master
  /// entry point is role-gated to them.
  List<Site> _visibleSites(List<Site> sites) {
    switch (widget.session.currentRole) {
      case UserRole.engineer:
        final userId = widget.session.currentUserId;
        if (userId == null) return const [];
        return sites
            .where((s) => s.assignedToUserId == userId)
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
        builder: (_) => AssignSurveyScreen(
          repository: widget.repository,
          syncService: widget.syncService,
        ),
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
          syncService: widget.syncService,
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
          session: widget.session,
        ),
      ),
    );
    await _load();
  }

  /// Sales, Admin, and Approver can edit/delete a site from here — same role
  /// scope as Site Hub's own "Manage site" menu (`canReassignRole` there).
  /// Engineer never gets this: they execute assigned surveys, not manage them.
  bool get _canManageSites =>
      widget.session.currentRole == UserRole.sales ||
      widget.session.currentRole == UserRole.admin ||
      widget.session.currentRole == UserRole.approver;

  /// Long-press quick actions for a Site card — Edit/Delete/Cancel. Mirrors
  /// Site Hub's "Manage site" overflow menu, just reachable without opening
  /// the site first.
  ///
  /// A modal bottom sheet (not a dialog) is the right Android-native pattern
  /// here: this is a small set of contextual actions triggered from a
  /// long-press on a list item, not a decision that needs an explicit
  /// OK/Cancel choice — dialogs interrupt for exactly that latter case.
  /// Styled per Material 3: a native drag handle, rounded top corners, a
  /// site-name header so it's clear which site the sheet applies to, Delete
  /// marked destructive with the theme's error color, and Cancel visually
  /// separated below a divider rather than sitting as a fourth equal option.
  Future<void> _showSiteActions(Site site) async {
    final scheme = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<_SiteQuickAction>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  site.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Site'),
              onTap: () => Navigator.of(context).pop(_SiteQuickAction.edit),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Delete Site', style: TextStyle(color: scheme.error)),
              onTap: () => Navigator.of(context).pop(_SiteQuickAction.delete),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Divider(height: 1),
            ),
            ListTile(
              title: const Text('Cancel', textAlign: TextAlign.center),
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _SiteQuickAction.edit:
        await _openEditSiteDetails(site);
      case _SiteQuickAction.delete:
        await _deleteSite(site);
      case null:
        break;
    }
  }

  Future<void> _openEditSiteDetails(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EditSiteDetailsScreen(repository: widget.repository, site: site),
      ),
    );
    await _load();
  }

  /// Soft-delete only — sets [Site.archived] so the site drops off every
  /// active list, but its row and every FK'd survey/BoM/photo record are
  /// left exactly as they are. [Site.archived] is a local-only field (never
  /// pushed to Supabase — see [SqfliteSurveyRepository._pullAndReconcile]'s
  /// doc), so this can never orphan a synced remote row; the site itself
  /// keeps syncing normally, it just stops showing up in [getSites]'s
  /// default (non-archived) result. Same mechanism as Site Hub's own
  /// "Delete site" action — not a new one.
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
    await _load();
  }

  Future<void> _openMaterialMaster() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MaterialMasterGroupListScreen(
          repository: widget.repository,
          changedByRole: widget.session.currentUserName ??
              widget.session.currentRole?.label ??
              'Unknown',
          changedByUserId: widget.session.currentUserId,
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
    final name = widget.session.currentUserName?.trim();
    final roleLabel = widget.session.currentRole?.label ?? 'a role';
    final identity = (name == null || name.isEmpty)
        ? 'signed in as $roleLabel'
        : 'signed in as $name ($roleLabel)';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: Text('You are $identity. Log out to switch roles?'),
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

  /// The manual Sync button (and the failure SnackBar's Retry action).
  /// Orchestration and status now live in [SyncController]; this method is
  /// only responsible for refreshing the visible list afterwards and
  /// reporting the result.
  Future<void> _syncNow() async {
    final outcome = await SyncScope.read(context).requestSync(manual: true);
    if (!mounted) return;

    // Refresh the visible list regardless of outcome — whatever DID pull
    // down should show even if the push half had rejected rows.
    await _load();
    if (!mounted) return;

    // Non-null for a manual request — it bypasses the debounce/cooldown
    // gates that are the only reasons a run is skipped — but checked rather
    // than forced, so a future change to those gates degrades to "no
    // SnackBar" instead of a crash.
    if (outcome != null) _presentSyncOutcome(outcome);
  }

  /// Turns a finished sync run into the user-facing SnackBar. Presentation
  /// only — every status decision was already made in [SyncController].
  ///
  /// Reached only from the manual path: an automatic sync deliberately
  /// reports nothing here, leaving the AppBar indicator as its sole signal
  /// (a SnackBar interrupting form entry would be intrusive, and the
  /// failure/needs-attention indicator already persists rather than fading).
  void _presentSyncOutcome(SyncOutcome outcome) {
    switch (outcome.status) {
      case SyncStatus.success:
        final records = outcome.records;
        final photos = outcome.photos;
        final pulled = outcome.materialMasterPulled;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'All synced — $records record${records == 1 ? '' : 's'} and '
              '$photos photo${photos == 1 ? '' : 's'} backed up'
              '${pulled > 0 ? ', $pulled Material Master item${pulled == 1 ? '' : 's'} updated' : ''}.',
            ),
          ),
        );
      case SyncStatus.partial:
        final blocked = outcome.blocked;
        final preserved = outcome.preservedSites;
        // A site kept back because it holds work the account can no longer
        // push is named outright, not folded into a count — "1 item needs
        // attention" would tell an engineer nothing about which site they
        // are about to lose a day's work on.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              preserved.isNotEmpty
                  ? 'Synced, but unsynced work remains on '
                      '${preserved.length == 1 ? preserved.first : '${preserved.length} sites'} '
                      'you no longer have access to.'
                  : 'Synced, but $blocked item${blocked == 1 ? '' : 's'} '
                      '${blocked == 1 ? 'needs' : 'need'} attention.',
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Details',
              onPressed: () =>
                  _showSyncNeedsAttentionDialog(blocked, preserved),
            ),
          ),
        );
      case SyncStatus.failure:
        // Keep the headline in plain language; raw error text (if any) only
        // shows up if the user taps through to the details view.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Couldn't finish syncing. Some changes are still only on "
                  'this device.',
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _showSyncFailureDetails(
                    skipped: outcome.skipped,
                    pushFailures: outcome.pushFailures,
                    wholeRunMessage: outcome.push.message,
                    corePullFailed: outcome.corePullFailed,
                    corePullMessage: outcome.corePull.message,
                    blocked: outcome.blocked,
                  ),
                  child: const Text(
                    'View details',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            // No fixed duration — a failure stays up until the user acts
            // (Retry, the close icon, or a swipe) rather than quietly timing
            // out and being missed. The close icon only calls
            // ScaffoldMessenger.hideCurrentSnackBar internally — it never
            // touches SyncController.status, so the AppBar indicator
            // (_syncStatusButton) keeps reporting failure, and the next
            // failed run shows a brand-new SnackBar regardless of whether
            // this one was dismissed.
            duration: const Duration(days: 1),
            showCloseIcon: true,
            action: SnackBarAction(label: 'Retry', onPressed: _syncNow),
          ),
        );
      case SyncStatus.idle:
      case SyncStatus.syncing:
        // Never returned as a finished run's outcome — a completed sync is
        // always one of the three terminal states above.
        break;
    }
  }

  /// Explains a [_SyncStatus.partial] result — a standing set of rows this
  /// account can never push, distinct from a retryable failure (see
  /// [_syncNow]'s partial branch).
  Future<void> _showSyncNeedsAttentionDialog(
    int blocked, [
    List<String> preservedSites = const [],
  ]) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Needs attention'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Named sites first and in full: this is unpushed field work on a
            // site that has been reassigned away, and the engineer is the
            // only person who knows what is in it. The data is kept on the
            // device deliberately rather than deleted, but it can no longer
            // be pushed — RLS refuses it — so the only useful action is to
            // tell someone before the device is wiped or reassigned again.
            if (preservedSites.isNotEmpty) ...[
              Text(
                preservedSites.length == 1
                    ? 'Unsynced work exists for "${preservedSites.first}", '
                        'which is no longer assigned to you.'
                    : 'Unsynced work exists for these sites, which are no '
                        'longer assigned to you:',
              ),
              if (preservedSites.length > 1) ...[
                const SizedBox(height: 8),
                for (final name in preservedSites) Text('  •  $name'),
              ],
              const SizedBox(height: 8),
              const Text(
                'It has been kept on this device so nothing is lost, but it '
                'can no longer be uploaded. Contact your manager before '
                'clearing the app or handing the device over.',
              ),
              if (blocked > 0) const SizedBox(height: 12),
            ],
            if (blocked > 0)
              Text(
                '$blocked item${blocked == 1 ? '' : 's'} on this device '
                "can't sync with your account's permissions — usually because "
                'they belong to a site or record you no longer have access to. '
                "Ask your admin to check if this doesn't look right.",
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Full explanation for a [_SyncStatus.failure] result, reached via "View
  /// details" on the failure SnackBar (see [_syncNow]). Plain-language lines
  /// first; raw diagnostic text (if any) sits behind a collapsed "Technical
  /// details" section so a casual user never has to read it, but it's still
  /// there for anyone reporting a bug.
  Future<void> _showSyncFailureDetails({
    required int skipped,
    required List<String> pushFailures,
    String? wholeRunMessage,
    required bool corePullFailed,
    String? corePullMessage,
    required int blocked,
  }) async {
    final technical = <String>[
      if (pushFailures.isNotEmpty) pushFailures.join('\n'),
      ?wholeRunMessage,
      if (corePullFailed) ?corePullMessage,
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (skipped > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '$skipped item${skipped == 1 ? '' : 's'} '
                    "couldn't be sent to the server yet. They'll be "
                    'retried automatically the next time you sync.',
                  ),
                ),
              if (corePullFailed)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Couldn't download the latest updates from other "
                    'devices. Check your connection and try again.',
                  ),
                ),
              if (blocked > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    "$blocked item${blocked == 1 ? '' : 's'} can't sync "
                    "with your account's permissions and need attention "
                    'from your admin.',
                  ),
                ),
              if (skipped == 0 && !corePullFailed && blocked == 0)
                const Text("Couldn't sync. Check your connection and try again."),
              if (technical.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('Technical details'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(technical.join('\n\n')),
                    ),
                  ],
                ),
            ],
          ),
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

  /// Whole-minute relative time since [at] — no new package, simple
  /// Duration math is enough at this granularity.
  String _lastSyncedLabel(DateTime? at) {
    if (at == null) return 'Synced';
    final minutes = DateTime.now().difference(at).inMinutes;
    return minutes < 1 ? 'Synced just now' : 'Synced ${minutes}m ago';
  }

  /// AppBar sync control — a single tappable status widget (replacing a
  /// plain "Sync now" icon button) that reflects [SyncController.status] and
  /// retriggers [_syncNow] on tap in every state.
  ///
  /// Wrapped in a [ListenableBuilder] scoped to just this button: the status
  /// used to live in this screen's own State, so every change rebuilt the
  /// whole screen (site list included). Only this button actually depends on
  /// it.
  Widget _syncStatusButton() {
    final controller = SyncScope.read(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        switch (controller.status) {
          case SyncStatus.idle:
            return TextButton.icon(
              onPressed: _syncNow,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Sync'),
            );
          case SyncStatus.syncing:
            return TextButton.icon(
              onPressed: null,
              icon: const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              label: const Text('Syncing…'),
            );
          case SyncStatus.success:
            return TextButton.icon(
              onPressed: _syncNow,
              icon: Icon(Icons.cloud_done, color: AppStatusColors.complete),
              label: Text(
                _lastSyncedLabel(controller.lastSyncedAt),
                style: const TextStyle(color: AppStatusColors.complete),
              ),
            );
          case SyncStatus.partial:
            // Same base "cloud done" icon as success (the data DID fully
            // sync) but amber, not green — signals "look closer" without
            // implying the run failed. Tapping still retries; retrying can't
            // fix the blocked rows themselves, but re-running is harmless and
            // may pick up anything new since.
            // Blocked rows and preserved sites both land in this tier, and a
            // run can carry either or both. Counting only blocked rows would
            // render "0 need attention" for a run whose sole issue is a site
            // kept back with unsynced work.
            final blocked = controller.blockedCount;
            final needsAttention = blocked + controller.preservedSites.length;
            return TextButton.icon(
              onPressed: _syncNow,
              icon: Icon(Icons.cloud_done, color: AppStatusColors.partial),
              label: Text(
                '${_lastSyncedLabel(controller.lastSyncedAt)} — $needsAttention '
                '${needsAttention == 1 ? 'needs' : 'need'} attention',
                style: const TextStyle(color: AppStatusColors.partial),
              ),
            );
          case SyncStatus.failure:
            return TextButton.icon(
              onPressed: _syncNow,
              icon: Icon(Icons.sync_problem, color: scheme.error),
              label: Text(
                'Sync failed — tap to retry',
                style: TextStyle(color: scheme.error),
              ),
            );
        }
      },
    );
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

  /// Approver's home, split into "Pending" and "All".
  ///
  /// Pending is `submitted` only — the single status that means "waiting for
  /// approval" (see [SurveyStatus.order]), and the same status the row tap
  /// requires before it will open the review screen. Defaults to Pending
  /// (tab 0) so an Approver lands on their actual queue rather than on 30
  /// sites they have no action for.
  ///
  /// Deliberately tabs rather than a default-on filter toggle: hiding most
  /// of the list behind an easily-missed switch is what made an approved
  /// site look deleted to Sales, and "All" sitting visibly alongside means
  /// nothing ever appears to have vanished. Approver keeps full visibility —
  /// this is display grouping only, no change to what RLS permits.
  Widget _buildApproverGroupedList(List<Site> sites) {
    final pending = sites
        .where((s) => s.status == SurveyStatus.submitted)
        .toList(growable: false);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              _tabLabelWithBadge(context, 'Pending', pending.length),
              _tabLabelWithBadge(context, 'All', sites.length),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _genericSiteList(
                  pending,
                  emptyMessage: 'Nothing waiting for approval.\n'
                      'Surveys appear here once an engineer submits them.',
                ),
                _genericSiteList(sites),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The plain (ungrouped) site list — Approver's two tabs and Admin's whole
  /// screen both render through this, so a row looks and behaves identically
  /// wherever it appears.
  ///
  /// [emptyMessage] is what a legitimately-empty *subset* says. Without it an
  /// empty Pending tab would be a blank screen indistinguishable from a
  /// failed load.
  Widget _genericSiteList(List<Site> sites, {String? emptyMessage}) {
    if (sites.isEmpty && emptyMessage != null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: sites.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final site = sites[i];
          final hasInputs = site.clientInputs != null;
          final role = widget.session.currentRole;
          final isSales = role == UserRole.sales;
          final isEngineer = role == UserRole.engineer;
          final isApprover = role == UserRole.approver;
          final isReadyForSales =
              site.status == SurveyStatus.approved ||
              site.status == SurveyStatus.released;
          // Human label ("In progress"), not the raw stored value
          // ("in_progress") — this is the line an Approver scans to tell
          // states apart without opening each site.
          final statusLabel = SurveyStatus.label(site.status);
          return ListTile(
            leading: const Icon(Icons.location_city_outlined),
            title: Text(site.name),
            subtitle: Text(
              isSales
                  ? (isReadyForSales
                        ? 'Approved · ready  ·  Assigned to: '
                              '${site.assignedTo ?? 'Unassigned'}'
                        : 'Assigned to: ${site.assignedTo ?? 'Unassigned'} '
                              '· Status: $statusLabel')
                  : isEngineer
                  ? 'Status: $statusLabel'
                  : isApprover
                  ? 'Assigned to: ${site.assignedTo ?? 'Unassigned'} '
                        '· Status: $statusLabel'
                  : '${site.blocks.length} block(s)  ·  Status: $statusLabel  ·  '
                        '${hasInputs ? 'Client inputs saved' : 'No client inputs yet'}',
            ),
            trailing: isSales && isReadyForSales
                ? const Icon(Icons.check_circle, color: AppStatusColors.complete)
                : const Icon(Icons.chevron_right),
            // Approver only gets the read-only review screen once a survey
            // is actually submitted; for any earlier status (e.g. one they
            // just created and assigned) they open the Site Hub, same as
            // Sales, which is where reassignment lives. Site Hub now offers
            // its own Approve path for a submitted site, so landing there
            // is no longer a dead end either.
            onTap: () => (isApprover && site.status == SurveyStatus.submitted)
                ? _openReview(site)
                : _openSite(site),
            onLongPress: _canManageSites ? () => _showSiteActions(site) : null,
          );
        },
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
      subtitle: Text('Status: ${SurveyStatus.label(site.status)}'),
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
                  '· Status: ${SurveyStatus.label(site.status)}',
      ),
      trailing: isReadyForSales
          ? const Icon(Icons.check_circle, color: AppStatusColors.complete)
          : const Icon(Icons.chevron_right),
      onTap: () => _openSite(site),
      onLongPress: _canManageSites ? () => _showSiteActions(site) : null,
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
        bottom: RefreshBar(active: _refreshing),
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
                _syncStatusButton(),
                PopupMenuButton<_HomeMoreMenuAction>(
                  tooltip: 'More',
                  onSelected: (action) {
                    switch (action) {
                      case _HomeMoreMenuAction.materialMaster:
                        _openMaterialMaster();
                      case _HomeMoreMenuAction.testConnection:
                        _testSupabase();
                      case _HomeMoreMenuAction.logout:
                        _logout();
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.session.currentRole == UserRole.admin)
                      const PopupMenuItem(
                        value: _HomeMoreMenuAction.materialMaster,
                        child: Text('Material Master'),
                      ),
                    // Developer diagnostic — compiled out of release builds
                    // entirely. This is a build-type concern (dev vs field),
                    // not a role/permission one, so kDebugMode is the right
                    // gate, not an admin-role check.
                    if (kDebugMode)
                      const PopupMenuItem(
                        value: _HomeMoreMenuAction.testConnection,
                        child: Text('Test Supabase connection'),
                      ),
                    if (widget.session.currentRole == UserRole.admin ||
                        kDebugMode)
                      const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _HomeMoreMenuAction.logout,
                      child: Text('Log out'),
                    ),
                  ],
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
          _RoleBanner(
            userName: widget.session.currentUserName,
            role: widget.session.currentRole,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? LoadErrorView(onRetry: _load, details: _loadError)
                : _sites.isEmpty
                ? _EmptyState(role: widget.session.currentRole)
                : _filteredSites.isEmpty
                ? const Center(child: Text('No sites found.'))
                : widget.session.currentRole == UserRole.engineer
                ? _buildEngineerGroupedList(_filteredSites)
                : widget.session.currentRole == UserRole.sales
                ? _buildSalesGroupedList(_filteredSites)
                : widget.session.currentRole == UserRole.approver
                ? _buildApproverGroupedList(_filteredSites)
                : _genericSiteList(_filteredSites),
          ),
        ],
      ),
    );
  }
}

/// A slim header showing who's signed in. Leads with the account's real
/// name (profiles.full_name) — the role is shown alongside in parentheses
/// for context, not as the headline identity, since a name alone doesn't
/// tell a reader what this person can do here. Role-gating logic elsewhere
/// keeps reading [SessionController.currentRole] directly; this is display
/// only.
class _RoleBanner extends StatelessWidget {
  const _RoleBanner({required this.userName, required this.role});

  final String? userName;
  final UserRole? role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roleLabel = role?.label ?? 'Unknown role';
    final name = userName?.trim();
    final identity = (name == null || name.isEmpty)
        ? 'Signed in as $roleLabel'
        : '$name ($roleLabel)';
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              identity,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
              ),
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
