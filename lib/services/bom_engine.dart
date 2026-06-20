import 'dart:math' as math;

import '../models/bom_line.dart';
import '../models/duct_lora.dart';
import '../models/inlet_point.dart';
import '../models/material_master_item.dart';
import '../models/source_point.dart';
import '../models/survey_options.dart';

/// Computes a BoM from Material Master rows + a site's survey data.
///
/// Pure computation, no I/O — the repository supplies the inputs. Every
/// quantity comes from the [MaterialMasterItem] rows passed in; this class
/// never hardcodes a material quantity, only the *shape* of how FIXED /
/// DERIVED / VARIABLE rows turn into numbers.
class BomEngine {
  const BomEngine();

  /// Returns the BoM grouped by [MaterialGroup], in A→G order. Groups with no
  /// matching rows are present with an empty list (not omitted), so the UI
  /// can render section headers consistently.
  Map<MaterialGroup, List<BomLine>> generate({
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

    for (final item in materials) {
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
          variantLabel: _variantLabel(item),
          quantity: quantity,
          unit: item.unit,
        ),
      );
    }
    return result;
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
