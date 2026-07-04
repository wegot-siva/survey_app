// Contract tests for BoM revisions (v2+), exercised through the in-memory
// repository: versioning starts at 2 and increments per survey, a revision's
// lines get ids assigned, revisions are scoped per survey, and — critically —
// adding a revision never touches the survey's existing v1 snapshot or its
// frozen lines (immutability holds even once revisions exist).

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/models/bom_revision_line.dart';
import 'package:survey_app/models/bom_snapshot_line.dart';
import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  late InMemorySurveyRepository repo;

  setUp(() => repo = InMemorySurveyRepository(IdService()));

  List<BomSnapshotLine> v1Lines() => const [
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
  ];

  List<BomRevisionLine> draftLines({double qtyDelta = 2}) => [
    BomRevisionLine(
      id: '',
      revisionId: '',
      sku: 'RWK-1',
      item: 'Extra rework kit',
      unit: 'set',
      qtyDelta: qtyDelta,
      group: MaterialGroup.d,
    ),
  ];

  test('no revisions exist before any are added', () async {
    final site = await repo.createSite(name: 'Site A');
    expect(await repo.getBomRevisions(site.id), isEmpty);
  });

  test('first revision on a survey is version 2', () async {
    final site = await repo.createSite(name: 'Site A');
    await repo.finalizeBom(
      surveyId: site.id,
      lines: v1Lines(),
      finalizedBy: 'Engineer',
    );

    final revision = await repo.addBomRevision(
      surveyId: site.id,
      reason: 'wall broken, extra elbows',
      lines: draftLines(),
      createdBy: 'Engineer',
    );

    expect(revision.version, 2);
    expect(revision.id, isNotEmpty);
    expect(revision.reason, 'wall broken, extra elbows');
  });

  test('revision lines get ids and revisionId assigned', () async {
    final site = await repo.createSite(name: 'Site A');
    await repo.finalizeBom(
      surveyId: site.id,
      lines: v1Lines(),
      finalizedBy: 'Engineer',
    );
    final revision = await repo.addBomRevision(
      surveyId: site.id,
      reason: 'wall broken',
      lines: draftLines(),
      createdBy: 'Engineer',
    );

    final lines = await repo.getBomRevisionLines(revision.id);
    expect(lines, hasLength(1));
    expect(lines.single.id, isNotEmpty);
    expect(lines.single.revisionId, revision.id);
    expect(lines.single.qtyDelta, 2);
  });

  test('versions increment per survey: v2, v3, v4', () async {
    final site = await repo.createSite(name: 'Site A');
    await repo.finalizeBom(
      surveyId: site.id,
      lines: v1Lines(),
      finalizedBy: 'Engineer',
    );

    final r2 = await repo.addBomRevision(
      surveyId: site.id,
      reason: 'first change',
      lines: draftLines(),
      createdBy: 'Engineer',
    );
    final r3 = await repo.addBomRevision(
      surveyId: site.id,
      reason: 'second change',
      lines: draftLines(qtyDelta: -1),
      createdBy: 'Approver',
    );

    expect(r2.version, 2);
    expect(r3.version, 3);

    final all = await repo.getBomRevisions(site.id);
    expect(all.map((r) => r.version).toList(), [2, 3]);
    expect(all.map((r) => r.reason).toList(), [
      'first change',
      'second change',
    ]);
  });

  test('revisions are scoped per survey', () async {
    final siteA = await repo.createSite(name: 'Site A');
    final siteB = await repo.createSite(name: 'Site B');
    await repo.finalizeBom(
      surveyId: siteA.id,
      lines: v1Lines(),
      finalizedBy: 'Engineer',
    );
    await repo.finalizeBom(
      surveyId: siteB.id,
      lines: v1Lines(),
      finalizedBy: 'Engineer',
    );

    await repo.addBomRevision(
      surveyId: siteA.id,
      reason: 'A only',
      lines: draftLines(),
      createdBy: 'Engineer',
    );

    expect(await repo.getBomRevisions(siteA.id), hasLength(1));
    expect(await repo.getBomRevisions(siteB.id), isEmpty);
  });

  test('adding a revision does not alter the existing v1 snapshot', () async {
    final site = await repo.createSite(name: 'Site A');
    final snapshot = await repo.finalizeBom(
      surveyId: site.id,
      lines: v1Lines(),
      finalizedBy: 'Engineer',
    );
    final originalLines = await repo.getBomSnapshotLines(snapshot.id);

    await repo.addBomRevision(
      surveyId: site.id,
      reason: 'wall broken',
      lines: draftLines(),
      createdBy: 'Engineer',
    );

    final snapshotAfter = await repo.getBomSnapshot(site.id);
    final linesAfter = await repo.getBomSnapshotLines(snapshot.id);
    expect(snapshotAfter!.id, snapshot.id);
    expect(snapshotAfter.finalizedBy, snapshot.finalizedBy);
    expect(linesAfter.length, originalLines.length);
    expect(linesAfter.single.qty, originalLines.single.qty);
    expect(linesAfter.single.item, originalLines.single.item);
  });
}
