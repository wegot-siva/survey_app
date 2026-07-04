// Tests the Sun_BOM export formatting: one flat sheet, columns [SKU, Item,
// Qty, Comments, SO item, Milestone, Phase, Project code, SO number],
// SKU/Item/Qty filled and the other six left empty, sorted by SKU, with
// zero/negative running-total lines excluded. Round-trips through the
// `excel` package (build bytes -> decode) so no platform plugins are needed.

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/services/bom_revision_engine.dart';
import 'package:survey_app/services/sun_bom_exporter.dart';

void main() {
  const exporter = SunBomExporter();

  BomRunningTotalLine line(
    String sku,
    String item,
    double rawQty, {
    String unit = 'pcs',
    MaterialGroup group = MaterialGroup.a,
  }) => BomRunningTotalLine(
    sku: sku,
    item: item,
    unit: unit,
    group: group,
    rawQty: rawQty,
  );

  List<List<String?>> decodeRows(List<int> bytes) {
    final sheet = Excel.decodeBytes(bytes).sheets.values.first;
    return sheet.rows
        .map((r) => r.map((c) => c?.value?.toString()).toList())
        .toList();
  }

  test('header row matches the exact Sun_BOM column order', () {
    final rows = decodeRows(exporter.buildXlsxBytes([line('SKU-1', 'Sensor', 5)]));
    expect(rows[0], [
      'SKU',
      'Item',
      'Qty',
      'Comments',
      'SO item',
      'Milestone',
      'Phase',
      'Project code',
      'SO number',
    ]);
  });

  test('SKU/Item/Qty are filled; the other six columns are present but empty', () {
    final rows = decodeRows(
      exporter.buildXlsxBytes([line('SKU-1', 'WEGOTAqua Sensor', 7, unit: 'pcs')]),
    );
    expect(rows[1][0], 'SKU-1');
    expect(rows[1][1], 'WEGOTAqua Sensor');
    expect(rows[1][2], '7');
    for (final col in rows[1].skip(3)) {
      expect(col, anyOf(isNull, isEmpty));
    }
    expect(rows[1].length, 9);
  });

  test('rows are sorted by SKU', () {
    final rows = decodeRows(
      exporter.buildXlsxBytes([
        line('SKU-3', 'Third', 1),
        line('SKU-1', 'First', 1),
        line('SKU-2', 'Second', 1),
      ]),
    );
    expect(rows.skip(1).map((r) => r[0]).toList(), ['SKU-1', 'SKU-2', 'SKU-3']);
  });

  test('lines with a running total of exactly 0 are excluded', () {
    final rows = decodeRows(
      exporter.buildXlsxBytes([
        line('SKU-1', 'Kept', 5),
        line('SKU-2', 'Zeroed out', 0),
      ]),
    );
    expect(rows.length, 2); // header + one kept row
    expect(rows[1][0], 'SKU-1');
  });

  test('lines with a negative running total are excluded', () {
    final rows = decodeRows(
      exporter.buildXlsxBytes([
        line('SKU-1', 'Kept', 5),
        line('SKU-2', 'Over-subtracted', -3),
      ]),
    );
    expect(rows.length, 2);
    expect(rows[1][0], 'SKU-1');
  });

  test('one flat sheet only — no per-group or per-DN-size splitting', () {
    final bytes = exporter.buildXlsxBytes([
      line('SKU-1', 'A group item', 1, group: MaterialGroup.a),
      line('SKU-2', 'D group item', 1, group: MaterialGroup.d),
    ]);
    expect(Excel.decodeBytes(bytes).sheets.length, 1);
  });

  test('integer quantities render without a decimal point', () {
    final rows = decodeRows(exporter.buildXlsxBytes([line('SKU-1', 'X', 4)]));
    expect(rows[1][2], '4');
  });
}
