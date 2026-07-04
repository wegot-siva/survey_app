import 'package:flutter/material.dart';

import '../models/material_master_item.dart';

/// One line as shown by [BomVersionDetailScreen] — a display-only shape
/// covering both a frozen v1 [BomSnapshotLine] (qty, unsigned) and a v2+
/// [BomRevisionLine] (qtyDelta, shown with an explicit +/- sign).
typedef BomVersionLineView = ({
  String item,
  String sku,
  String unit,
  double qty,
  MaterialGroup group,
  bool isDelta,
});

/// Read-only viewer for one version of a locked survey's BoM — either the
/// frozen v1 snapshot or a single v2+ revision's delta lines. Reached from
/// [BomRevisionsScreen]'s version history list.
class BomVersionDetailScreen extends StatelessWidget {
  const BomVersionDetailScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.lines,
  });

  final String title;
  final String subtitle;
  final List<BomVersionLineView> lines;

  static String _formatQty(double q, bool signed) {
    final rounded = q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);
    return signed && q > 0 ? '+$rounded' : rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          Expanded(
            child: lines.isEmpty
                ? const Center(child: Text('No lines.'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final group in MaterialGroup.values)
                        if (lines.any((l) => l.group == group))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondaryContainer,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    child: Text(
                                      '${group.code} — ${group.label}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                  for (final line in lines.where(
                                    (l) => l.group == group,
                                  ))
                                    ListTile(
                                      dense: true,
                                      title: Text(
                                        line.sku.isEmpty
                                            ? line.item
                                            : '${line.item} (${line.sku})',
                                      ),
                                      trailing: Text(
                                        '${_formatQty(line.qty, line.isDelta)} ${line.unit}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
