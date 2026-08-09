import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/material_master_item.dart';
import 'material_master_screen.dart';
import 'widgets/load_error_view.dart';

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
    this.changedByUserId,
  });

  final SurveyRepository repository;

  /// Threaded through unchanged to every [MaterialMasterScreen] this pushes.
  final String changedByRole;
  final String? changedByUserId;

  @override
  State<MaterialMasterGroupListScreen> createState() =>
      _MaterialMasterGroupListScreenState();
}

class _MaterialMasterGroupListScreenState
    extends State<MaterialMasterGroupListScreen> {
  List<MaterialMasterItem> _items = const [];
  bool _loading = true;
  Object? _loadError;
  bool _loadedOnce = false;

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
    try {
      final items = await widget.repository.getMaterialMasterItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _loadedOnce = true;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      // A failed refresh keeps whatever is already on screen — only a
      // first load, which has nothing to fall back to, hands over to
      // LoadErrorView.
      final hadContent = _loadedOnce;
      setState(() {
        _loading = false;
        _loadError = hadContent ? null : error;
      });
      if (hadContent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't refresh: $error")),
        );
      }
    }
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
          changedByUserId: widget.changedByUserId,
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
          : _loadError != null
          ? LoadErrorView(onRetry: _load, details: _loadError)
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
