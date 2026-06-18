import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import 'create_site_screen.dart';
import 'site_detail_screen.dart';

/// Lists all sites and offers a button to create a new one.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final SurveyRepository repository;

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
            SiteDetailScreen(repository: widget.repository, siteId: site.id),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sites')),
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
