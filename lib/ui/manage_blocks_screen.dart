import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';

/// View / add / edit / delete a site's blocks after it exists.
///
/// Edits a working copy of the block list and persists via
/// [SurveyRepository.updateSiteBlocks] (which leaves name + client inputs
/// untouched). Source/Inlet block dropdowns read the site's blocks, so changes
/// here show up there the next time those forms are opened.
class ManageBlocksScreen extends StatefulWidget {
  const ManageBlocksScreen({
    super.key,
    required this.repository,
    required this.site,
  });

  final SurveyRepository repository;
  final Site site;

  @override
  State<ManageBlocksScreen> createState() => _ManageBlocksScreenState();
}

class _ManageBlocksScreenState extends State<ManageBlocksScreen> {
  final _scrollController = ScrollController();
  final List<TextEditingController> _blockControllers = [];
  final List<FocusNode> _blockFocusNodes = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final block in widget.site.blocks) {
      _blockControllers.add(TextEditingController(text: block));
      _blockFocusNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final c in _blockControllers) {
      c.dispose();
    }
    for (final f in _blockFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _addBlock() {
    setState(() {
      _blockControllers.add(TextEditingController());
      _blockFocusNodes.add(FocusNode());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      _blockFocusNodes.last.requestFocus();
    });
  }

  void _removeBlock(int index) {
    setState(() {
      _blockControllers[index].dispose();
      _blockControllers.removeAt(index);
      _blockFocusNodes[index].dispose();
      _blockFocusNodes.removeAt(index);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final blocks = _blockControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    await widget.repository.updateSiteBlocks(widget.site.id, blocks);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Blocks saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocks'),
        actions: [
          IconButton(
            tooltip: 'Save blocks',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBlock,
        icon: const Icon(Icons.add),
        label: const Text('Add block'),
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Blocks for "${widget.site.name}"',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_blockControllers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No blocks yet. Tap "Add block" to create one.'),
            ),
          for (var i = 0; i < _blockControllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _blockControllers[i],
                      focusNode: _blockFocusNodes[i],
                      decoration: InputDecoration(
                        labelText: 'Block ${i + 1}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete block',
                    onPressed: () => _removeBlock(i),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          // Clears the floating "Add block" button so the last row's text
          // field and delete icon stay reachable when scrolled to the end.
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}
