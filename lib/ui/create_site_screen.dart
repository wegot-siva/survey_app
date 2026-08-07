import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import 'sync_scope.dart';
import 'widgets/form_fields.dart';

/// Create a new site: the Sales-owned site metadata (name, address, client
/// name, client contact — the same set [EditSiteDetailsScreen] edits), of
/// which only the name is required. Blocks are added later, during the
/// survey, via Site Hub's "Blocks" section, and the engineer's on-site
/// Client Inputs are a separate section they fill themselves.
class CreateSiteScreen extends StatefulWidget {
  const CreateSiteScreen({super.key, required this.repository});

  final SurveyRepository repository;

  @override
  State<CreateSiteScreen> createState() => _CreateSiteScreenState();
}

class _CreateSiteScreenState extends State<CreateSiteScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _clientNameController = TextEditingController();
  final _clientContactController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _clientNameController.dispose();
    _clientContactController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a site name.')),
      );
      return;
    }

    setState(() => _saving = true);
    await widget.repository.createSite(
      name: name,
      address: _addressController.text.trim(),
      clientName: _clientNameController.text.trim(),
      clientContact: _clientContactController.text.trim(),
    );
    if (!mounted) return;
    // Sync strictly after the local write and after the pop — see
    // client_inputs_screen.dart's _save for the full reasoning. A newly
    // created site is exactly the kind of edit another device/account may
    // need to see; without this, it sits local-only until some other
    // trigger happens to fire.
    final sync = SyncScope.read(context);
    Navigator.of(context).pop();
    unawaited(sync.requestSync(manual: false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New site')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Site name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _addressController,
            label: 'Address (optional)',
            maxLines: 2,
          ),
          AppTextField(
            controller: _clientNameController,
            label: 'Client name (optional)',
          ),
          AppTextField(
            controller: _clientContactController,
            label: 'Client contact (optional)',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save site'),
          ),
        ],
      ),
    );
  }
}
