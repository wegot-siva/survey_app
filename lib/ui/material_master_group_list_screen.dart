import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/material_master_item.dart';
import 'material_master_screen.dart';

/// Material Master's first screen: all seven groups (A–G), each with a live
/// count of its active (non-deleted) rows. Tapping one pushes
/// [MaterialMasterScreen] scoped to that group — the second level of
/// navigation, reusing that screen unchanged (search, selection mode, Clear
/// all, edit/delete all still work, just narrowed to one group's rows).
///
/// Gated behind the Admin role, same as [MaterialMasterScreen] — reached
/// only from the home screen's Material Master entry point.
class MaterialMasterGroupListScreen extends StatefulWidget {
  const MaterialMasterGroupListScreen({
    super.key,
    required this.repository,
    required this.changedByRole,
  });

  final SurveyRepository repository;

  /// Threaded through unchanged to every [MaterialMasterScreen] this pushes.
  final String changedByRole;

  @override
  State<MaterialMasterGroupListScreen> createState() =>
      _MaterialMasterGroupListScreenState();
}

class _MaterialMasterGroupListScreenState
    extends State<MaterialMasterGroupListScreen> {
  List<MaterialMasterItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Fetches every active row once, then [_countFor] narrows it down per
  /// group in memory — same "one fetch, filter in the UI" approach
  /// [MaterialMasterScreen] itself uses for its own group scoping, rather
  /// than one query per group.
  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await widget.repository.getMaterialMasterItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  int _countFor(MaterialGroup group) =>
      _items.where((i) => i.group == group).length;

  /// Reloads on return — an add/edit/delete inside the pushed
  /// [MaterialMasterScreen] may have changed this group's count (or, via
  /// Clear all, several at once), so the counts shown here must reflect that
  /// the moment the admin comes back rather than staying stale.
  Future<void> _openGroup(MaterialGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MaterialMasterScreen(
          repository: widget.repository,
          changedByRole: widget.changedByRole,
          group: group,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Material Master')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: MaterialGroup.values.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final group = MaterialGroup.values[index];
                final count = _countFor(group);
                return ListTile(
                  leading: CircleAvatar(child: Text(group.code)),
                  title: Text(group.label),
                  trailing: Text(
                    '$count item${count == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onTap: () => _openGroup(group),
                );
              },
            ),
    );
  }
}
