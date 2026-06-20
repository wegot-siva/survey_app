import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/session_controller.dart';

/// Role-based sign-in shown at app start (Slice A). The user picks a role and
/// enters the shared password for it. On success, [SessionController] flips to
/// logged-in and the app's auth gate swaps to the home screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  UserRole _role = UserRole.engineer;
  final TextEditingController _password = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await widget.session.login(_role, _password.text);

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
    }
    // On success the auth gate rebuilds and replaces this screen; no nav here.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.badge_outlined, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Choose your role',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                SegmentedButton<UserRole>(
                  segments: [
                    for (final role in UserRole.values)
                      ButtonSegment(value: role, label: Text(role.label)),
                  ],
                  selected: {_role},
                  onSelectionChanged: _submitting
                      ? null
                      : (sel) => setState(() => _role = sel.first),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _password,
                  obscureText: true,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submitting ? null : _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _submitting ? null : _login,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text('Sign in as ${_role.label}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
