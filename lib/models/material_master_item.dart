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

/// Resolves a stored or remote `group_code` to its [MaterialGroup], or null
/// if it is not one this app knows.
///
/// Accepts either form, case-insensitively, because both are in circulation:
/// the lowercase enum name ('c') is what this app writes, on both the local
/// row and the pushed row, while the uppercase display letter ('C') is what
/// the bulk SQL plumbing-catalog import used for every row it created.
///
/// Shared by the remote pull and the local read so the two cannot disagree
/// about what a code means. They previously did: the local read matched only
/// the lowercase name, so an uppercase code reaching local storage would
/// have failed to resolve there while resolving correctly on the pull.
///
/// Returns null rather than guessing. No caller may substitute
/// [MaterialGroup.a] — see [kUnknownMaterialGroupFallback].
MaterialGroup? materialGroupFromCode(String? code) {
  if (code == null) return null;
  final normalized = code.toLowerCase();
  for (final group in MaterialGroup.values) {
    if (group.name == normalized || group.code.toLowerCase() == normalized) {
      return group;
    }
  }
  return null;
}

/// Where a material whose `group_code` this app does not recognise is put.
///
/// The one property that matters is that it is NOT [MaterialGroup.a].
/// Group A is the only automatically-calculated group: the BoM engine builds
/// its candidate set from every Group A material and resolves each survey
/// point's `materialId` against it, so a row that lands in A can contribute
/// real quantities to a customer-facing BoM. Every other group is manual —
/// an unrecognised row there produces a visible line rather than a wrong
/// number, and any point referencing it is reported as unresolved, which is
/// exactly the loud signal wanted.
///
/// G ("Labour") is otherwise arbitrary, and mislabelling is a real if minor
/// cost. The honest fix is a dedicated `unknown` member, but MaterialGroup
/// is enumerated in 15 places including two user-facing dropdowns
/// (`items: MaterialGroup.values`), so adding one would put "unknown" in
/// front of users as a selectable group. Deliberately deferred.
const MaterialGroup kUnknownMaterialGroupFallback = MaterialGroup.g;

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
    this.itemLabel = '',
    this.sensorSize,
    this.sensorType,
    this.quantityPerSensor = 0,
    this.derivedFormula,
    this.formulaDivisor,
    this.variableSource,
    this.notes = '',
    this.materialType,
    this.category,
    this.variant,
    this.sizeMm,
    this.sizeDisplay,
  });

  final String id;
  final MaterialGroup group;
  final String materialName;

  /// Optional SKU / part code. Free text — not every material has one yet.
  final String sku;

  /// Optional short label distinct from [materialName] — e.g. an export
  /// column ("Item") that isn't the full descriptive name ("Materials").
  /// Free text; blank until an admin fills it in.
  final String itemLabel;

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

  /// The following five fields drive the 4-level cascading picker (Material
  /// Type → Category → Variant → Size) used only for group C's plumbing
  /// catalog (uPVC/CPVC fittings). All null for every other row — D/E/F/G
  /// rows, and any C row from the earlier Lumax-derived seed, keep using the
  /// flat single-dropdown picker unaffected by these columns.
  ///
  /// e.g. 'uPVC', 'CPVC'.
  final String? materialType;

  /// e.g. 'Elbow 90°', 'Tee', 'Coupler'.
  final String? category;

  /// e.g. 'SCH40', 'SCH80', 'Brass Threaded'.
  final String? variant;

  /// Nominal DN in mm — sort/join field only, never shown directly. For a
  /// reducer/multi-size fitting, this is the larger of the two sizes.
  final double? sizeMm;

  /// Human-readable size shown in the picker, e.g. '1¼"' or '1¼" x 1"' for a
  /// reducer.
  final String? sizeDisplay;

  /// Returns a copy with a different [id]. Used when the repository assigns
  /// an id to a freshly added row.
  MaterialMasterItem copyWithId(String newId) => MaterialMasterItem(
    id: newId,
    group: group,
    materialName: materialName,
    unit: unit,
    behaviorType: behaviorType,
    sku: sku,
    itemLabel: itemLabel,
    sensorSize: sensorSize,
    sensorType: sensorType,
    quantityPerSensor: quantityPerSensor,
    derivedFormula: derivedFormula,
    formulaDivisor: formulaDivisor,
    variableSource: variableSource,
    notes: notes,
    materialType: materialType,
    category: category,
    variant: variant,
    sizeMm: sizeMm,
    sizeDisplay: sizeDisplay,
  );
}
