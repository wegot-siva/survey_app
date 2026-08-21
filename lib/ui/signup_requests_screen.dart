import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/signup_review_data_source.dart';
import 'theme/app_theme.dart';
import 'widgets/load_error_view.dart';

/// The signup review queue — approve or reject requests for an account.
///
/// Reachable from the overflow menu for Admin and Approver. As everywhere
/// else in this flow, the menu gate is convenience and not the control: the
/// table's only SELECT policy is `is_signup_reviewer()`, and both actions go
/// through an Edge Function that re-derives the caller's role from `profiles`
/// server-side. Somebody who reached this screen without the role would see
/// an empty list and get a refusal on every action.
///
/// The role an approval grants is chosen HERE, by the approver. The
/// applicant's `requested_role` is only the default — it came from their
/// invite code and confers nothing on its own.
class SignupRequestsScreen extends StatefulWidget {
  const SignupRequestsScreen({super.key, this.review});

  /// Injectable purely so a test can drive the screen without a live
  /// Supabase client; production always builds its own.
  final SignupReviewDataSource? review;

  @override
  State<SignupRequestsScreen> createState() => _SignupRequestsScreenState();
}

class _SignupRequestsScreenState extends State<SignupRequestsScreen> {
  late final SignupReviewDataSource _review =
      widget.review ?? SignupReviewDataSource();

  List<SignupRequest> _pending = const [];
  List<SignupRequest> _reviewed = const [];

  /// profiles id -> reviewer name. Partial by design for an Approver, who
  /// cannot read an Admin's profile row — see
  /// [SignupReviewDataSource.reviewerNames].
  Map<String, String> _reviewers = const {};

  /// null = show everything reviewed; otherwise 'approved' or 'rejected'.
  String? _historyFilter;

  /// What this reviewer may grant. An Approver gets sales/engineer; an Admin
  /// gets all four. Empty until loaded, which is why the approve dialog waits
  /// for it rather than guessing.
  List<String> _grantable = const [];

