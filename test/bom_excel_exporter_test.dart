// Tests the BoM Excel formatting: one sheet per block, grouped A–G, columns
// Item/Materials/Size/Qty/Unit, items only. Round-trips through the `excel`
// package (build bytes -> decode) so no platform plugins are needed.

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/models/bom_line.dart';
import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/services/bom_excel_exporter.dart';

void main() {
  const exporter = BomExcelExporter();

  BlockBom block(String label, Map<MaterialGroup, List<BomLine>> bom) =>
      (label: label, bom: bom);

  BomLine line(
    MaterialGroup g,
    String name,
    String variant,
    double qty,
    String unit,
  ) => BomLine(
    group: g,
    materialName: name,
    variantLabel: variant,
    quantity: qty,
    unit: unit,
  );

  test('writes one sheet per block', () {
    final bytes = exporter.buildXlsxBytes([
      block('Block A', {
        MaterialGroup.a: [line(MaterialGroup.a, 'Sensor', 'DN25 · Wired', 5, 'pcs')],
      }),
      block('Block B', {
        MaterialGroup.a: [line(MaterialGroup.a, 'Sensor', 'DN50 · Wired', 2, 'pcs')],
      }),
    ]);

    final decoded = Excel.decodeBytes(bytes);
    expect(decoded.sheets.keys, containsAll(['Block A', 'Block B']));
    // The stray default 'Sheet1' must be gone.
    expect(decoded.sheets.keys, isNot(contains('Sheet1')));
  });

  test('lays out group header + column headers + numbered item rows', () {
    final bytes = exporter.buildXlsxBytes([
      block('Block A', {
        MaterialGroup.a: [
          line(MaterialGroup.a, 'WEGOTAqua sensor', 'DN25 · Wired', 5, 'pcs'),
          line(MaterialGroup.a, 'WEGOTAqua sensor', 'DN50 · Wired', 3, 'pcs'),
        ],
      }),
    ]);

    final sheet = Excel.decodeBytes(bytes).sheets['Block A']!;
    final rows = sheet.rows
        .map((r) => r.map((c) => c?.value?.toString()).toList())
        .toList();

    // Block title, blank, group header, column header, two items, spacer.
    expect(rows[0][0], 'Block: Block A');
    expect(rows[2][0], startsWith('A — '));
    expect(rows[3].take(5).toList(), ['Item', 'Materials', 'Size', 'Qty', 'Unit']);
    expect(rows[4].take(5).toList(), [
      '1',
      'WEGOTAqua sensor',
      'DN25 · Wired',
      '5',
      'pcs',
    ]);
    expect(rows[5][0], '2'); // item numbering continues within the group
  });

  test('item numbering restarts per group', () {
    final bytes = exporter.buildXlsxBytes([
      block('Block A', {
        MaterialGroup.a: [line(MaterialGroup.a, 'Sensor', 'DN25', 1, 'pcs')],
        MaterialGroup.c: [
          line(MaterialGroup.c, 'Pipe', '25mm', 4, 'm'),
          line(MaterialGroup.c, 'Elbow', '25mm', 8, 'pcs'),
        ],
      }),
    ]);

    final sheet = Excel.decodeBytes(bytes).sheets['Block A']!;
    final rows = sheet.rows
        .map((r) => r.map((c) => c?.value?.toString()).toList())
        .toList();

    // Find the C group's first item row and confirm it restarts at 1.
    final cHeaderIdx = rows.indexWhere((r) => (r[0] ?? '').startsWith('C — '));
    expect(cHeaderIdx, greaterThan(0));
    // group header, then column header, then first item.
    expect(rows[cHeaderIdx + 2][0], '1');
    expect(rows[cHeaderIdx + 3][0], '2');
  });

  test('omits groups with no lines', () {
    final bytes = exporter.buildXlsxBytes([
      block('Block A', {
        MaterialGroup.a: [line(MaterialGroup.a, 'Sensor', 'DN25', 1, 'pcs')],
        MaterialGroup.b: const [],
      }),
    ]);

    final sheet = Excel.decodeBytes(bytes).sheets['Block A']!;
    final hasGroupB = sheet.rows.any(
      (r) => (r.isNotEmpty ? r[0]?.value?.toString() ?? '' : '').startsWith('B — '),
    );
    expect(hasGroupB, isFalse);
  });

  test('sanitizes invalid sheet-name characters and dedupes', () {
    final bytes = exporter.buildXlsxBytes([
      block('A/B:C', {
        MaterialGroup.a: [line(MaterialGroup.a, 'X', '-', 1, 'pcs')],
      }),
      block('A/B:C', {
        MaterialGroup.a: [line(MaterialGroup.a, 'Y', '-', 1, 'pcs')],
      }),
    ]);

    final names = Excel.decodeBytes(bytes).sheets.keys.toList();
    // No invalid chars survive, and the duplicate is disambiguated.
    expect(names.any((n) => n.contains('/') || n.contains(':')), isFalse);
    expect(names.length, 2);
    expect(names.toSet().length, 2);
  });
}
