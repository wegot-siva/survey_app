import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/gateway.dart';
import '../models/site.dart';
import 'gateway_form_screen.dart';

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final gateways = await widget.repository.getGateways(widget.site.id);
    if (!mounted) return;
    setState(() {
      _gateways = gateways;
      _loading = false;
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
      appBar: AppBar(title: const Text('Gateways')),
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
