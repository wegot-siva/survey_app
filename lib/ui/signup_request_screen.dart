import 'package:flutter/material.dart';

import '../data/signup_request_data_source.dart';
import 'theme/app_theme.dart';

/// Requests an account. Reached from the login screen; needs no session.
///
/// Collects name, email and an invite code — **no password**. The account is
/// created only when an Admin or Approver approves the request, and the
/// applicant sets their own password from the invite link they receive then.
/// So there is no password field, no confirm-password, and no strength meter
/// on the one screen an untrained field engineer meets first.
///
/// The role is not chosen freely: it is whatever the invite code permits, and
/// is shown once the code is recognised. A request never grants anything —
/// approval does.
class SignupRequestScreen extends StatefulWidget {
  const SignupRequestScreen({super.key, this.requests});

  /// Injectable for tests; production builds its own.
  final SignupRequestDataSource? requests;

  @override
  State<SignupRequestScreen> createState() => _SignupRequestScreenState();
}

class _SignupRequestScreenState extends State<SignupRequestScreen> {
  late final SignupRequestDataSource _requests =
      widget.requests ?? SignupRequestDataSource();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// The role the entered code permits, once it has been recognised. Null
  /// while unknown — which covers "not typed yet" and "not a usable code"
  /// alike, because those must not be distinguishable.
  String? _role;
  bool _checkingCode = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _code.removeListener(_onCodeChanged);
    _name.dispose();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Codes are 20 characters; anything shorter cannot be one, so the lookup
  /// waits rather than firing a request per keystroke.
  void _onCodeChanged() {
    final raw = _code.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (raw.length < 20) {
      if (_role != null) setState(() => _role = null);
      return;
    }
    _lookupRole();
  }

  Future<void> _lookupRole() async {
    if (_checkingCode) return;
    setState(() => _checkingCode = true);
    try {
      final role = await _requests.roleForCode(_code.text);
      if (!mounted) return;
      setState(() {
        _role = role;
        _checkingCode = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Network failure looks the same as an unusable code on purpose.
      setState(() {
        _role = null;
        _checkingCode = false;
      });
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final role = _role;

    setState(() => _error = null);

    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Enter your name and email.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (role == null) {
      // Deliberately not "that code is invalid/expired/used" — the client is
      // never told which, and the server would not tell it anyway.
      setState(() => _error = "That invite code can't be used.");
      return;
    }

    setState(() => _submitting = true);
    try {
      final ok = await _requests.submit(
        fullName: name,
        email: email,
        requestedRole: role,
        inviteCode: _code.text,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      if (ok) {
        await _showSubmitted();
      } else {
        setState(() => _error = "That invite code can't be used.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't send your request. Check your connection and "
            'try again.';
      });
    }
  }

  /// Worded to be true whether a row was written or the email already had an
  /// account — the server does not say which, and neither does this.
  Future<void> _showSubmitted() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Request sent'),
        content: const Text(
          'Your request is waiting for review.\n\n'
          "You'll get an email with a link to set your password once it's "
          'approved. If you already have an account, sign in instead.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request an account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "You'll need an invite code from your administrator.",
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _name,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _email,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _code,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Invite code',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                    errorMaxLines: 3,
                    suffixIcon: _checkingCode
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _role != null
                            ? const Icon(Icons.check_circle_outline)
                            : null,
                  ),
                ),
                if (_role != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'This code is for a $_role account.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Send request'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
