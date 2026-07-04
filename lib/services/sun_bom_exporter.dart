import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bom_revision_engine.dart';

/// Writes a survey's running-total BoM to the Sun_BOM .xlsx format: one flat
/// sheet, columns [SKU, Item, Qty, Comments, SO item, Milestone, Phase,
/// Project code, SO number]. The app only ever fills SKU/Item/Qty — the
/// other six columns are emitted empty for the office/ERP side to fill in.
///
/// Pure formatting — it never computes quantities; the running total (from
/// [BomRevisionEngine]) is passed in unchanged. This slice exports the
/// latest running total only; exporting an older version is a later slice.
class SunBomExporter {
  const SunBomExporter();

  static const _headers = [
    'SKU',
    'Item',
    'Qty',
    'Comments',
    'SO item',
    'Milestone',
    'Phase',
    'Project code',
    'SO number',
  ];

  /// Builds the workbook from [lines] and writes it to a temp file (suitable
  /// for the share sheet). Returns the file path. [siteName] names the file.
  Future<String> export({
    required String siteName,
    required List<BomRunningTotalLine> lines,
  }) async {
    final bytes = buildXlsxBytes(lines);
    final dir = await getTemporaryDirectory();
    final filePath = p.join(
      dir.path,
      'Sun_BOM_${_safeFileName(siteName)}_'
      '${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  /// Pure workbook construction (no I/O) — exposed so the formatting can be
  /// unit-tested without platform plugins. Excludes any line whose running
  /// total is 0 or below, then sorts the remainder by SKU.
  List<int> buildXlsxBytes(List<BomRunningTotalLine> lines) {
    final rows = lines.where((l) => l.rawQty > 0).toList()
      ..sort((a, b) => a.sku.compareTo(b.sku));

    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet()!;
    final sheet = excel[sheetName];

    sheet.appendRow([for (final h in _headers) TextCellValue(h)]);
    for (var c = 0; c < _headers.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .cellStyle = CellStyle(bold: true);
    }

    for (final line in rows) {
      sheet.appendRow([
        TextCellValue(line.sku),
        TextCellValue(line.item),
        _qtyCell(line.displayQty),
        // Comments, SO item, Milestone, Phase, Project code, SO number —
        // filled in later by the office/ERP side, never by the app.
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
      ]);
    }

    return excel.encode()!;
  }

  CellValue _qtyCell(double q) =>
      q == q.roundToDouble() ? IntCellValue(q.toInt()) : DoubleCellValue(q);

  String _safeFileName(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'site' : cleaned;
  }
}
