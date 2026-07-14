import 'package:flutter/material.dart';

import '../models/bom_line.dart';
import '../models/material_master_item.dart';

/// Group A (WEGOTAqua sensors) — fully auto-computed from survey data by
/// BomEngine. Read-only: no add/edit action exists here under any
/// circumstance, since sensor lines are never hand-entered.
///
/// Hides zero-qty lines by default (BomEngine emits every Material Master
/// row regardless of computed quantity, so most rows are zero) — same
/// "Show all" toggle the old flat BoM view offered per group.
class BomGroupASectionScreen extends StatefulWidget {
  const BomGroupASectionScreen({super.key, required this.lines});

  final List<BomLine> lines;

  @override
  State<BomGroupASectionScreen> createState() => _BomGroupASectionScreenState();
}

class _BomGroupASectionScreenState extends State<BomGroupASectionScreen> {
  bool _showAll = false;

  static String _formatQuantity(double q) {
    return q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final hiddenCount = widget.lines.where((l) => l.quantity <= 0).length;
    final visible = _showAll
        ? widget.lines
        : widget.lines.where((l) => l.quantity > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${MaterialGroup.a.code} — ${MaterialGroup.a.label}'),
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
      body: visible.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No sensor lines yet.\n\n'
                  'This section is fully computed from survey data — add '
                  'source/inlet points to generate sensor quantities here.',
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
