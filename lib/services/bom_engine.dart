import 'dart:math' as math;

import '../models/bom_line.dart';
import '../models/duct_lora.dart';
import '../models/inlet_point.dart';
import '../models/material_master_item.dart';
import '../models/source_point.dart';
import '../models/survey_options.dart';

/// A source/inlet point whose sensor selection doesn't resolve to a
/// currently-active Group A material_master_items row — either it was never
/// assigned one (materialId null, e.g. a point still on the old size/type
/// entry mechanism) or the material it referenced has since been
/// deactivated/removed. [BomEngine] never guesses which material a point
/// like this should count toward, so no [BomLine] is generated for it — it's
/// surfaced here instead, via [BomGenerationResult.groupAUnresolvedPoints].
class GroupAUnresolvedPoint {
  const GroupAUnresolvedPoint({required this.pointType, required this.label});

  /// e.g. "Source point" or "Inlet point".
  final String pointType;

  /// Best-effort human label for the point (block/apartment), so the
  /// Generate BoM screen's banner can name exactly which point needs
  /// reopening and re-picking, not just an abstract category.
  final String label;

  String get description => '$pointType ($label)';
}

/// [BomEngine.generate]'s full result: the per-group lines the rest of the
/// app already expects, plus Group A's unresolved points — the list that
/// must block Finalize (see [hasBlockingGroupAIssues]). No other group's
/// incompleteness is ever tracked here; this exists solely because Group A's
/// material-reference matching can't be allowed to silently omit a point
/// whose sensor was never (re-)assigned.
class BomGenerationResult {
  const BomGenerationResult({
    required this.lines,
    required this.groupAUnresolvedPoints,
  });

  final Map<MaterialGroup, List<BomLine>> lines;

  /// Source/inlet points whose materialId doesn't resolve to a currently
  /// active Group A material_master_items row.
  final List<GroupAUnresolvedPoint> groupAUnresolvedPoints;

  bool get hasBlockingGroupAIssues => groupAUnresolvedPoints.isNotEmpty;
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
/// VARIABLE dispatch every other group's rows go through — instead, each
/// Source/Inlet point directly references the specific active group_code='A'
/// row it was assigned via the material dropdown (materialId), and that
/// row's own materialName/sku/unit/quantityPerSensor is read straight off of
/// it. A point whose reference doesn't resolve to a currently-active Group A
/// row never gets a guessed [BomLine] — it's surfaced instead via
/// [BomGenerationResult.groupAUnresolvedPoints], which the caller must block
/// Finalize on.
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

    final groupAResult = _generateGroupA(sourcePoints, inletPoints, materials);
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
      groupAUnresolvedPoints: groupAResult.unresolved,
    );
  }

  /// For every Source/Inlet point: resolves its materialId against the
  /// active group_code='A' rows and folds its qty into that material's
  /// running total. A point whose materialId is null or doesn't match any
  /// currently-active row is collected into [unresolved] instead — never
  /// silently dropped, and never guessed at.
  ///
  /// One [BomLine] per referenced material (not per point), reading that
  /// row's own materialName/sku/unit/quantityPerSensor — quantity = summed
  /// point count × quantityPerSensor. Two points can legitimately reference
  /// two different materials for what looks like the same nominal size, and
  /// that's not a conflict: the engineer picked the specific product
  /// actually installed at each point, which is the whole point of matching
  /// by reference instead of by abstract size + type.
  ({List<BomLine> lines, List<GroupAUnresolvedPoint> unresolved})
  _generateGroupA(
    List<SourcePoint> sourcePoints,
    List<InletPoint> inletPoints,
    List<MaterialMasterItem> materials,
  ) {
    final groupAMaterials = {
      for (final m in materials.where((m) => m.group == MaterialGroup.a))
        m.id: m,
    };

    final materialCounts = <String, int>{};
    final unresolved = <GroupAUnresolvedPoint>[];

    void process(String pointType, String label, String? materialId, int? qty) {
      if (materialId == null || !groupAMaterials.containsKey(materialId)) {
        unresolved.add(GroupAUnresolvedPoint(pointType: pointType, label: label));
        return;
      }
      materialCounts[materialId] = (materialCounts[materialId] ?? 0) + (qty ?? 0);
    }

    for (final sp in sourcePoints) {
      process('Source point', _pointLabel(sp.block, sp.apartment), sp.materialId, sp.qty);
    }
    for (final ip in inletPoints) {
      process('Inlet point', _pointLabel(ip.block, ip.apartmentBhk), ip.materialId, ip.qty);
    }

    final lines = <BomLine>[
      for (final entry in materialCounts.entries)
        BomLine(
          group: MaterialGroup.a,
          materialName: groupAMaterials[entry.key]!.materialName,
          sku: groupAMaterials[entry.key]!.sku,
          itemLabel: groupAMaterials[entry.key]!.itemLabel,
          variantLabel: _variantLabel(groupAMaterials[entry.key]!),
          sensorSize: groupAMaterials[entry.key]!.sensorSize,
          sensorType: groupAMaterials[entry.key]!.sensorType,
          quantity: entry.value * groupAMaterials[entry.key]!.quantityPerSensor,
          unit: groupAMaterials[entry.key]!.unit,
        ),
    ]..sort((a, b) => a.materialName.compareTo(b.materialName));

    return (lines: lines, unresolved: unresolved);
  }

  /// Best-effort human label for a point — block + apartment/BHK, whichever
  /// is set — so [GroupAUnresolvedPoint] can name exactly which point needs
  /// reopening, not just an abstract category.
  String _pointLabel(String? block, String apartment) {
    final parts = [
      if (block != null && block.isNotEmpty) 'Block $block',
      if (apartment.isNotEmpty) apartment,
    ];
    return parts.isEmpty ? 'unlabeled' : parts.join(' — ');
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