  bool _loading = true;
  Object? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _review.fetchPending(),
        _review.fetchReviewed(),
        _review.grantableRoles(),
      ]);
      final pending = results[0] as List<SignupRequest>;
      final reviewed = results[1] as List<SignupRequest>;
      final reviewers = await _review.reviewerNames(
        reviewed.map((r) => r.reviewedBy).whereType<String>(),
      );
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _reviewed = reviewed;
        _reviewers = reviewers;
        _grantable = results[2] as List<String>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _approve(SignupRequest request) async {
    final role = await showDialog<String>(
      context: context,
      builder: (_) => _ApproveDialog(request: request, grantable: _grantable),
    );
    if (role == null || !mounted) return;

    setState(() => _busy = true);
    final outcome =
        await _review.approve(requestId: request.id, grantedRole: role);
    if (!mounted) return;
    setState(() => _busy = false);

    if (outcome.ok) {
      await _showApproved(request, role, outcome);
    } else {
      await _showFailure(outcome);
    }
    await _load();
  }

  Future<void> _reject(SignupRequest request) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectDialog(request: request),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    final outcome = await _review.reject(
      requestId: request.id,
      reason: reason.isEmpty ? null : reason,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (!outcome.ok) await _showFailure(outcome);
    await _load();
  }

  /// The account exists by the time this shows. If a link came back, it is
  /// the only copy — GoTrue keeps a single recovery token per user, so
  /// generating another one invalidates this one.
  Future<void> _showApproved(
    SignupRequest request,
    String role,
    ReviewOutcome outcome,
  ) async {
    final link = outcome.actionLink;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approved'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${request.fullName} now has a $role account.'),
            const SizedBox(height: AppSpacing.md),
            if (link != null) ...[
              const Text(
                'Send them this link so they can set a password. It is shown '
                'once — generating another one cancels this.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(
                link,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ] else if (outcome.delivery == 'emailed')
              Text("We've emailed ${request.email} a link to set a password.")
            else
              Text(
                'The account is ready, but the password link could not be '
                'issued (${outcome.delivery ?? 'unknown'}). Ask them to use '
                '"Forgot password" on the sign-in screen.',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        actions: [
          if (link != null)
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Copy link'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFailure(ReviewOutcome outcome) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(outcome.reason == 'already_reviewed'
            ? 'Already reviewed'
            : "Couldn't complete that"),
        content: Text(outcome.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Account requests'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Pending (${_pending.length})'),
              const Tab(text: 'Reviewed'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? LoadErrorView(onRetry: _load, details: _loadError)
                : Stack(
                    children: [
                      TabBarView(
                        children: [
                          _pendingList(),
                          _reviewedList(),
                        ],
                      ),
                      if (_busy)
                        const ColoredBox(
                          color: Color(0x33000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _pendingList() {
    if (_pending.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nothing waiting for review.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _pending.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final r = _pending[i];
          return ListTile(
            isThreeLine: true,
            title: Text(r.fullName),
            subtitle: Text(
              '${r.email}\nasked for ${r.requestedRole} · '
              '${_date(r.createdAt)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _reject(r),
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _approve(r),
                  child: const Text('Approve'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The audit trail: every request that has been dealt with, who dealt with
  /// it, when, and — for rejections — why.
  ///
  /// Two things it deliberately does NOT claim to show, because the database
  /// does not store them (see [SignupReviewDataSource]'s class comment): the
  /// role actually GRANTED, which can differ from the role requested, and any
  /// link to the account that was created. The tile says "asked for X" rather
  /// than "granted X" so nobody mistakes one for the other.
  Widget _reviewedList() {
    if (_reviewed.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Nothing reviewed yet.', textAlign: TextAlign.center),
        ),
      );
    }
    final visible = _historyFilter == null
        ? _reviewed
        : _reviewed.where((r) => r.status == _historyFilter).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final f in <(String, String?)>[
                ('All (${_reviewed.length})', null),
                ('Approved (${_reviewed.where((r) => r.isApproved).length})',
                    'approved'),
                ('Rejected (${_reviewed.where((r) => r.isRejected).length})',
                    'rejected'),
              ]) ...[
                ChoiceChip(
                  label: Text(f.$1),
                  selected: _historyFilter == f.$2,
                  onSelected: (_) => setState(() => _historyFilter = f.$2),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Nothing here.', textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _historyTile(visible[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _historyTile(SignupRequest r) {
    final scheme = Theme.of(context).colorScheme;
    final approved = r.isApproved;
    return ListTile(
      isThreeLine: true,
      leading: Icon(
        approved ? Icons.check_circle_outline : Icons.block,
        color: approved ? scheme.primary : scheme.error,
      ),
      title: Text(r.fullName),
      subtitle: Text(
        '${r.email}\n'
        '${approved ? 'Approved' : 'Rejected'} by ${_reviewerLabel(r)}'
        '${r.reviewedAt == null ? '' : ' on ${_date(r.reviewedAt!)}'}\n'
        'asked for ${r.requestedRole} · code ${r.inviteCodeUsed} · '
        'applied ${_date(r.createdAt)}'
        '${r.rejectionReason == null ? '' : '\nReason: ${r.rejectionReason}'}',
      ),
    );
  }

  /// The reviewer's name, or their raw id when RLS did not return a profile
  /// for it — which is the normal case for an Approver looking at something
  /// an Admin reviewed. Never silently blank: who reviewed it is the whole
  /// point of the record.
  String _reviewerLabel(SignupRequest r) {
    final id = r.reviewedBy;
    if (id == null) return 'an unrecorded reviewer';
    final name = _reviewers[id];
    if (name == null || name.isEmpty) return id;
    return name;
  }

  static String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }
}

/// Asks which role to grant.
///
/// Only offers what the server said this reviewer may grant, so an Approver
/// is never shown "admin" as a choice. If the requested role is not among
/// them the dialog says so and refuses to approve at all, rather than
/// quietly downgrading the applicant to something they did not ask for.
class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.request, required this.grantable});

  final SignupRequest request;
  final List<String> grantable;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  late String? _role = widget.grantable.contains(widget.request.requestedRole)
      ? widget.request.requestedRole
      : null;

  bool get _blocked => !widget.grantable.contains(widget.request.requestedRole);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.request.fullName} · ${widget.request.email}'),
          const SizedBox(height: AppSpacing.md),
          if (_blocked)
            Text(
              'This request asks for a ${widget.request.requestedRole} '
              'account, which your role cannot grant. An Admin has to '
              'approve it.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else ...[
            const Text('Role to grant'),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _role,
              items: [
                for (final r in widget.grantable)
                  DropdownMenuItem(value: r, child: Text(r)),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'They asked for ${widget.request.requestedRole}. You can grant '
              'something different — the request does not decide this.',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _blocked || _role == null
              ? null
              : () => Navigator.of(context).pop(_role),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

/// Asks for an optional reason. Returns '' for "reject with no reason" and
/// null for "cancelled" — the two must stay distinguishable.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.request});

  final SignupRequest request;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.request.fullName} · ${widget.request.email}'),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'No account is created, and their invite code is not used up — '
            'it can still be given to somebody else.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason (optional, for your records)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
