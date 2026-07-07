import 'package:flutter/material.dart';

import '../models/engineer_directory.dart';
import '../models/user_role.dart';
import '../services/session_controller.dart';
import 'theme/app_theme.dart';

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

  // Which engineer the shared Engineer login is simulating (Slice C) — there
  // are no real per-user accounts yet, so this is how testing the per-engineer
  // filter works. Only used when _role == UserRole.engineer.
  String? _engineerName;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_role == UserRole.engineer && _engineerName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose which engineer you are.')),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await widget.session.login(
      _role,
      _password.text,
      engineerName: _engineerName,
    );

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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Survey App',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.title,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Role', style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.sm),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 2.6,
                  children: [
                    for (final role in UserRole.values)
                      Center(
                        child: ChoiceChip(
                          label: Text(role.label),
                          showCheckmark: false,
                          selected: _role == role,
                          selectedColor: colorScheme.primaryContainer,
                          backgroundColor: colorScheme.secondaryContainer,
                          labelStyle: TextStyle(
                            color: _role == role
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSecondaryContainer,
                          ),
                          onSelected: _submitting
                              ? null
                              : (_) => setState(() {
                                  _role = role;
                                  if (_role != UserRole.engineer) {
                                    _engineerName = null;
                                  }
                                }),
                        ),
                      ),
                  ],
                ),
                if (_role == UserRole.engineer) ...[
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    initialValue: _engineerName,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Which engineer are you?',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final name in kEngineerDirectory)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _engineerName = v),
                  ),
                ],
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
