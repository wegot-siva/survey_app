// Unit tests for MaterialMasterAuditBuilder — the field-level diff that backs
// the Material Master change log. Create/delete each produce exactly one
// summary row; an edit produces one row per field that actually changed.

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/models/survey_options.dart';
import 'package:survey_app/services/material_master_audit_builder.dart';

void main() {
  const builder = MaterialMasterAuditBuilder();
  final now = DateTime(2026, 1, 1, 12, 30);

  const base = MaterialMasterItem(
    id: 'm1',
    group: MaterialGroup.a,
    materialName: 'WEGOTAqua sensor',
    sku: 'WGA-001',
    unit: 'pcs',
    behaviorType: MaterialBehaviorType.fixed,
    sensorSize: SensorSize.dn25,
    sensorType: SensorType.wired,
    quantityPerSensor: 2,
    notes: 'initial',
  );

  test('forCreate writes exactly one row with no old value', () {
    final entries = builder.forCreate(
      item: base,
      changedByRole: 'Admin',
      changedAt: now,
    );

    expect(entries, hasLength(1));
    expect(entries.single.id, isEmpty); // repository assigns the real id
    expect(entries.single.materialRowId, 'm1');
    expect(entries.single.fieldChanged, '(created)');
    expect(entries.single.oldValue, isNull);
    expect(entries.single.newValue, contains('WEGOTAqua sensor'));
    expect(entries.single.newValue, contains('WGA-001'));
    expect(entries.single.changedByRole, 'Admin');
    expect(entries.single.changedAt, now);
  });

  test('forDelete writes exactly one row with no new value', () {
    final entries = builder.forDelete(
      item: base,
      changedByRole: 'Admin',
      changedAt: now,
    );

    expect(entries, hasLength(1));
    expect(entries.single.fieldChanged, '(deleted)');
    expect(entries.single.newValue, isNull);
    expect(entries.single.oldValue, contains('WEGOTAqua sensor'));
  });

  test('forUpdate writes nothing when no field actually changed', () {
    final entries = builder.forUpdate(
      oldItem: base,
      newItem: base,
      changedByRole: 'Admin',
      changedAt: now,
    );
    expect(entries, isEmpty);
  });

  test('forUpdate writes one row per changed field, not per save', () {
    final edited = MaterialMasterItem(
      id: base.id,
      group: base.group,
      materialName: base.materialName,
      sku: 'WGA-002', // changed
      unit: base.unit,
      behaviorType: base.behaviorType,
      sensorSize: base.sensorSize,
      sensorType: base.sensorType,
      quantityPerSensor: 5, // changed
      notes: base.notes, // unchanged
    );

    final entries = builder.forUpdate(
      oldItem: base,
      newItem: edited,
      changedByRole: 'Admin',
      changedAt: now,
    );

    expect(entries, hasLength(2));
    final byField = {for (final e in entries) e.fieldChanged: e};
    expect(byField.keys, containsAll(['SKU', 'Quantity per sensor']));
    expect(byField['SKU']!.oldValue, 'WGA-001');
    expect(byField['SKU']!.newValue, 'WGA-002');
    expect(byField['Quantity per sensor']!.oldValue, '2.0');
    expect(byField['Quantity per sensor']!.newValue, '5.0');
    // Unchanged fields (materialName, notes, ...) must not appear.
    expect(byField.keys, isNot(contains('Notes')));
    expect(byField.keys, isNot(contains('Material name')));
  });

  test('forUpdate diffs nullable enum fields, including becoming null', () {
    final cleared = MaterialMasterItem(
      id: base.id,
      group: base.group,
      materialName: base.materialName,
      sku: base.sku,
      unit: base.unit,
      behaviorType: base.behaviorType,
      sensorType: base.sensorType,
      quantityPerSensor: base.quantityPerSensor,
      notes: base.notes,
      // sensorSize omitted -> null, i.e. "cleared to Any size"
    );

    final entries = builder.forUpdate(
      oldItem: base,
      newItem: cleared,
      changedByRole: 'Admin',
      changedAt: now,
    );

    expect(entries, hasLength(1));
    expect(entries.single.fieldChanged, 'Sensor size');
    expect(entries.single.oldValue, SensorSize.dn25.label);
    expect(entries.single.newValue, isNull);
  });

  test('every entry carries the given role and timestamp', () {
    final entries = builder.forCreate(
      item: base,
      changedByRole: 'Sales',
      changedAt: now,
    );
    expect(entries.single.changedByRole, 'Sales');
    expect(entries.single.changedAt, now);
  });
}
