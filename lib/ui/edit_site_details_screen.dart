import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import 'widgets/form_fields.dart';

/// Sales' "Edit site details" action — edits site-level metadata (name,
/// address, client contact) on an existing site. Distinct from the field
/// engineer's Client Inputs survey section ([Site.clientInputs]), which this
/// screen never touches, and from blocks (see [ManageBlocksScreen]).
class EditSiteDetailsScreen extends StatefulWidget {
  const EditSiteDetailsScreen({
    super.key,
    required this.repository,
    required this.site,
  });

  final SurveyRepository repository;
  final Site site;

  @override
  State<EditSiteDetailsScreen> createState() => _EditSiteDetailsScreenState();
}

class _EditSiteDetailsScreenState extends State<EditSiteDetailsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _clientName;
  late final TextEditingController _clientContact;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.site.name);
    _address = TextEditingController(text: widget.site.address);
    _clientName = TextEditingController(text: widget.site.clientName);
    _clientContact = TextEditingController(text: widget.site.clientContact);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _clientName.dispose();
    _clientContact.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a site name.')),
      );
      return;
    }

    setState(() => _saving = true);
    await widget.repository.updateSite(
      widget.site.copyWith(
        name: name,
        address: _address.text.trim(),
        clientName: _clientName.text.trim(),
        clientContact: _clientContact.text.trim(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Site details saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit site details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppTextField(controller: _name, label: 'Site name'),
          AppTextField(controller: _address, label: 'Address', maxLines: 2),
          AppTextField(controller: _clientName, label: 'Client name'),
          AppTextField(controller: _clientContact, label: 'Client contact'),
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
            label: const Text('Save site details'),
          ),
        ],
      ),
    );
  }
}
