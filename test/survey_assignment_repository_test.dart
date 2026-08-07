// Contract tests for reassignment, exercised through the in-memory
// repository: reassignSurvey must write one audit row recording old/new
// assignee (both the real account id and its display-name snapshot — Slice
// 1c), and must leave other surveys' status/assignment untouched.
//
// Reassignment is deliberately allowed in EVERY status, including after the
// engineer has started work. The old 'assigned'-only rule read to users as an
// arbitrary reassignment limit (the button vanished the moment the engineer
// opened the survey), so the handover risk is now surfaced as a UI warning
// rather than a hard block — see SurveyRepository's reassignment doc.

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/models/survey_status.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  late InMemorySurveyRepository repo;

  setUp(() => repo = InMemorySurveyRepository(IdService()));

  test('reassigning an assigned survey updates assignedTo/assignedToUserId and logs one entry',
      () async {
    final site = await repo.createSite(name: 'Site A', blocks: const []);
    await repo.updateSite(
      site.copyWith(
        assignedTo: 'Ravi Kumar',
        assignedToUserId: 'eng-ravi',
        status: SurveyStatus.assigned,
      ),
    );

    await repo.reassignSurvey(
      siteId: site.id,
      newAssigneeUserId: 'eng-priya',
      newAssignee: 'Priya Sharma',
      changedByRole: 'Sales',
    );

    final updated = await repo.getSiteById(site.id);
    expect(updated!.assignedTo, 'Priya Sharma');
    expect(updated.assignedToUserId, 'eng-priya');

    final log = await repo.getSurveyAssignmentAuditLog(site.id);
    expect(log, hasLength(1));
    expect(log.single.oldAssignee, 'Ravi Kumar');
    expect(log.single.oldAssigneeUserId, 'eng-ravi');
    expect(log.single.newAssignee, 'Priya Sharma');
    expect(log.single.newAssigneeUserId, 'eng-priya');
    expect(log.single.changedByRole, 'Sales');
    expect(log.single.siteId, site.id);
  });

  // The core of the "reassignment limit" fix: every one of these used to
  // throw, which is what made reassignment look capped after an engineer
  // opened the survey.
  for (final status in [
    SurveyStatus.inProgress,
    SurveyStatus.submitted,
    SurveyStatus.approved,
  ]) {
    test('a survey already in "$status" can still be reassigned', () async {
      final site = await repo.createSite(name: 'Site $status');
      await repo.updateSite(
        site.copyWith(
          assignedTo: 'Ravi Kumar',
          assignedToUserId: 'eng-ravi',
          status: status,
        ),
      );

      await repo.reassignSurvey(
        siteId: site.id,
        newAssigneeUserId: 'eng-priya',
        newAssignee: 'Priya Sharma',
        changedByRole: 'Sales',
      );

      final updated = await repo.getSiteById(site.id);
      expect(updated!.assignedTo, 'Priya Sharma');
      expect(updated.assignedToUserId, 'eng-priya');
      // Reassigning is a handover, not a workflow reset — the survey keeps
      // whatever progress it had.
      expect(updated.status, status);
      expect(await repo.getSurveyAssignmentAuditLog(site.id), hasLength(1));
    });
  }

  test('a survey with no status set can be reassigned', () async {
    final site = await repo.createSite(name: 'Site C');
    // Never assigned at all — status is null.

    await repo.reassignSurvey(
      siteId: site.id,
      newAssigneeUserId: 'eng-priya',
      newAssignee: 'Priya Sharma',
      changedByRole: 'Sales',
    );

    final updated = await repo.getSiteById(site.id);
    expect(updated!.assignedToUserId, 'eng-priya');
  });

  test('an in-progress survey can be reassigned repeatedly — there is no '
      'cap on how many times a survey changes hands', () async {
    final site = await repo.createSite(name: 'Site D');
    await repo.updateSite(
      site.copyWith(
        assignedTo: 'Engineer 0',
        assignedToUserId: 'eng-0',
        status: SurveyStatus.inProgress,
      ),
    );

    for (var i = 1; i <= 6; i++) {
      await repo.reassignSurvey(
        siteId: site.id,
        newAssigneeUserId: 'eng-$i',
        newAssignee: 'Engineer $i',
        changedByRole: 'Sales',
      );
    }

    final updated = await repo.getSiteById(site.id);
    expect(updated!.assignedToUserId, 'eng-6');
    expect(await repo.getSurveyAssignmentAuditLog(site.id), hasLength(6));
  });

  test('reassignment log is scoped per survey and ordered newest first',
      () async {
    final a = await repo.createSite(name: 'Site A', blocks: const []);
    await repo.updateSite(
      a.copyWith(
        assignedTo: 'Ravi Kumar',
        assignedToUserId: 'eng-ravi',
        status: SurveyStatus.assigned,
      ),
    );
    final b = await repo.createSite(name: 'Site B', blocks: const []);
    await repo.updateSite(
      b.copyWith(
        assignedTo: 'Arjun Mehta',
        assignedToUserId: 'eng-arjun',
        status: SurveyStatus.assigned,
      ),
    );

    await repo.reassignSurvey(
      siteId: a.id,
      newAssigneeUserId: 'eng-priya',
      newAssignee: 'Priya Sharma',
      changedByRole: 'Sales',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repo.reassignSurvey(
      siteId: a.id,
      newAssigneeUserId: 'eng-sneha',
      newAssignee: 'Sneha Iyer',
      changedByRole: 'Sales',
    );

    final logA = await repo.getSurveyAssignmentAuditLog(a.id);
    expect(logA, hasLength(2));
    expect(logA.first.newAssignee, 'Sneha Iyer'); // newest first
    expect(logA.last.newAssignee, 'Priya Sharma');

    // Site B's log is untouched by A's reassignments.
    expect(await repo.getSurveyAssignmentAuditLog(b.id), isEmpty);
    final unchangedB = await repo.getSiteById(b.id);
    expect(unchangedB!.assignedTo, 'Arjun Mehta');
  });

  test('reassigning a nonexistent site throws', () async {
    await expectLater(
      () => repo.reassignSurvey(
        siteId: 'does-not-exist',
        newAssigneeUserId: 'eng-priya',
        newAssignee: 'Priya Sharma',
        changedByRole: 'Sales',
      ),
      throwsStateError,
    );
  });
}
