import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import 'create_site_screen.dart';
import 'site_hub_screen.dart';

/// Lists all sites and offers a button to create a new one.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.supabaseService,
    required this.syncService,
  });

  final SurveyRepository repository;
  final SupabaseService supabaseService;
  final SyncService syncService;

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
      _sites = sites;
      _loading = false;
    });
  }

  Future<void> _openCreateSite() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateSiteScreen(repository: widget.repository),
      ),
    );
    await _load();
  }

  Future<void> _openSite(Site site) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SiteHubScreen(repository: widget.repository, siteId: site.id),
      ),
    );
    await _load();
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
                  '• ${result.footers} footer form(s)',
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateSite,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('New site'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sites.isEmpty
          ? const _EmptyState()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _sites.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final site = _sites[i];
                  final hasInputs = site.clientInputs != null;
                  return ListTile(
                    leading: const Icon(Icons.location_city_outlined),
                    title: Text(site.name),
                    subtitle: Text(
                      '${site.blocks.length} block(s)  •  '
                      '${hasInputs ? 'Client inputs saved' : 'No client inputs yet'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openSite(site),
                  );
                },
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'No sites yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap "New site" to add your first one.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
