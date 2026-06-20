import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/engineer_directory.dart';
import '../models/site.dart';
import '../models/survey_status.dart';
import 'client_inputs_screen.dart';

/// Sales' "New survey" flow (Roles & Assignment — Slice B).
///
/// Two phases in one screen: first create the site (name + blocks, same as
/// [CreateSiteScreen] but kept separate so that screen's other callers are
/// unaffected); once created, optionally fill Client inputs (pre-survey info
/// Sales records from the customer — reuses [ClientInputsScreen] unmodified),
/// then assign an engineer and set status to [SurveyStatus.assigned].
class AssignSurveyScreen extends StatefulWidget {
  const AssignSurveyScreen({super.key, required this.repository});

  final SurveyRepository repository;

  @override
  State<AssignSurveyScreen> createState() => _AssignSurveyScreenState();
}

class _AssignSurveyScreenState extends State<AssignSurveyScreen> {
  final _nameController = TextEditingController();
  final _scrollController = ScrollController();
  final List<TextEditingController> _blockControllers = [];

  Site? _createdSite;
  String? _engineer;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _scrollController.dispose();
    for (final c in _blockControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addBlock() {
    setState(() => _blockControllers.add(TextEditingController()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeBlock(int index) {
    setState(() {
      _blockControllers[index].dispose();
      _blockControllers.removeAt(index);
    });
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
    final blocks = _blockControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final site = await widget.repository.createSite(name: name, blocks: blocks);
    if (!mounted) return;
    setState(() {
      _createdSite = site;
      _saving = false;
    });
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

    setState(() => _saving = true);
    await widget.repository.updateSite(
      site.copyWith(assignedTo: _engineer, status: SurveyStatus.assigned),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Survey assigned to $_engineer.')),
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
      controller: _scrollController,
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
        Row(
          children: [
            Text('Blocks', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: _addBlock,
              icon: const Icon(Icons.add),
              label: const Text('Add block'),
            ),
          ],
        ),
        if (_blockControllers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No blocks added.'),
          ),
        for (var i = 0; i < _blockControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _blockControllers[i],
                    decoration: InputDecoration(
                      labelText: 'Block ${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove block',
                  onPressed: () => _removeBlock(i),
                  icon: const Icon(Icons.close),
                ),
              ],
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
            subtitle: Text('${site.blocks.length} block(s)'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openClientInputs,
          icon: Icon(
            hasInputs ? Icons.check_circle_outline : Icons.assignment_outlined,
          ),
          label: Text(
            hasInputs ? 'Client inputs saved — edit' : 'Fill Client inputs',
          ),
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(
          initialValue: _engineer,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Assign to engineer',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final engineer in kEngineerDirectory)
              DropdownMenuItem(value: engineer, child: Text(engineer)),
          ],
          onChanged: (v) => setState(() => _engineer = v),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _assign,
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
