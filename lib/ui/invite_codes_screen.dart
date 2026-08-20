import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/signup_invite_data_source.dart';
import '../models/user_role.dart';
import 'widgets/load_error_view.dart';

/// Admin-only screen for issuing, reviewing and revoking signup invite codes.
///
/// Reachable only from the Admin overflow menu, but the gate that matters is
/// not this screen: `create_signup_invite` and `revoke_signup_invite` both
/// re-check `is_admin()` server-side and raise otherwise, and the table's
/// only policy grants SELECT to Admins alone. A non-Admin who reached this
/// screen would see an empty list and get an error on every action.
class InviteCodesScreen extends StatefulWidget {
  const InviteCodesScreen({super.key, this.invites});

  /// Injectable purely so a test can drive the screen without a live
  /// Supabase client; production always builds its own.
  final SignupInviteDataSource? invites;

  @override
  State<InviteCodesScreen> createState() => _InviteCodesScreenState();
}

class _InviteCodesScreenState extends State<InviteCodesScreen> {
  late final SignupInviteDataSource _invites =
      widget.invites ?? SignupInviteDataSource();

  List<SignupInvite> _codes = const [];
  bool _loading = true;
  Object? _loadError;

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
      final codes = await _invites.fetchInvites();
      if (!mounted) return;
      setState(() {
        _codes = codes;
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

  Future<void> _generate() async {
    final result = await showDialog<_NewInvite>(
      context: context,
      builder: (_) => const _GenerateInviteDialog(),
    );
    if (result == null || !mounted) return;

    try {
      final code = await _invites.createInvite(
        roleAllowed: result.role.name,
        expiresAt: result.expiresAt,
      );
      if (!mounted) return;
      await _showCode(code, result.role);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't create the code: $e")),
      );
    }
  }

  /// Shown once, immediately after generation, with copy-to-clipboard.
  ///
  /// The code stays readable in the list afterwards — it is not a secret from
  /// the Admin who issued it — but surfacing it here means the common case
  /// (generate, send to someone) never needs a second lookup.
  Future<void> _showCode(String code, UserRole role) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite code created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('For a ${role.name} account. Send this to the person '
                'signing up:'),
            const SizedBox(height: 12),
            SelectableText(
              _formatted(code),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'It can be used once, and only for that role.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(SignupInvite invite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke this code?'),
        content: Text(
          'The code ${_formatted(invite.code)} will stop working immediately. '
          'Anyone who already has it will not be able to sign up with it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _invites.revokeInvite(invite.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't revoke the code: $e")),
      );
    }
  }

  /// Grouped into fives purely for reading aloud and typing — the stored and
  /// transmitted value has no separators, and the validation RPC strips any
  /// the user adds anyway.
  static String _formatted(String code) {
    final out = StringBuffer();
    for (var i = 0; i < code.length; i++) {
      if (i > 0 && i % 5 == 0) out.write('-');
      out.write(code[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite codes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generate,
        icon: const Icon(Icons.add),
        label: const Text('New code'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? LoadErrorView(onRetry: _load, details: _loadError)
              : _codes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No invite codes yet.\n\n'
                          'Create one to let someone request an account.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _codes.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _tile(_codes[i]),
                      ),
                    ),
    );
  }

  Widget _tile(SignupInvite invite) {
    final reason = invite.inactiveReason;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(
        _formatted(invite.code),
        style: TextStyle(
          fontFamily: 'monospace',
          decoration: reason == null ? null : TextDecoration.lineThrough,
          color: reason == null ? null : scheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        '${invite.roleAllowed} · '
        '${reason ?? _remaining(invite)}'
        '${invite.expiresAt == null ? '' : ' · expires ${_date(invite.expiresAt!)}'}',
      ),
      trailing: invite.isUsable
          ? TextButton(
              onPressed: () => _revoke(invite),
              child: const Text('Revoke'),
            )
          : null,
    );
  }

  static String _remaining(SignupInvite i) =>
      i.maxUses == 1 ? 'unused' : '${i.uses}/${i.maxUses} used';

  static String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }
}

class _NewInvite {
  const _NewInvite(this.role, this.expiresAt);
  final UserRole role;
  final DateTime? expiresAt;
}

class _GenerateInviteDialog extends StatefulWidget {
  const _GenerateInviteDialog();

  @override
  State<_GenerateInviteDialog> createState() => _GenerateInviteDialogState();
}

class _GenerateInviteDialogState extends State<_GenerateInviteDialog> {
  UserRole _role = UserRole.engineer;
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New invite code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Role this code may be used for'),
          const SizedBox(height: 8),
          DropdownButtonFormField<UserRole>(
            initialValue: _role,
            items: [
              for (final r in UserRole.values)
                DropdownMenuItem(value: r, child: Text(r.name)),
            ],
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 20),
          const Text('Expires after'),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _days,
            items: const [
              DropdownMenuItem(value: 1, child: Text('1 day')),
              DropdownMenuItem(value: 7, child: Text('7 days')),
              DropdownMenuItem(value: 30, child: Text('30 days')),
              DropdownMenuItem(value: 0, child: Text('No expiry')),
            ],
            onChanged: (v) => setState(() => _days = v ?? _days),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _NewInvite(
              _role,
              _days == 0 ? null : DateTime.now().add(Duration(days: _days)),
            ),
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
