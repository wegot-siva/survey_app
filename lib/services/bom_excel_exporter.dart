import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/bom_line.dart';
import '../models/material_master_item.dart';

/// One block's computed BoM (the [BomEngine] output for that block's points),
/// ready to become a worksheet.
typedef BlockBom = ({String label, Map<MaterialGroup, List<BomLine>> bom});

/// Writes a BoM to an .xlsx file: one sheet per block, grouped A–G, items only
/// (Item, Materials, Size, Qty, Unit — no prices). Pure formatting — it never
/// computes quantities; the [BomEngine] output is passed in unchanged.
class BomExcelExporter {
  const BomExcelExporter();

  static const _headers = ['Item', 'Materials', 'Size', 'Qty', 'Unit'];

  /// Builds the workbook from [blocks] and writes it to a temp file (suitable
  /// for the share sheet). Returns the file path. [siteName] names the file.
  Future<String> export({
    required String siteName,
    required List<BlockBom> blocks,
  }) async {
    final bytes = buildXlsxBytes(blocks);
    final dir = await getTemporaryDirectory();
    final filePath = p.join(
      dir.path,
      'BoM_${_safeFileName(siteName)}_'
      '${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  /// Pure workbook construction (no I/O) — one sheet per block. Exposed so the
  /// formatting can be unit-tested without platform plugins.
  List<int> buildXlsxBytes(List<BlockBom> blocks) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    final usedNames = <String>{};

    for (final block in blocks) {
      final name = _uniqueSheetName(block.label, usedNames);
      _writeBlockSheet(excel[name], block);
    }

    // Remove the stray default sheet, unless a block happened to use that name.
    // Guard against deleting the only sheet (no blocks → nothing written).
    if (defaultSheet != null &&
        usedNames.isNotEmpty &&
        !usedNames.contains(defaultSheet.toLowerCase())) {
      excel.delete(defaultSheet);
    }

    return excel.encode()!;
  }

  void _writeBlockSheet(Sheet sheet, BlockBom block) {
    sheet.setColumnWidth(0, 8);
    sheet.setColumnWidth(1, 42);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 10);
    sheet.setColumnWidth(4, 10);

    _row(sheet, [TextCellValue('Block: ${block.label}')], bold: true);
    _row(sheet, [TextCellValue('')]);

    for (final group in MaterialGroup.values) {
      final lines = block.bom[group] ?? const [];
      if (lines.isEmpty) continue;

      _row(sheet, [TextCellValue('${group.code} — ${group.label}')], bold: true);
      _row(sheet, [for (final h in _headers) TextCellValue(h)], bold: true);

      var item = 1;
      for (final line in lines) {
        _row(sheet, [
          IntCellValue(item++),
          TextCellValue(line.materialName),
          TextCellValue(line.variantLabel),
          _qtyCell(line.quantity),
          TextCellValue(line.unit),
        ]);
      }
      _row(sheet, [TextCellValue('')]); // spacer between groups
    }
  }

  /// Appends a row, optionally bolding its cells.
  void _row(Sheet sheet, List<CellValue?> values, {bool bold = false}) {
    sheet.appendRow(values);
    if (!bold) return;
    final r = sheet.maxRows - 1;
    for (var c = 0; c < values.length; c++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .cellStyle = CellStyle(bold: true);
    }
  }

  CellValue _qtyCell(double q) =>
      q == q.roundToDouble() ? IntCellValue(q.toInt()) : DoubleCellValue(q);

  /// Excel sheet names: max 31 chars, none of []:*?/\, and unique
  /// (case-insensitive). Tracks taken names (lowercased) in [used].
  String _uniqueSheetName(String raw, Set<String> used) {
    var name = raw.trim().replaceAll(RegExp(r'[\[\]:*?/\\]'), '_');
    if (name.isEmpty) name = 'Sheet';
    if (name.length > 31) name = name.substring(0, 31);

    var candidate = name;
    var n = 2;
    while (used.contains(candidate.toLowerCase())) {
      final suffix = ' ($n)';
      final base = name.length + suffix.length > 31
          ? name.substring(0, 31 - suffix.length)
          : name;
      candidate = '$base$suffix';
      n++;
    }
    used.add(candidate.toLowerCase());
    return candidate;
  }

  String _safeFileName(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'site' : cleaned;
  }
}
