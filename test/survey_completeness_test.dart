// Pure-logic tests for the survey completeness check behind the
// submit-time warning (Issue 2).
//
// The warning is deliberately advisory, not a block — see
// evaluateSurveyCompleteness's doc for why the per-section "how many is
// enough" rules are not encoded here. These tests pin down the part that IS
// settled: a section with nothing in it gets named, and a section with
// something in it does not.

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/models/client_inputs.dart';
import 'package:survey_app/models/site.dart';
import 'package:survey_app/services/survey_completeness.dart';

Site _site({List<String> blocks = const ['A'], bool withClientInputs = true}) =>
    Site(
      id: 's1',
      name: 'Test Site',
      blocks: blocks,
      clientInputs: withClientInputs ? const ClientInputs() : null,
    );

SurveyCompletenessResult _evaluate({
  Site? site,
  int sourcePoints = 1,
  int inletPoints = 1,
  int ductLoras = 1,
  int gateways = 1,
  bool footerFilled = true,
}) => evaluateSurveyCompleteness(
  site: site ?? _site(),
  sourcePointCount: sourcePoints,
  inletPointCount: inletPoints,
  ductLoraCount: ductLoras,
  gatewayCount: gateways,
  footerFilled: footerFilled,
);

void main() {
  test('a fully populated survey reports no gaps', () {
    final result = _evaluate();
    expect(result.isComplete, isTrue);
    expect(result.gaps, isEmpty);
  });

  test('an entirely empty survey names every section', () {
    final result = _evaluate(
      site: _site(blocks: const [], withClientInputs: false),
      sourcePoints: 0,
      inletPoints: 0,
      ductLoras: 0,
      gateways: 0,
      footerFilled: false,
    );

    expect(result.isComplete, isFalse);
    expect(
      result.gaps.map((g) => g.section),
      containsAll(<String>[
        'Blocks',
        'Client inputs',
        'Source points',
        'Inlet points',
        'Duct LoRa',
        'Gateway',
        'Footer',
      ]),
    );
  });

  test('each section is reported independently', () {
    expect(_evaluate(sourcePoints: 0).gaps.single.section, 'Source points');
    expect(_evaluate(inletPoints: 0).gaps.single.section, 'Inlet points');
    expect(_evaluate(ductLoras: 0).gaps.single.section, 'Duct LoRa');
    expect(_evaluate(gateways: 0).gaps.single.section, 'Gateway');
    expect(_evaluate(footerFilled: false).gaps.single.section, 'Footer');
    expect(
      _evaluate(site: _site(blocks: const [])).gaps.single.section,
      'Blocks',
    );
    expect(
      _evaluate(site: _site(withClientInputs: false)).gaps.single.section,
      'Client inputs',
    );
  });

  test(
    'a single record is enough — the unverified one-per-block heuristic is '
    'deliberately NOT applied, so a 5-block site with one source point is '
    'not flagged',
    () {
      final result = _evaluate(
        site: _site(blocks: const ['A', 'B', 'C', 'D', 'E']),
        sourcePoints: 1,
        inletPoints: 1,
        ductLoras: 1,
        gateways: 1,
      );
      expect(result.isComplete, isTrue);
    },
  );

  test(
    'one gateway covering several blocks is not flagged — Gateway.'
    'blocksCovered is a Set, so one-per-block would demand redundant hardware',
    () {
      final result = _evaluate(
        site: _site(blocks: const ['A', 'B', 'C']),
        gateways: 1,
      );
      expect(result.gaps.where((g) => g.section == 'Gateway'), isEmpty);
    },
  );

  test('gap descriptions name the Site Hub tile the user has to open', () {
    final gap = _evaluate(sourcePoints: 0).gaps.single;
    expect(gap.description, 'Source points — nothing recorded yet');
  });
}
