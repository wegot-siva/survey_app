// Contract tests for the polymorphic photo store (photo slice 2), exercised
// through the in-memory repository: setPhotos must insert new rows, keep/update
// existing ones by id, and delete those dropped from the submitted set —
// scoped to a single (ownerType, ownerId).

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/models/survey_photo.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  late InMemorySurveyRepository repo;

  setUp(() => repo = InMemorySurveyRepository(IdService()));

  test('setPhotos inserts new photos and assigns ids', () async {
    await repo.setPhotos(PhotoOwner.gateway, 'g1', [
      const SurveyPhoto(
        id: '',
        ownerType: PhotoOwner.gateway,
        ownerId: 'g1',
        slot: PhotoSlot.gatewayLocation,
        localPath: '/tmp/a.jpg',
      ),
    ]);

    final stored = await repo.getPhotos(PhotoOwner.gateway, 'g1');
    expect(stored, hasLength(1));
    expect(stored.single.id, isNotEmpty);
    expect(stored.single.localPath, '/tmp/a.jpg');
    expect(stored.single.remotePath, isNull);
  });

  test('setPhotos updates an existing photo by id without re-inserting',
      () async {
    await repo.setPhotos(PhotoOwner.sourcePoint, 's1', [
      const SurveyPhoto(
        id: '',
        ownerType: PhotoOwner.sourcePoint,
        ownerId: 's1',
        slot: PhotoSlot.inletMarked,
        localPath: '/tmp/a.jpg',
      ),
    ]);
    final first = (await repo.getPhotos(PhotoOwner.sourcePoint, 's1')).single;

    // Resubmit the same id with a remote path recorded (e.g. after upload).
    await repo.setPhotos(PhotoOwner.sourcePoint, 's1', [
      SurveyPhoto(
        id: first.id,
        ownerType: PhotoOwner.sourcePoint,
        ownerId: 's1',
        slot: PhotoSlot.inletMarked,
        localPath: '/tmp/a.jpg',
        remotePath: 'photos/${first.id}.jpg',
      ),
    ]);

    final after = await repo.getPhotos(PhotoOwner.sourcePoint, 's1');
    expect(after, hasLength(1));
    expect(after.single.id, first.id);
    expect(after.single.remotePath, 'photos/${first.id}.jpg');
  });

  test('setPhotos deletes photos dropped from the submitted set', () async {
    await repo.setPhotos(PhotoOwner.footer, 'site1', [
      const SurveyPhoto(
        id: '',
        ownerType: PhotoOwner.footer,
        ownerId: 'site1',
        slot: PhotoSlot.siteMedia,
        position: 0,
        localPath: '/tmp/a.jpg',
      ),
      const SurveyPhoto(
        id: '',
        ownerType: PhotoOwner.footer,
        ownerId: 'site1',
        slot: PhotoSlot.siteMedia,
        position: 1,
        localPath: '/tmp/b.jpg',
      ),
    ]);
    final two = await repo.getPhotos(PhotoOwner.footer, 'site1');
    expect(two, hasLength(2));

    // Keep only the first; the second should be deleted.
    await repo.setPhotos(PhotoOwner.footer, 'site1', [
      two.first,
    ]);

    final remaining = await repo.getPhotos(PhotoOwner.footer, 'site1');
    expect(remaining, hasLength(1));
    expect(remaining.single.id, two.first.id);
  });

  test('setPhotos only touches the given owner', () async {
    await repo.setPhotos(PhotoOwner.gateway, 'g1', [
      const SurveyPhoto(
        id: '',
        ownerType: PhotoOwner.gateway,
        ownerId: 'g1',
        slot: PhotoSlot.gatewayLocation,
        localPath: '/tmp/g1.jpg',
      ),
    ]);
    await repo.setPhotos(PhotoOwner.gateway, 'g2', [
      const SurveyPhoto(
        id: '',
        ownerType: PhotoOwner.gateway,
        ownerId: 'g2',
        slot: PhotoSlot.gatewayLocation,
        localPath: '/tmp/g2.jpg',
      ),
    ]);

    // Clearing g2 must leave g1 intact.
    await repo.setPhotos(PhotoOwner.gateway, 'g2', const []);

    expect(await repo.getPhotos(PhotoOwner.gateway, 'g1'), hasLength(1));
    expect(await repo.getPhotos(PhotoOwner.gateway, 'g2'), isEmpty);
  });

  test('getAllPhotos returns photos across every owner', () async {
    await repo.setPhotos(PhotoOwner.gateway, 'g1', [
      const SurveyPhoto(
        id: '',
        ownerType: PhotoOwner.gateway,
        ownerId: 'g1',
        slot: PhotoSlot.gatewayLocation,
        localPath: '/tmp/g1.jpg',
      ),
    ]);
    await repo.setPhotos(PhotoOwner.inletPoint, 'i1', [
      const SurveyPhoto(
        id: '',
        ownerType: PhotoOwner.inletPoint,
        ownerId: 'i1',
        slot: PhotoSlot.shaftAccess,
        localPath: '/tmp/i1.jpg',
      ),
    ]);

    expect(await repo.getAllPhotos(), hasLength(2));
  });
}
