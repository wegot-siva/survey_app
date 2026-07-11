import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/duct_lora.dart';
import '../models/site.dart';
import 'duct_lora_form_screen.dart';

/// Lists a site's Duct LoRa units with add / edit / delete.
class DuctLorasListScreen extends StatefulWidget {
  const DuctLorasListScreen({
    super.key,
    required this.repository,
    required this.site,
    this.readOnly = false,
    this.isAdmin = false,
  });

  final SurveyRepository repository;
  final Site site;
  final bool readOnly;

  /// Threaded through to [DuctLoraFormScreen] — see its doc for what this
  /// shows.
  final bool isAdmin;

  @override
  State<DuctLorasListScreen> createState() => _DuctLorasListScreenState();
}

class _DuctLorasListScreenState extends State<DuctLorasListScreen> {
  List<DuctLora> _units = const [];
  List<String> _availableSeries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final units = await widget.repository.getDuctLoras(widget.site.id);
    // Series options come from the Series values used on the site's inlets.
    final inlets = await widget.repository.getInletPoints(widget.site.id);
    final series =
        inlets
            .map((i) => i.series.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (!mounted) return;
    setState(() {
      _units = units;
      _availableSeries = series;
      _loading = false;
    });
  }

  Future<void> _addOrEdit([DuctLora? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DuctLoraFormScreen(
          repository: widget.repository,
          site: widget.site,
          availableSeries: _availableSeries,
          existing: existing,
          readOnly: widget.readOnly,
          isAdmin: widget.isAdmin,
        ),
      ),
    );
    await _load();
  }

  Future<void> _delete(DuctLora d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Duct LoRa unit?'),
        content: Text('"${_titleFor(d)}" will be permanently removed.'),
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

    await widget.repository.deleteDuctLora(d.id);
    await _load();
  }

  static String _titleFor(DuctLora d) {
    if (d.block != null && d.block!.trim().isNotEmpty) {
      return 'Block ${d.block}';
    }
    return 'Untitled Duct LoRa unit';
  }

  static String _subtitleFor(DuctLora d) {
    final parts = <String>[
      if (d.seriesServed.isNotEmpty) 'Series ${d.seriesServed.join(", ")}',
      if (d.accessibleForService == true) 'Accessible',
    ];
    return parts.isEmpty ? 'No details yet' : parts.join('  •  ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duct LoRa')),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Add Duct LoRa'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _units.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No Duct LoRa units yet.\nTap "Add Duct LoRa" to create one.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _units.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final d = _units[i];
                return ListTile(
                  leading: const Icon(Icons.router_outlined),
                  title: Text(_titleFor(d)),
                  subtitle: Text(_subtitleFor(d)),
                  onTap: () => _addOrEdit(d),
                  trailing: widget.readOnly
                      ? null
                      : IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(d),
                        ),
                );
              },
            ),
    );
  }
}
