import 'dart:math' as math;

import '../models/bom_line.dart';
import '../models/duct_lora.dart';
import '../models/inlet_point.dart';
import '../models/material_master_item.dart';
import '../models/source_point.dart';
import '../models/survey_options.dart';

/// One sensor variant (size + type) the survey's Source/Inlet counts require
/// a Group A catalog match for — used for both
/// [BomGenerationResult.groupAMissingVariants] (zero matches) and
/// [GroupAConflict] (2+ matches).
class GroupASensorVariant {
  const GroupASensorVariant(this.sensorSize, this.sensorType);

  final SensorSize sensorSize;
  final SensorType sensorType;

  /// e.g. "DN40 Wired" — matches the wording the Generate BoM screen's
  /// banner names each missing/conflicting variant with.
  String get label => '${sensorSize.label} ${sensorType.label}';

  @override
  bool operator ==(Object other) =>
      other is GroupASensorVariant &&
      other.sensorSize == sensorSize &&
      other.sensorType == sensorType;

  @override
  int get hashCode => Object.hash(sensorSize, sensorType);
}

/// A sensor variant with 2+ active Group A material_master_items rows
/// matching it — [BomEngine] refuses to guess which one is right, so no
/// [BomLine] is generated for this variant until an admin removes/merges the
/// duplicate in Material Master.
class GroupAConflict {
  const GroupAConflict({
    required this.variant,
    required this.matchingMaterialNames,
  });

  final GroupASensorVariant variant;

  /// Every conflicting row's [MaterialMasterItem.materialName], named in
  /// full so the admin doesn't have to go hunting for which rows collide.
  final List<String> matchingMaterialNames;
}

/// [BomEngine.generate]'s full result: the per-group lines the rest of the
/// app already expects, plus Group A's catalog-matching health — the two
/// lists that must block Finalize (see [hasBlockingGroupAIssues]). No other
/// group's incompleteness is ever tracked here; this exists solely because
/// Group A's restored catalog-matching can't be allowed to silently omit or
/// silently guess at a sensor variant.
class BomGenerationResult {
  const BomGenerationResult({
    required this.lines,
    required this.groupAMissingVariants,
    required this.groupAConflicts,
  });

  final Map<MaterialGroup, List<BomLine>> lines;

  /// Sensor variants present in the survey's Source/Inlet counts with zero
  /// matching active (non-deleted) Group A material_master_items rows.
  final List<GroupASensorVariant> groupAMissingVariants;

  /// Sensor variants present in the survey's Source/Inlet counts with 2+
  /// matching active Group A material_master_items rows.
  final List<GroupAConflict> groupAConflicts;

  bool get hasBlockingGroupAIssues =>
      groupAMissingVariants.isNotEmpty || groupAConflicts.isNotEmpty;
}

/// Computes a BoM from Material Master rows + a site's survey data.
///
/// Pure computation, no I/O — the repository supplies the inputs. Every
/// quantity comes from a [MaterialMasterItem] row or a survey field passed
/// in; this class never hardcodes a material quantity, only the *shape* of
/// how FIXED / DERIVED / VARIABLE rows (and Group A's catalog-matching,
/// below) turn into numbers.
///
/// Group A (WEGOTAqua sensors) doesn't use the generic FIXED/DERIVED/
/// VARIABLE dispatch every other group's rows go through — instead, for each
/// sensor variant the survey's Source/Inlet counts actually contain, it looks
/// up the matching active group_code='A' row directly (by sensor size +
/// type) and reads that row's materialName/sku/unit/quantityPerSensor. A
/// variant with zero or 2+ matches never gets a guessed [BomLine] — it's
/// surfaced instead via [BomGenerationResult.groupAMissingVariants] /
/// [groupAConflicts], which the caller must block Finalize on.
class BomEngine {
  const BomEngine();

  /// Returns the BoM grouped by [MaterialGroup] (in A→G order) plus Group
  /// A's catalog-matching health. Groups with no matching rows are present
  /// with an empty list (not omitted), so the UI can render section headers
  /// consistently.
  BomGenerationResult generate({
    required List<MaterialMasterItem> materials,
    required List<SourcePoint> sourcePoints,
    required List<InletPoint> inletPoints,
    required List<DuctLora> ductLoras,
  }) {
    final sensorCounts = _countSensors(sourcePoints, inletPoints);
    final totalWiredSensors = sensorCounts.entries
        .where((e) => e.key.$2 == SensorType.wired)
        .fold(0, (sum, e) => sum + e.value);

    final result = <MaterialGroup, List<BomLine>>{
      for (final group in MaterialGroup.values) group: <BomLine>[],
    };

    final groupAResult = _generateGroupA(sensorCounts, materials);
    result[MaterialGroup.a] = groupAResult.lines;

    for (final item in materials) {
      // Group A never goes through the generic dispatch below — see
      // _generateGroupA. Any group_code='A' row here is ignored outright,
      // never merged in and never double-counted.
      if (item.group == MaterialGroup.a) continue;

      final quantity = _quantityFor(
        item,
        sensorCounts: sensorCounts,
        totalWiredSensors: totalWiredSensors,
        sourcePoints: sourcePoints,
        inletPoints: inletPoints,
        ductLoras: ductLoras,
      );
      result[item.group]!.add(
        BomLine(
          group: item.group,
          materialName: item.materialName,
          sku: item.sku,
          itemLabel: item.itemLabel,
          variantLabel: _variantLabel(item),
          sensorSize: item.sensorSize,
          sensorType: item.sensorType,
          quantity: quantity,
          unit: item.unit,
        ),
      );
    }

    return BomGenerationResult(
      lines: result,
      groupAMissingVariants: groupAResult.missing,
      groupAConflicts: groupAResult.conflicts,
    );
  }

