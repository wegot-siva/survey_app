import '../models/material_master_audit_entry.dart';
import '../models/material_master_item.dart';

/// Builds the audit entries a Material Master mutation should write.
///
/// Pure — no I/O, no id generation (entries come out with `id: ''`, same
/// convention as a freshly-built model the repository is about to insert).
/// Create/delete each produce one summary row; an edit produces one row per
/// field that actually changed, so the change log reads as a literal
/// field-level diff.
class MaterialMasterAuditBuilder {
  const MaterialMasterAuditBuilder();

  List<MaterialMasterAuditEntry> forCreate({
    required MaterialMasterItem item,
    required String changedByRole,
    required DateTime changedAt,
  }) {
    return [
      MaterialMasterAuditEntry(
        id: '',
        materialRowId: item.id,
        fieldChanged: '(created)',
        newValue: _summary(item),
        changedByRole: changedByRole,
        changedAt: changedAt,
      ),
    ];
  }

  List<MaterialMasterAuditEntry> forDelete({
    required MaterialMasterItem item,
    required String changedByRole,
    required DateTime changedAt,
  }) {
    return [
      MaterialMasterAuditEntry(
        id: '',
        materialRowId: item.id,
        fieldChanged: '(deleted)',
        oldValue: _summary(item),
        changedByRole: changedByRole,
        changedAt: changedAt,
      ),
    ];
  }

  /// One row per changed field; returns an empty list if nothing differs
  /// (e.g. the user opened and re-saved a row unchanged).
  List<MaterialMasterAuditEntry> forUpdate({
    required MaterialMasterItem oldItem,
    required MaterialMasterItem newItem,
    required String changedByRole,
    required DateTime changedAt,
  }) {
    return [
      for (final d in _diff(oldItem, newItem))
        MaterialMasterAuditEntry(
          id: '',
          materialRowId: newItem.id,
          fieldChanged: d.field,
          oldValue: d.oldValue,
          newValue: d.newValue,
          changedByRole: changedByRole,
          changedAt: changedAt,
        ),
    ];
  }

  String _summary(MaterialMasterItem item) {
    final parts = [
      item.materialName,
      if (item.sku.isNotEmpty) 'SKU ${item.sku}',
      '${item.group.code} — ${item.group.label}',
      '${item.quantityPerSensor} ${item.unit}',
    ];
    return parts.join(' · ');
  }

  List<({String field, String? oldValue, String? newValue})> _diff(
    MaterialMasterItem oldItem,
    MaterialMasterItem newItem,
  ) {
    final diffs = <({String field, String? oldValue, String? newValue})>[];
    void compare(String field, Object? oldV, Object? newV) {
      if (oldV == newV) return;
      diffs.add((
        field: field,
        oldValue: oldV?.toString(),
        newValue: newV?.toString(),
      ));
    }

    compare('Group', oldItem.group.label, newItem.group.label);
    compare('Material name', oldItem.materialName, newItem.materialName);
    compare('SKU', oldItem.sku, newItem.sku);
    compare('Item label', oldItem.itemLabel, newItem.itemLabel);
    compare('Unit', oldItem.unit, newItem.unit);
    compare('Behaviour', oldItem.behaviorType.label, newItem.behaviorType.label);
    compare('Sensor size', oldItem.sensorSize?.label, newItem.sensorSize?.label);
    compare('Sensor type', oldItem.sensorType?.label, newItem.sensorType?.label);
    compare(
      'Quantity per sensor',
      oldItem.quantityPerSensor,
      newItem.quantityPerSensor,
    );
    compare(
      'Derived formula',
      oldItem.derivedFormula?.label,
      newItem.derivedFormula?.label,
    );
    compare('Formula divisor', oldItem.formulaDivisor, newItem.formulaDivisor);
    compare(
      'Variable source',
      oldItem.variableSource?.label,
      newItem.variableSource?.label,
    );
    compare('Notes', oldItem.notes, newItem.notes);
    return diffs;
  }
}
