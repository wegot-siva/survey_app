import 'package:flutter/material.dart';

import '../data/survey_repository.dart';

/// Create a new site: a name plus zero or more repeatable "block" text entries.
class CreateSiteScreen extends StatefulWidget {
  const CreateSiteScreen({super.key, required this.repository});

  final SurveyRepository repository;

  @override
  State<CreateSiteScreen> createState() => _CreateSiteScreenState();
}

class _CreateSiteScreenState extends State<CreateSiteScreen> {
  final _nameController = TextEditingController();
  final List<TextEditingController> _blockControllers = [];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _blockControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addBlock() {
    setState(() => _blockControllers.add(TextEditingController()));
  }

  void _removeBlock(int index) {
    setState(() {
      _blockControllers[index].dispose();
      _blockControllers.removeAt(index);
    });
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
    final blocks = _blockControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    await widget.repository.createSite(name: name, blocks: blocks);
    if (!mounted) return;
    Navigator.of(context).pop();
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
