import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/bom_line.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import 'duct_loras_list_screen.dart';

/// Group B (DCU) — Duct LoRa count is auto-computed (derived formula) and
/// shown read-only here, same as group A: no add/edit for those lines under
/// any circumstance.
///
/// Cable length is hand-entered, but only ever as a field on a Duct LoRa
/// unit (there's no separate "add cable" mechanism anywhere in the app) —
/// so "Add material" opens the existing Duct LoRa list/add/edit/delete
/// flow unchanged, rather than a new one. That flow also covers "view/edit/
/// delete existing entries" for this section.
///
/// Hides zero-qty lines by default, same "Show all" toggle as group A.
class BomGroupBSectionScreen extends StatefulWidget {
  const BomGroupBSectionScreen({
    super.key,
    required this.repository,
    required this.site,
    required this.lines,
    this.readOnly = false,
    this.isAdmin = false,
  });

  final SurveyRepository repository;
  final Site site;
  final List<BomLine> lines;

  /// When true, hides "Add material" and opens the Duct LoRa list read-only
  /// — mirrors [BomPreviewScreen.readOnly].
  final bool readOnly;

  /// Threaded through to [DuctLorasListScreen] — see its doc for what this
  /// shows.
  final bool isAdmin;

  @override
  State<BomGroupBSectionScreen> createState() => _BomGroupBSectionScreenState();
}

class _BomGroupBSectionScreenState extends State<BomGroupBSectionScreen> {
  bool _showAll = false;

  static String _formatQuantity(double q) {
    return q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
  }

  Future<void> _openDuctLoras() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DuctLorasListScreen(
          repository: widget.repository,
          site: widget.site,
          readOnly: widget.readOnly,
          isAdmin: widget.isAdmin,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hiddenCount = widget.lines.where((l) => l.quantity <= 0).length;
    final visible = _showAll
        ? widget.lines
        : widget.lines.where((l) => l.quantity > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${MaterialGroup.b.code} — ${MaterialGroup.b.label}'),
        actions: [
          if (hiddenCount > 0)
            TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(
                _showAll ? 'Hide zero-qty' : 'Show all ($hiddenCount)',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
        ],
      ),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: _openDuctLoras,
              icon: const Icon(Icons.add),
              label: const Text('Add material'),
            ),
      body: visible.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No Duct LoRa or cable lines yet.\n\n'
                  'Duct LoRa count is computed from wired sensors; cable '
                  "length comes from each Duct LoRa unit's own cable-length "
                  'field.${widget.readOnly ? '' : ' Tap "Add material" to manage Duct LoRa units.'}',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final line = visible[i];
                return ListTile(
                  title: Text(line.materialName),
                  subtitle: Text(line.variantLabel),
                  trailing: Text(
                    '${_formatQuantity(line.quantity)} ${line.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
    );
  }
}
