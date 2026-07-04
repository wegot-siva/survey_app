// Contract tests for the Finalize flow's storage, exercised through the
// in-memory repository: finalizing writes one snapshot + its frozen lines,
// a second finalize is a no-op (idempotent, no revisions in this slice), and
// the site's bomLocked flag flips. Immutability against later Material
// Master / bom_manual_entries edits is a UI-assembly property (the caller
// copies values in before calling finalizeBom), not something this
// repository layer can violate, since snapshot lines never reference either
// source table.

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/models/bom_snapshot_line.dart';
import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  late InMemorySurveyRepository repo;

  setUp(() => repo = InMemorySurveyRepository(IdService()));

  List<BomSnapshotLine> draftLines() => const [
    BomSnapshotLine(
      id: '',
      snapshotId: '',
      sku: 'SEN-1',
      item: 'WEGOTAqua Sensor (DN25 · Wired)',
      unit: 'pcs',
      qty: 4,
      group: MaterialGroup.a,
      source: BomSnapshotSource.auto,
    ),
    BomSnapshotLine(
      id: '',
      snapshotId: '',
      sku: 'RWK-1',
      item: 'Extra rework kit',
      unit: 'set',
      qty: 2,
      group: MaterialGroup.d,
      source: BomSnapshotSource.manual,
    ),
  ];

  test('no snapshot exists before finalize', () async {
    final site = await repo.createSite(name: 'Site A');
    expect(await repo.getBomSnapshot(site.id), isNull);
    expect(site.bomLocked, isFalse);
  });

  test('finalize writes one snapshot and its frozen lines', () async {
    final site = await repo.createSite(name: 'Site A');

    final snapshot = await repo.finalizeBom(
      surveyId: site.id,
      lines: draftLines(),
      finalizedBy: 'Engineer',
    );

    expect(snapshot.id, isNotEmpty);
    expect(snapshot.surveyId, site.id);
    expect(snapshot.version, 1);
    expect(snapshot.status, 'final');
    expect(snapshot.finalizedBy, 'Engineer');

    final stored = await repo.getBomSnapshot(site.id);
    expect(stored, isNotNull);
    expect(stored!.id, snapshot.id);

    final lines = await repo.getBomSnapshotLines(snapshot.id);
    expect(lines, hasLength(2));
    expect(lines.every((l) => l.id.isNotEmpty), isTrue);
    expect(lines.every((l) => l.snapshotId == snapshot.id), isTrue);
    expect(
      lines.map((l) => l.item),
      containsAll(['WEGOTAqua Sensor (DN25 · Wired)', 'Extra rework kit']),
    );
    expect(
      lines.firstWhere((l) => l.group == MaterialGroup.a).source,
      BomSnapshotSource.auto,
    );
    expect(
      lines.firstWhere((l) => l.group == MaterialGroup.d).source,
      BomSnapshotSource.manual,
    );
  });

  test('finalize locks the site', () async {
    final site = await repo.createSite(name: 'Site A');
    await repo.finalizeBom(
      surveyId: site.id,
      lines: draftLines(),
      finalizedBy: 'Engineer',
    );

    final locked = await repo.getSiteById(site.id);
    expect(locked!.bomLocked, isTrue);
  });

  test('finalizing twice is a no-op — returns the existing snapshot', () async {
    final site = await repo.createSite(name: 'Site A');
    final first = await repo.finalizeBom(
      surveyId: site.id,
      lines: draftLines(),
      finalizedBy: 'Engineer',
    );
    final second = await repo.finalizeBom(
      surveyId: site.id,
      lines: const [],
      finalizedBy: 'Approver',
    );

    expect(second.id, first.id);
    expect(second.finalizedBy, 'Engineer'); // unchanged, not overwritten
    expect(await repo.getBomSnapshotLines(first.id), hasLength(2));
  });

  test('snapshots are scoped per survey', () async {
    final siteA = await repo.createSite(name: 'Site A');
    final siteB = await repo.createSite(name: 'Site B');
    await repo.finalizeBom(
      surveyId: siteA.id,
      lines: draftLines(),
      finalizedBy: 'Engineer',
    );

    expect(await repo.getBomSnapshot(siteA.id), isNotNull);
    expect(await repo.getBomSnapshot(siteB.id), isNull);
  });
}
