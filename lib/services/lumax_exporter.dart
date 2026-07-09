import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/material_master_item.dart';
import '../models/survey_options.dart';
import 'bom_revision_engine.dart';

/// Writes a survey's running-total BoM to the Lumax .xlsx format: one sheet
/// per sensor variant present (e.g. "DN25 Wired", "DN25 Wireless"), each with
/// a site-name row, a header row [No., Item, Materials, Size, Qty, Unit,
/// Unit price, Total], then group header rows (A–G) with materials nested
/// under each — numbering restarts per group. Unit price/Total stay blank
/// (filled downstream by office, same as Sun_BOM's ERP columns).
///
/// Reads the exact same [BomRunningTotalLine] input as [SunBomExporter] —
/// same data source, different formatter. Pure formatting — never computes
/// quantities.
class LumaxExporter {
  const LumaxExporter();

  static const _headers = [
    'No.',
    'Item',
    'Materials',
    'Size',
    'Qty',
    'Unit',
    'Unit price',
    'Total',
  ];

  /// Sheet label for lines with neither [SensorSize] nor [SensorType] set —
  /// most D/E/G manual/revision entries, which aren't tied to a variant.
  static const _generalSheetLabel = 'General';

  /// Builds the workbook from [lines] and writes it to a temp file (suitable
  /// for the share sheet). Returns the file path. [siteName] also names the
  /// row written at the top of every sheet. The file itself is named
  /// `<site name>-Standard-v<version>.xlsx` — deterministic, so re-exporting
  /// the same site/version simply overwrites the prior temp file (harmless;
  /// it's consumed immediately by the share sheet).
  Future<String> export({
    required String siteName,
    required List<BomRunningTotalLine> lines,
    required int version,
  }) async {
    final bytes = buildXlsxBytes(siteName: siteName, lines: lines);
    final dir = await getTemporaryDirectory();
    final filePath = p.join(
      dir.path,
      '${_safeFileName(siteName)}-Standard-v$version.xlsx',
    );
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  /// Pure workbook construction (no I/O) — exposed so the formatting can be
  /// unit-tested without platform plugins. Excludes any line whose running
  /// total is 0 or below, same as [SunBomExporter].
  List<int> buildXlsxBytes({
    required String siteName,
    required List<BomRunningTotalLine> lines,
  }) {
    final kept = lines.where((l) => l.rawQty > 0).toList();

    final byVariant = <(SensorSize?, SensorType?), List<BomRunningTotalLine>>{};
    for (final line in kept) {
      final key = (line.sensorSize, line.sensorType);
      (byVariant[key] ??= []).add(line);
    }

    final variantKeys = byVariant.keys.toList()
      ..sort((a, b) {
        final aSize = a.$1?.index ?? SensorSize.values.length;
        final bSize = b.$1?.index ?? SensorSize.values.length;
        if (aSize != bSize) return aSize.compareTo(bSize);
        final aType = a.$2?.index ?? SensorType.values.length;
        final bType = b.$2?.index ?? SensorType.values.length;
        return aType.compareTo(bType);
      });

    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    final usedNames = <String>{};

    for (final key in variantKeys) {
      final name = _uniqueSheetName(_sheetLabel(key.$1, key.$2), usedNames);
      _writeVariantSheet(excel[name], siteName, byVariant[key]!);
    }

    // Remove the stray default sheet, unless a variant happened to use that
    // name. Guard against deleting the only sheet (no kept lines at all).
    if (defaultSheet != null &&
        usedNames.isNotEmpty &&
        !usedNames.contains(defaultSheet.toLowerCase())) {
      excel.delete(defaultSheet);
    }

    return excel.encode()!;
  }

  void _writeVariantSheet(
    Sheet sheet,
    String siteName,
    List<BomRunningTotalLine> lines,
  ) {
    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 24);
    sheet.setColumnWidth(2, 32);
    sheet.setColumnWidth(3, 16);
    sheet.setColumnWidth(4, 10);
    sheet.setColumnWidth(5, 10);
    sheet.setColumnWidth(6, 12);
    sheet.setColumnWidth(7, 12);

    _row(sheet, [TextCellValue(siteName)], bold: true);
    _row(sheet, [for (final h in _headers) TextCellValue(h)], bold: true);

    for (final group in MaterialGroup.values) {
      final groupLines = lines.where((l) => l.group == group).toList();
      if (groupLines.isEmpty) continue;

      _row(sheet, [TextCellValue('${group.code} — ${group.label}')], bold: true);

      var no = 1;
      for (final line in groupLines) {
        sheet.appendRow([
          IntCellValue(no++),
          TextCellValue(line.itemLabel),
          TextCellValue(line.materialName),
          TextCellValue(_sizeLabel(line.sensorSize, line.sensorType)),
          _qtyCell(line.displayQty),
          TextCellValue(line.unit),
          // Unit price, Total — filled in later by the office side, never
          // by the app.
          TextCellValue(''),
          TextCellValue(''),
        ]);
      }
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

  String _sheetLabel(SensorSize? size, SensorType? type) {
    final parts = [size?.label, type?.label].whereType<String>();
    return parts.isEmpty ? _generalSheetLabel : parts.join(' ');
  }

  String _sizeLabel(SensorSize? size, SensorType? type) {
    final parts = [size?.label, type?.label].whereType<String>();
    return parts.isEmpty ? '' : parts.join(' · ');
  }

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
