import 'survey_options.dart';

/// Material grouping A–G used to organize the BoM (Material Master phase).
enum MaterialGroup {
  a('A', 'WEGOTAqua (Sensor)'),
  b('B', 'DCU (S2S cable, Duct LoRa, Duct LoRa cables)'),
  c('C', 'Plumbing accessories'),
  d('D', 'Plumbing rework'),
  e('E', 'Electrical'),
  f('F', 'Consumables'),
  g('G', 'Labour');

  const MaterialGroup(this.code, this.label);

  /// Single-letter group code shown in the BoM (e.g. "A").
  final String code;
  final String label;
}

/// How a material row's quantity is computed by the BoM engine.
enum MaterialBehaviorType {
  /// Quantity = (matching sensor count) × [MaterialMasterItem.quantityPerSensor].
  fixed('Fixed (× sensor count)'),

  /// Quantity computed by [MaterialMasterItem.derivedFormula], using
  /// [MaterialMasterItem.formulaDivisor] as its only data-driven constant.
  derived('Derived (formula)'),

  /// Quantity pulled directly from a survey-measured field — see
  /// [MaterialMasterItem.variableSource].
  variable('Variable (from survey)');

  const MaterialBehaviorType(this.label);
  final String label;
}

/// Named derived-quantity formulas the BoM engine knows how to evaluate.
///
/// The formula *shape* lives in code; every numeric constant it needs (e.g.
/// the divisor in "ceil(wired sensors ÷ N)") is read from
/// [MaterialMasterItem.formulaDivisor] — changing that number is a Material
/// Master edit, never a code change.
enum DerivedFormula {
  ceilWiredSensorsDividedByDivisor('ceil(wired sensors ÷ N)');

  const DerivedFormula(this.label);
  final String label;
}

/// Survey-measured fields a VARIABLE material row can pull its quantity from.
enum VariableSource {
  ductLoraCableLength('Duct LoRa cable length (summed across units)'),
  sourceReworkCount('Source points marked rework (count)'),
  inletReworkCount('Inlet points marked rework (count)');

  const VariableSource(this.label);
  final String label;
}

/// One row of the Material Master: the material kit for a sensor variant (or
/// a general line not tied to one), with the data the BoM engine needs to
/// compute its quantity for a given site.
///
/// Every quantity here is DATA, read at BoM-generation time — the engine never
/// hardcodes a number. [quantityPerSensor] defaults to 0 ("TBD") until filled
/// in via the Material Master admin screen.
class MaterialMasterItem {
  const MaterialMasterItem({
    required this.id,
    required this.group,
    required this.materialName,
    required this.unit,
    required this.behaviorType,
    this.sku = '',
    this.sensorSize,
    this.sensorType,
    this.quantityPerSensor = 0,
    this.derivedFormula,
    this.formulaDivisor,
    this.variableSource,
    this.notes = '',
  });

  final String id;
  final MaterialGroup group;
  final String materialName;

  /// Optional SKU / part code. Free text — not every material has one yet.
  final String sku;

  final String unit;
  final MaterialBehaviorType behaviorType;

  /// Which sensor variant this row's kit applies to. Null matches any size /
  /// any type — use that for general lines (e.g. flat labour or consumables)
  /// rather than a specific sensor's kit.
  final SensorSize? sensorSize;
  final SensorType? sensorType;

  /// FIXED: quantity per matching sensor.
  final double quantityPerSensor;

  /// DERIVED: which formula, and the constant it uses.
  final DerivedFormula? derivedFormula;
  final double? formulaDivisor;

  /// VARIABLE: which survey-measured field this pulls its quantity from.
  final VariableSource? variableSource;

  final String notes;

  /// Returns a copy with a different [id]. Used when the repository assigns
  /// an id to a freshly added row.
  MaterialMasterItem copyWithId(String newId) => MaterialMasterItem(
    id: newId,
    group: group,
    materialName: materialName,
    unit: unit,
    behaviorType: behaviorType,
    sku: sku,
    sensorSize: sensorSize,
    sensorType: sensorType,
    quantityPerSensor: quantityPerSensor,
    derivedFormula: derivedFormula,
    formulaDivisor: formulaDivisor,
    variableSource: variableSource,
    notes: notes,
  );
}