  /// For every (size, type) variant the survey's own counts actually
  /// contain (regardless of whether the summed count is 0 — a point that
  /// declares the variant still needs a catalog match): looks up active
  /// group_code='A' rows matching that exact size + type.
  ///
  /// - Exactly one match: emits a [BomLine] from that row's own
  ///   materialName/sku/unit/quantityPerSensor — quantity = survey count ×
  ///   quantityPerSensor.
  /// - Zero matches: no line — the variant is collected into [missing]
  ///   instead of being silently dropped.
  /// - 2+ matches: no line — collected into [conflicts], naming every
  ///   colliding row, rather than guessing which one is right.
  ///
  /// Variants sorted by [SensorSize]/[SensorType] declaration order, so the
  /// banner listing [missing]/[conflicts] reads in a stable, predictable
  /// order every time.
  ({List<BomLine> lines, List<GroupASensorVariant> missing, List<GroupAConflict> conflicts})
  _generateGroupA(
    Map<(SensorSize, SensorType), int> sensorCounts,
    List<MaterialMasterItem> materials,
  ) {
    final groupAMaterials = materials.where((m) => m.group == MaterialGroup.a);

    final lines = <BomLine>[];
    final missing = <GroupASensorVariant>[];
    final conflicts = <GroupAConflict>[];

    final requiredVariants = sensorCounts.keys.toList()
      ..sort((a, b) {
        final sizeCompare = SensorSize.values
            .indexOf(a.$1)
            .compareTo(SensorSize.values.indexOf(b.$1));
        if (sizeCompare != 0) return sizeCompare;
        return SensorType.values.indexOf(a.$2).compareTo(SensorType.values.indexOf(b.$2));
      });

    for (final (size, type) in requiredVariants) {
      final count = sensorCounts[(size, type)] ?? 0;
      final matches = groupAMaterials
          .where((m) => m.sensorSize == size && m.sensorType == type)
          .toList();

      if (matches.isEmpty) {
        missing.add(GroupASensorVariant(size, type));
      } else if (matches.length > 1) {
        conflicts.add(
          GroupAConflict(
            variant: GroupASensorVariant(size, type),
            matchingMaterialNames: matches.map((m) => m.materialName).toList(),
          ),
        );
      } else {
        final row = matches.single;
        lines.add(
          BomLine(
            group: MaterialGroup.a,
            materialName: row.materialName,
            sku: row.sku,
            itemLabel: row.itemLabel,
            variantLabel: '${size.label} · ${type.label}',
            sensorSize: size,
            sensorType: type,
            quantity: count * row.quantityPerSensor,
            unit: row.unit,
          ),
        );
      }
    }

    return (lines: lines, missing: missing, conflicts: conflicts);
  }

  double _quantityFor(
    MaterialMasterItem item, {
    required Map<(SensorSize, SensorType), int> sensorCounts,
    required int totalWiredSensors,
    required List<SourcePoint> sourcePoints,
    required List<InletPoint> inletPoints,
    required List<DuctLora> ductLoras,
  }) {
    switch (item.behaviorType) {
      case MaterialBehaviorType.fixed:
        final matchingCount = sensorCounts.entries
            .where(
              (e) =>
                  (item.sensorSize == null || e.key.$1 == item.sensorSize) &&
                  (item.sensorType == null || e.key.$2 == item.sensorType),
            )
            .fold(0, (sum, e) => sum + e.value);
        return matchingCount * item.quantityPerSensor;

      case MaterialBehaviorType.derived:
        return _derivedQuantity(item, totalWiredSensors);

      case MaterialBehaviorType.variable:
        return _variableQuantity(item, sourcePoints, inletPoints, ductLoras);
    }
  }

  double _derivedQuantity(MaterialMasterItem item, int totalWiredSensors) {
    final divisor = item.formulaDivisor;
    if (divisor == null || divisor <= 0) return 0;

    switch (item.derivedFormula) {
      case DerivedFormula.ceilWiredSensorsDividedByDivisor:
        return math.max(0, (totalWiredSensors / divisor).ceil()).toDouble();
      case null:
        return 0;
    }
  }

  double _variableQuantity(
    MaterialMasterItem item,
    List<SourcePoint> sourcePoints,
    List<InletPoint> inletPoints,
    List<DuctLora> ductLoras,
  ) {
    switch (item.variableSource) {
      case VariableSource.ductLoraCableLength:
        return ductLoras.fold(0.0, (sum, d) => sum + (d.cableLength ?? 0));
      case VariableSource.sourceReworkCount:
        return sourcePoints.where((s) => s.rework == true).length.toDouble();
      case VariableSource.inletReworkCount:
        return inletPoints.where((i) => i.rework == true).length.toDouble();
      case null:
        return 0;
    }
  }

  /// Sums each survey point's `qty` into a (size, type) bucket. Points
  /// missing either field are skipped — they can't be safely counted toward
  /// any specific variant.
  Map<(SensorSize, SensorType), int> _countSensors(
    List<SourcePoint> sourcePoints,
    List<InletPoint> inletPoints,
  ) {
    final counts = <(SensorSize, SensorType), int>{};
    void add(SensorSize? size, SensorType? type, int? qty) {
      if (size == null || type == null) return;
      final key = (size, type);
      counts[key] = (counts[key] ?? 0) + (qty ?? 0);
    }

    for (final sp in sourcePoints) {
      add(sp.sensorSize, sp.sensorType, sp.qty);
    }
    for (final ip in inletPoints) {
      add(ip.sensorSize, ip.sensorType, ip.qty);
    }
    return counts;
  }

  String _variantLabel(MaterialMasterItem item) {
    final parts = [
      item.sensorSize?.label,
      item.sensorType?.label,
    ].whereType<String>();
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}
