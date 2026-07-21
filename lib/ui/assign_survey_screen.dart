import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/engineer.dart';
import '../models/site.dart';
import '../models/survey_status.dart';
import '../services/sync_service.dart';
import 'client_inputs_screen.dart';

/// Sales' "New survey" flow (Roles & Assignment — Slice B). Approver also
/// uses this screen unmodified, for the same Sales-like create+assign
/// capability (see home_screen.dart's FAB routing).
///
/// Two phases in one screen: first create the site (name only — blocks are
/// added later, during the survey, via Site Hub's "Blocks" section), then
/// optionally fill Client inputs (pre-survey info recorded from the
/// customer — reuses [ClientInputsScreen] unmodified), then assign an
/// engineer and set status to [SurveyStatus.assigned].
class AssignSurveyScreen extends StatefulWidget {
  const AssignSurveyScreen({
    super.key,
    required this.repository,
    required this.syncService,
  });

  final SurveyRepository repository;
  final SyncService syncService;

  @override
  State<AssignSurveyScreen> createState() => _AssignSurveyScreenState();
}

class _AssignSurveyScreenState extends State<AssignSurveyScreen> {
  final _nameController = TextEditingController();

  Site? _createdSite;
  Engineer? _engineer;
  bool _saving = false;

  List<Engineer>? _roster;
  String? _rosterError;
  bool _loadingRoster = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// The engineer roster is a live Supabase query (real accounts, not the
  /// retired hardcoded list — see SyncService.fetchEngineerRoster), so it
  /// needs its own loading/error state, fetched once the site exists (step
  /// 2 of this screen) rather than up front.
  Future<void> _loadRoster() async {
    setState(() {
      _loadingRoster = true;
      _rosterError = null;
    });
    try {
      final roster = await widget.syncService.fetchEngineerRoster();
      if (!mounted) return;
      setState(() {
        _roster = roster;
        _loadingRoster = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rosterError = 'Could not load the engineer list: $e';
        _loadingRoster = false;
      });
    }
  }

  Future<void> _createSite() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a site name.')),
      );
      return;
    }

    setState(() => _saving = true);
    final site = await widget.repository.createSite(name: name);
    if (!mounted) return;
    setState(() {
      _createdSite = site;
      _saving = false;
    });
    unawaited(_loadRoster());
  }

  Future<void> _openClientInputs() async {
    final site = _createdSite;
    if (site == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ClientInputsScreen(repository: widget.repository, site: site),
      ),
    );
    // Re-fetch so the "filled" indicator reflects what was just saved.
    final refreshed = await widget.repository.getSiteById(site.id);
    if (!mounted || refreshed == null) return;
    setState(() => _createdSite = refreshed);
  }

  Future<void> _assign() async {
    final site = _createdSite;
    if (site == null) return;
    if (_engineer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an engineer.')),
      );
      return;
    }

    final engineer = _engineer!;
    setState(() => _saving = true);
    await widget.repository.updateSite(
      site.copyWith(
        assignedTo: engineer.name,
        assignedToUserId: engineer.id,
        status: SurveyStatus.assigned,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Survey assigned to ${engineer.name}.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final site = _createdSite;
    return Scaffold(
      appBar: AppBar(title: const Text('New survey')),
      body: site == null ? _buildCreateForm() : _buildAssignForm(site),
    );
  }

  Widget _buildCreateForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Hint(
          'Step 1 of 2 — create the site, then assign it to an engineer.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Site name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _createSite,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward),
          label: const Text('Create survey'),
        ),
      ],
    );
  }

  Widget _buildAssignForm(Site site) {
    final hasInputs = site.clientInputs != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Hint('Step 2 of 2 — optionally record pre-survey info, then assign.'),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_city_outlined),
            title: Text(site.name),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openClientInputs,
          icon: Icon(
            hasInputs ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          ),
          label: Text(
            hasInputs ? 'Client inputs saved — edit' : 'Fill Client inputs',
          ),
        ),
        const SizedBox(height: 24),
        _buildEngineerPicker(),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving || _engineer == null ? null : _assign,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.assignment_turned_in_outlined),
          label: const Text('Assign survey'),
        ),
      ],
    );
  }

  Widget _buildEngineerPicker() {
    if (_loadingRoster) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_rosterError != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_rosterError!)),
          TextButton(onPressed: _loadRoster, child: const Text('Retry')),
        ],
      );
    }
    final roster = _roster ?? const [];
    return DropdownButtonFormField<Engineer>(
      initialValue: _engineer,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Assign to engineer',
        border: const OutlineInputBorder(),
        helperText: roster.isEmpty ? 'No engineer accounts found.' : null,
      ),
      items: [
        for (final engineer in roster)
          DropdownMenuItem(value: engineer, child: Text(engineer.name)),
      ],
      onChanged: (v) => setState(() => _engineer = v),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
