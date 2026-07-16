// Tests the Lumax export formatting: one sheet per sensor variant, each with
// a site-name row, header row [No., Item, Materials, Size, Qty, Unit, Unit
// price, Total], group header rows (A-G) with materials nested (numbering
// restarts per group), and the same zero-qty/empty-group exclusion as
// Sun_BOM. Round-trips through the `excel` package so no platform plugins
// are needed.

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/models/survey_options.dart';
import 'package:survey_app/services/bom_revision_engine.dart';
import 'package:survey_app/services/lumax_exporter.dart';

void main() {
  const exporter = LumaxExporter();

  BomRunningTotalLine line(
    String item,
    double rawQty, {
    String sku = '',
    String itemLabel = '',
    String materialName = '',
    MaterialGroup group = MaterialGroup.a,
    SensorSize? sensorSize,
    SensorType? sensorType,
    String unit = 'pcs',
  }) => BomRunningTotalLine(
    sku: sku,
    item: item,
    materialName: materialName.isEmpty ? item : materialName,
    itemLabel: itemLabel,
    sensorSize: sensorSize,
    sensorType: sensorType,
    unit: unit,
    group: group,
    rawQty: rawQty,
  );

  List<List<String?>> rowsOf(Excel decoded, String sheetName) {
    return decoded.sheets[sheetName]!.rows
        .map((r) => r.map((c) => c?.value?.toString()).toList())
        .toList();
  }

  test('one sheet per sensor variant present', () {
    final bytes = exporter.buildXlsxBytes(
      siteName: 'Test Site',
      lines: [
        line('Sensor A', 1, sensorSize: SensorSize.dn25, sensorType: SensorType.wired),
        line('Sensor B', 1, sensorSize: SensorSize.dn25, sensorType: SensorType.wireless),
      ],
    );
    final decoded = Excel.decodeBytes(bytes);
    expect(decoded.sheets.keys, containsAll(['DN25 Wired', 'DN25 Wireless']));
    expect(decoded.sheets.keys, isNot(contains('Sheet1')));
  });

  test('lines with no sensor variant land on a General sheet', () {
    final bytes = exporter.buildXlsxBytes(
      siteName: 'Test Site',
      lines: [line('Rework kit', 1, group: MaterialGroup.d)],
    );
    final decoded = Excel.decodeBytes(bytes);
    expect(decoded.sheets.keys, contains('General'));
  });

  test('sheet layout: site name row, header row, group header, item rows', () {
    final bytes = exporter.buildXlsxBytes(
      siteName: 'Acme Towers',
      lines: [
        line(
          'Sensor A',
          5,
          itemLabel: 'SEN-A',
          materialName: 'Sensor Alpha',
          unit: 'pcs',
          sensorSize: SensorSize.dn25,
          sensorType: SensorType.wired,
        ),
      ],
    );
    final rows = rowsOf(Excel.decodeBytes(bytes), 'DN25 Wired');

    expect(rows[0][0], 'Acme Towers');
    expect(rows[1], [
      'No.',
      'Item',
      'Materials',
      'Size',
      'Qty',
      'Unit',
      'Unit price',
      'Total',
    ]);
    expect(rows[2][0], startsWith('A — '));
    expect(rows[3].take(6), [
      '1',
      'SEN-A',
      'Sensor Alpha',
      'DN25 · Wired',
      '5',
      'pcs',
    ]);
    expect(rows[3][6], anyOf(isNull, isEmpty));
    expect(rows[3][7], anyOf(isNull, isEmpty));
  });

  test('Item column falls back to materialName when itemLabel is blank', () {
    final bytes = exporter.buildXlsxBytes(
      siteName: 'Site',
      lines: [
        line(
          'Sensor A',
          1,
          materialName: 'Sensor Alpha',
          sensorSize: SensorSize.dn25,
          sensorType: SensorType.wired,
        ),
      ],
    );
    final rows = rowsOf(Excel.decodeBytes(bytes), 'DN25 Wired');
    expect(rows[3][1], 'Sensor Alpha'); // "Item" column, not blank
  });

  test('numbering restarts per group within a sheet', () {
    final bytes = exporter.buildXlsxBytes(
      siteName: 'Site',
      lines: [
        line('A1', 1, group: MaterialGroup.a, sensorSize: SensorSize.dn25, sensorType: SensorType.wired),
        line('A2', 1, group: MaterialGroup.a, sensorSize: SensorSize.dn25, sensorType: SensorType.wired),
        line('C1', 1, group: MaterialGroup.c, sensorSize: SensorSize.dn25, sensorType: SensorType.wired),
      ],
    );
    final rows = rowsOf(Excel.decodeBytes(bytes), 'DN25 Wired');
    final cHeaderIdx = rows.indexWhere((r) => (r[0] ?? '').startsWith('C — '));
    expect(cHeaderIdx, greaterThan(0));
    expect(rows[cHeaderIdx + 1][0], '1'); // restarts, not continuing from A's "2"
  });

  test('Unit price and Total columns are always blank', () {
    final bytes = exporter.buildXlsxBytes(
      siteName: 'Site',
      lines: [line('X', 1, sensorSize: SensorSize.dn25, sensorType: SensorType.wired)],
    );
    final rows = rowsOf(Excel.decodeBytes(bytes), 'DN25 Wired');
    expect(rows[3][6], anyOf(isNull, isEmpty));
    expect(rows[3][7], anyOf(isNull, isEmpty));
  });

  test('lines with a running total of 0 or below are excluded', () {
    final bytes = exporter.buildXlsxBytes(
      siteName: 'Site',
      lines: [
        line('Kept', 5, sensorSize: SensorSize.dn25, sensorType: SensorType.wired),
        line('Zeroed', 0, sensorSize: SensorSize.dn25, sensorType: SensorType.wired),
        line('Negative', -3, sensorSize: SensorSize.dn25, sensorType: SensorType.wired),
      ],
    );
    final rows = rowsOf(Excel.decodeBytes(bytes), 'DN25 Wired');
    // header rows + group header + exactly one item row.
    expect(rows.length, 4);
    expect(rows[3][2], 'Kept'); // "Materials" column (materialName)
  });

  test('a group with no non-zero materials is fully omitted from the sheet', () {
    final bytes = exporter.buildXlsxBytes(
      siteName: 'Site',
      lines: [
        line('A item', 5, group: MaterialGroup.a, sensorSize: SensorSize.dn25, sensorType: SensorType.wired),
        line('C item', 0, group: MaterialGroup.c, sensorSize: SensorSize.dn25, sensorType: SensorType.wired),
      ],
    );
    final rows = rowsOf(Excel.decodeBytes(bytes), 'DN25 Wired');
    final hasGroupC = rows.any((r) => (r[0] ?? '').startsWith('C — '));
    expect(hasGroupC, isFalse);
  });

  test('a partial variant (size only, no type) gets its own sheet', () {
    final bytes = exporter.buildXlsxBytes(
      siteName: 'Site',
      lines: [line('X', 1, sensorSize: SensorSize.dn32)],
    );
    expect(Excel.decodeBytes(bytes).sheets.keys, contains('DN32'));
  });
}
