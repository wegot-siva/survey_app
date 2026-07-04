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

  /// Engineer sees only their own assigned surveys (Slice C); Approver sees
  /// only those submitted and awaiting review (Slice D); Sales and Admin see
  /// everything, unchanged from before (Admin has no survey-list filtering —
  /// only the Material Master entry point is role-gated to them).
  List<Site> _visibleSites(List<Site> sites) {
    switch (widget.session.currentRole) {
      case UserRole.engineer:
        final engineer = widget.session.currentEngineerName;
        if (engineer == null) return const [];
        return sites
            .where((s) => s.assignedTo == engineer)
            .toList(growable: false);
      case UserRole.approver:
        return sites
            .where((s) => s.status == SurveyStatus.submitted)
            .toList(growable: false);
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
    if (confirmed == true) widget.session.logout();
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
              ? Text(
                  'Pushed to Supabase:\n\n'
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
                  '${result.bomSnapshots == 1 ? '' : 's'}',
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
      floatingActionButton: widget.session.currentRole == UserRole.sales
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
                          onTap: () =>
                              isApprover ? _openReview(site) : _openSite(site),
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
