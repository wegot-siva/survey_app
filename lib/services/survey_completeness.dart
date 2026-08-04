import '../models/site.dart';

/// One section of a survey that has nothing recorded in it.
///
/// Deliberately describes a *gap*, never a verdict: whether a given gap
/// should stop a submission is a domain rule this file does not decide (see
/// [SurveyCompletenessResult]).
class SurveyGap {
  const SurveyGap({required this.section, required this.detail});

  /// Matches the Site Hub tile the user needs to open, verbatim — so the
  /// warning names something they can actually go and tap, rather than an
  /// abstract field name.
  final String section;

  /// Why it counts as empty, in the user's terms ("nothing recorded yet").
  final String detail;

  String get description => '$section — $detail';
}

/// What [evaluateSurveyCompleteness] found.
///
/// Modelled on [BomGenerationResult] (see bom_engine.dart), which reports
/// Group A's unresolved points and lets the caller decide what to do about
/// them. Same split here: this computes the facts, the UI decides the
/// consequence.
class SurveyCompletenessResult {
  const SurveyCompletenessResult({required this.gaps});

  final List<SurveyGap> gaps;

  bool get isComplete => gaps.isEmpty;
}

/// Reports which survey sections are still completely empty.
///
/// Pure computation, no I/O — the caller supplies counts it has already
/// loaded (Site Hub has all of them in state before the Submit button is
/// even rendered), so this adds no queries to the submit path.
///
/// ## What this deliberately does NOT check
///
/// **Field-level completeness.** Every section form already blocks its own
/// save until its mandatory fields are filled (see e.g.
/// SourcePointFormScreen's `_save`, which refuses with "Please fill in the
/// required fields"). So a saved record already implies its own required
/// fields are present, and re-checking them here would duplicate a rule
/// that is enforced closer to the user.
///
/// **"Enough" records.** Site Hub's own `_countStatus` treats a section as
/// complete once its count reaches the number of blocks — a display
/// heuristic that has never been confirmed as a domain rule. It is
/// especially doubtful for gateways, since [Gateway.blocksCovered] is a
/// Set: one gateway explicitly covers many blocks, so "one per block" would
/// demand redundant hardware. This function therefore only reports sections
/// with *nothing at all* in them, which needs no such assumption. If the
/// real per-section rules are ever pinned down, they belong here — as
/// additional gaps, not as a rewrite of this one.
///
/// **A finalized BoM.** Finalizing has its own blocking safety net (Group
/// A unresolved points) and plausibly belongs after approval, not before
/// submission. Treating it as a submission prerequisite is a workflow
/// decision, not a data one.
SurveyCompletenessResult evaluateSurveyCompleteness({
  required Site site,
  required int sourcePointCount,
  required int inletPointCount,
  required int ductLoraCount,
  required int gatewayCount,
  required bool footerFilled,
}) {
  const nothingRecorded = 'nothing recorded yet';
  return SurveyCompletenessResult(
    gaps: [
      if (site.blocks.isEmpty)
        const SurveyGap(section: 'Blocks', detail: 'no blocks added'),
      if (site.clientInputs == null)
        const SurveyGap(section: 'Client inputs', detail: 'not filled in'),
      if (sourcePointCount == 0)
        const SurveyGap(section: 'Source points', detail: nothingRecorded),
      if (inletPointCount == 0)
        const SurveyGap(section: 'Inlet points', detail: nothingRecorded),
      if (ductLoraCount == 0)
        const SurveyGap(section: 'Duct LoRa', detail: nothingRecorded),
      if (gatewayCount == 0)
        const SurveyGap(section: 'Gateway', detail: nothingRecorded),
      if (!footerFilled)
        const SurveyGap(section: 'Footer', detail: 'not filled in'),
    ],
  );
}
