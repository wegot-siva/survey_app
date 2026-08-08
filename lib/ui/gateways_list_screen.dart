import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/gateway.dart';
import '../models/site.dart';
import 'gateway_form_screen.dart';
import 'widgets/refresh_bar.dart';

/// Lists a site's gateways with add / edit / delete.
class GatewaysListScreen extends StatefulWidget {
  const GatewaysListScreen({
    super.key,
    required this.repository,
    required this.site,
    this.readOnly = false,
    this.isAdmin = false,
  });

  final SurveyRepository repository;
  final Site site;
  final bool readOnly;

  /// Threaded through to [GatewayFormScreen] — see its doc for what this
  /// shows.
  final bool isAdmin;

  @override
  State<GatewaysListScreen> createState() => _GatewaysListScreenState();
}

class _GatewaysListScreenState extends State<GatewaysListScreen> {
  List<Gateway> _gateways = const [];
  /// True only until the very first read completes — after that the
  /// screen already has content worth keeping on screen, and a reload
  /// shows [RefreshBar] instead of replacing it. See [_load].
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _refreshing = true);
    final gateways = await widget.repository.getGateways(widget.site.id);
    if (!mounted) return;
    setState(() {
      _gateways = gateways;
      _loading = false;
      _refreshing = false;
    });
  }

  Future<void> _addOrEdit([Gateway? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GatewayFormScreen(
          repository: widget.repository,
          site: widget.site,
          existing: existing,
          readOnly: widget.readOnly,
          isAdmin: widget.isAdmin,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete(Gateway g) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete gateway?'),
        content: Text('"${_titleFor(g)}" will be permanently removed.'),
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

    await widget.repository.deleteGateway(g.id);
    await _load();
  }

  static String _titleFor(Gateway g) {
    if (g.locationDescription.trim().isNotEmpty) {
      return g.locationDescription.trim();
    }
    if (g.placement != null) return g.placement!.label;
    return 'Untitled gateway';
  }

  static String _subtitleFor(Gateway g) {
    final parts = <String>[
      if (g.placement != null) g.placement!.label,
      if (g.uplinkType != null) g.uplinkType!.label,
      if (g.blocksCovered.isNotEmpty) 'Blocks ${g.blocksCovered.join(", ")}',
    ];
    return parts.isEmpty ? 'No details yet' : parts.join('  •  ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gateways'),
        bottom: RefreshBar(active: _refreshing),
      ),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Add gateway'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _gateways.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No gateways yet.\nTap "Add gateway" to create one.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              // Clears the extended FAB, which would otherwise sit on top of
              // the last row and block its overflow menu.
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: _gateways.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final g = _gateways[i];
                return ListTile(
                  leading: const Icon(Icons.cell_tower_outlined),
                  title: Text(_titleFor(g)),
                  subtitle: Text(_subtitleFor(g)),
                  onTap: () => _addOrEdit(g),
                  trailing: widget.readOnly
                      ? null
                      : IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(g),
                        ),
                );
              },
            ),
    );
  }
}
