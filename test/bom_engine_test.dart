// Unit tests for BomEngine — the core "never hardcode a quantity" guarantee.
// Every number here comes from a MaterialMasterItem or survey field passed in,
// never from a constant inside the engine.

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/models/duct_lora.dart';
import 'package:survey_app/models/inlet_point.dart';
import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/models/source_point.dart';
import 'package:survey_app/models/survey_options.dart';
import 'package:survey_app/services/bom_engine.dart';

void main() {
  const engine = BomEngine();

  SourcePoint sourcePoint({
    SensorSize? sensorSize,
    SensorType? sensorType,
    int? qty,
    bool? rework,
  }) => SourcePoint(
    id: 'sp',
    siteId: 'site',
    sensorSize: sensorSize,
    sensorType: sensorType,
    qty: qty,
    rework: rework,
  );

  InletPoint inletPoint({
    SensorSize? sensorSize,
    SensorType? sensorType,
    int? qty,
    bool? rework,
  }) => InletPoint(
    id: 'ip',
    siteId: 'site',
    sensorSize: sensorSize,
    sensorType: sensorType,
    qty: qty,
    rework: rework,
  );

  test('FIXED multiplies matching sensor count by quantityPerSensor', () {
    final materials = [
      const MaterialMasterItem(
        id: 'm1',
        group: MaterialGroup.a,
        materialName: 'WEGOTAqua DN25 Wired sensor',
        unit: 'pcs',
        behaviorType: MaterialBehaviorType.fixed,
        sensorSize: SensorSize.dn25,
        sensorType: SensorType.wired,
        quantityPerSensor: 2,
      ),
    ];
    final bom = engine.generate(
      materials: materials,
      sourcePoints: [
        sourcePoint(sensorSize: SensorSize.dn25, sensorType: SensorType.wired, qty: 3),
      ],
      inletPoints: [
        inletPoint(sensorSize: SensorSize.dn25, sensorType: SensorType.wired, qty: 2),
      ],
      ductLoras: const [],
    );

    expect(bom[MaterialGroup.a]!.single.quantity, 10); // (3+2) * 2
  });

  test('FIXED ignores sensors of a different size/type', () {
    final materials = [
      const MaterialMasterItem(
        id: 'm1',
        group: MaterialGroup.a,
        materialName: 'WEGOTAqua DN25 Wired sensor',
        unit: 'pcs',
        behaviorType: MaterialBehaviorType.fixed,
        sensorSize: SensorSize.dn25,
        sensorType: SensorType.wired,
        quantityPerSensor: 1,
      ),
    ];
    final bom = engine.generate(
      materials: materials,
      sourcePoints: [
        sourcePoint(sensorSize: SensorSize.dn50, sensorType: SensorType.wired, qty: 5),
        sourcePoint(sensorSize: SensorSize.dn25, sensorType: SensorType.wireless, qty: 5),
      ],
      inletPoints: const [],
      ductLoras: const [],
    );

    expect(bom[MaterialGroup.a]!.single.quantity, 0);
  });

  test('FIXED with no size/type filter sums every classified sensor', () {
    final materials = [
      const MaterialMasterItem(
        id: 'm1',
        group: MaterialGroup.g,
        materialName: 'Installation labour',
        unit: 'hr',
        behaviorType: MaterialBehaviorType.fixed,
        quantityPerSensor: 0.5,
      ),
    ];
    final bom = engine.generate(
      materials: materials,
      sourcePoints: [
        sourcePoint(sensorSize: SensorSize.dn25, sensorType: SensorType.wired, qty: 4),
      ],
      inletPoints: [
        inletPoint(sensorSize: SensorSize.dn100, sensorType: SensorType.wireless, qty: 6),
      ],
      ductLoras: const [],
    );

    expect(bom[MaterialGroup.g]!.single.quantity, 5); // (4+6) * 0.5
  });

  test('quantityPerSensor of 0 (TBD default) yields 0 regardless of count', () {
    final materials = [
      const MaterialMasterItem(
        id: 'm1',
        group: MaterialGroup.c,
        materialName: 'Unknown wired accessory',
        unit: 'pcs',
        behaviorType: MaterialBehaviorType.fixed,
        sensorType: SensorType.wired,
      ),
    ];
    final bom = engine.generate(
      materials: materials,
      sourcePoints: [
        sourcePoint(sensorSize: SensorSize.dn40, sensorType: SensorType.wired, qty: 100),
      ],
      inletPoints: const [],
      ductLoras: const [],
    );

    expect(bom[MaterialGroup.c]!.single.quantity, 0);
  });

  test('DERIVED computes ceil(total wired sensors / formulaDivisor)', () {
    final materials = [
      const MaterialMasterItem(
        id: 'm1',
        group: MaterialGroup.b,
        materialName: 'Duct LoRa',
        unit: 'pcs',
        behaviorType: MaterialBehaviorType.derived,
        derivedFormula: DerivedFormula.ceilWiredSensorsDividedByDivisor,
        formulaDivisor: 20,
      ),
    ];
    final bom = engine.generate(
      materials: materials,
      sourcePoints: [
        sourcePoint(sensorSize: SensorSize.dn25, sensorType: SensorType.wired, qty: 25),
      ],
      inletPoints: [
        inletPoint(sensorSize: SensorSize.dn50, sensorType: SensorType.wired, qty: 20),
        // Wireless sensors must not count toward the wired-only formula.
        inletPoint(sensorSize: SensorSize.dn40, sensorType: SensorType.wireless, qty: 999),
      ],
      ductLoras: const [],
    );

    // (25 + 20) wired = 45; ceil(45 / 20) = 3.
    expect(bom[MaterialGroup.b]!.single.quantity, 3);
  });

  test('changing only the divisor changes the DERIVED result (no hardcoding)', () {
    MaterialMasterItem ductLoraRow(double divisor) => MaterialMasterItem(
      id: 'm1',
      group: MaterialGroup.b,
      materialName: 'Duct LoRa',
      unit: 'pcs',
      behaviorType: MaterialBehaviorType.derived,
      derivedFormula: DerivedFormula.ceilWiredSensorsDividedByDivisor,
      formulaDivisor: divisor,
    );
    final sourcePoints = [
      sourcePoint(sensorSize: SensorSize.dn25, sensorType: SensorType.wired, qty: 41),
    ];

    final bomWith20 = engine.generate(
      materials: [ductLoraRow(20)],
      sourcePoints: sourcePoints,
      inletPoints: const [],
      ductLoras: const [],
    );
    final bomWith10 = engine.generate(
      materials: [ductLoraRow(10)],
      sourcePoints: sourcePoints,
      inletPoints: const [],
      ductLoras: const [],
    );

    expect(bomWith20[MaterialGroup.b]!.single.quantity, 3); // ceil(41/20)
    expect(bomWith10[MaterialGroup.b]!.single.quantity, 5); // ceil(41/10)
  });

  test('DERIVED with no divisor set (TBD) yields 0', () {
    final materials = [
      const MaterialMasterItem(
        id: 'm1',
        group: MaterialGroup.b,
        materialName: 'Duct LoRa',
        unit: 'pcs',
        behaviorType: MaterialBehaviorType.derived,
        derivedFormula: DerivedFormula.ceilWiredSensorsDividedByDivisor,
      ),
    ];
    final bom = engine.generate(
      materials: materials,
      sourcePoints: [
        sourcePoint(sensorSize: SensorSize.dn25, sensorType: SensorType.wired, qty: 100),
      ],
      inletPoints: const [],
      ductLoras: const [],
    );

    expect(bom[MaterialGroup.b]!.single.quantity, 0);
  });

  test('VARIABLE sums Duct LoRa cable length across units', () {
    final materials = [
      const MaterialMasterItem(
        id: 'm1',
        group: MaterialGroup.b,
        materialName: 'Duct LoRa cable',
        unit: 'm',
        behaviorType: MaterialBehaviorType.variable,
        variableSource: VariableSource.ductLoraCableLength,
      ),
    ];
    final bom = engine.generate(
      materials: materials,
      sourcePoints: const [],
      inletPoints: const [],
      ductLoras: [
        const DuctLora(id: 'd1', siteId: 'site', cableLength: 12.5),
        const DuctLora(id: 'd2', siteId: 'site', cableLength: 7.5),
        const DuctLora(id: 'd3', siteId: 'site'), // null cable length -> 0
      ],
    );

    expect(bom[MaterialGroup.b]!.single.quantity, 20);
  });

  test('VARIABLE counts rework-flagged source and inlet points separately', () {
    final materials = [
      const MaterialMasterItem(
        id: 'm1',
        group: MaterialGroup.d,
        materialName: 'Source rework kit',
        unit: 'set',
        behaviorType: MaterialBehaviorType.variable,
        variableSource: VariableSource.sourceReworkCount,
      ),
      const MaterialMasterItem(
        id: 'm2',
        group: MaterialGroup.d,
        materialName: 'Inlet rework kit',
        unit: 'set',
        behaviorType: MaterialBehaviorType.variable,
        variableSource: VariableSource.inletReworkCount,
      ),
    ];
    final bom = engine.generate(
      materials: materials,
      sourcePoints: [
        sourcePoint(rework: true),
        sourcePoint(rework: false),
        sourcePoint(rework: true),
      ],
      inletPoints: [inletPoint(rework: true)],
      ductLoras: const [],
    );

    final lines = bom[MaterialGroup.d]!;
    expect(lines.firstWhere((l) => l.materialName == 'Source rework kit').quantity, 2);
    expect(lines.firstWhere((l) => l.materialName == 'Inlet rework kit').quantity, 1);
  });

  test('every MaterialGroup is present in the result, even when empty', () {
    final bom = engine.generate(
      materials: const [],
      sourcePoints: const [],
      inletPoints: const [],
      ductLoras: const [],
    );

    for (final group in MaterialGroup.values) {
      expect(bom.containsKey(group), isTrue);
      expect(bom[group], isEmpty);
    }
  });
}
