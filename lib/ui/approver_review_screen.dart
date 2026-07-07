import 'package:flutter/material.dart';

import '../data/survey_repository.dart';
import '../models/site.dart';
import '../models/survey_status.dart';

/// Approver's read-only review of a submitted survey (Roles & Assignment —
/// Slice D). Shows a summary of what the engineer recorded; no editing here —
/// edits stay in the engineer's Site Hub. Approving sets status to "approved"
/// then immediately "released", which is what makes the survey visible to
/// Sales as ready (the actual BoM/report push and notification email are
/// later phases, not built here).
class ApproverReviewScreen extends StatefulWidget {
  const ApproverReviewScreen({
    super.key,
    required this.repository,
    required this.siteId,
  });

  final SurveyRepository repository;
  final String siteId;

  @override
  State<ApproverReviewScreen> createState() => _ApproverReviewScreenState();
}

class _ApproverReviewScreenState extends State<ApproverReviewScreen> {
  Site? _site;
  int _sourcePointCount = 0;
  int _inletPointCount = 0;
  int _ductLoraCount = 0;
  int _gatewayCount = 0;
  bool _footerFilled = false;
  bool _loading = true;
  bool _approving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final site = await widget.repository.getSiteById(widget.siteId);
    final sourcePoints = await widget.repository.getSourcePoints(widget.siteId);
    final inletPoints = await widget.repository.getInletPoints(widget.siteId);
    final ductLoras = await widget.repository.getDuctLoras(widget.siteId);
    final gateways = await widget.repository.getGateways(widget.siteId);
    final footer = await widget.repository.getFooter(widget.siteId);
    if (!mounted) return;
    setState(() {
      _site = site;
      _sourcePointCount = sourcePoints.length;
      _inletPointCount = inletPoints.length;
      _ductLoraCount = ductLoras.length;
      _gatewayCount = gateways.length;
      _footerFilled = footer != null;
      _loading = false;
    });
  }

  Future<void> _approve() async {
    final site = _site;
    if (site == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve survey?'),
        content: const Text(
          'This releases the survey back to Sales as ready.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _approving = true);
    // Two real transitions, matching the lifecycle: approved, then released.
    await widget.repository.updateSite(
      site.copyWith(status: SurveyStatus.approved),
    );
    await widget.repository.updateSite(
      site.copyWith(status: SurveyStatus.released),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Survey approved and released to Sales.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    return Scaffold(
      appBar: AppBar(title: Text(site?.name ?? 'Review survey')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : site == null
          ? const Center(child: Text('Site not found.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (site.status != null) _ReviewStatusBanner(status: site.status!),
                const SizedBox(height: 8),
                _ReviewTile(
                  icon: Icons.person_outline,
                  title: 'Assigned to',
                  value: site.assignedTo ?? 'Unassigned',
                ),
                _ReviewTile(
                  icon: Icons.grid_view_outlined,
                  title: 'Blocks',
                  value: site.blocks.isEmpty ? 'None' : site.blocks.join(', '),
                ),
                _ReviewTile(
                  icon: Icons.assignment_outlined,
                  title: 'Client inputs',
                  value: site.clientInputs != null ? 'Filled' : 'Not filled',
                ),
                _ReviewTile(
                  icon: Icons.water_drop_outlined,
                  title: 'Source points',
                  value: '$_sourcePointCount recorded',
                ),
                _ReviewTile(
                  icon: Icons.input_outlined,
                  title: 'Inlet points',
                  value: '$_inletPointCount recorded',
                ),
                _ReviewTile(
                  icon: Icons.router_outlined,
                  title: 'Duct LoRa',
                  value: '$_ductLoraCount recorded',
                ),
                _ReviewTile(
                  icon: Icons.cell_tower_outlined,
                  title: 'Gateway',
                  value: '$_gatewayCount recorded',
                ),
                _ReviewTile(
                  icon: Icons.notes_outlined,
                  title: 'Footer',
                  value: _footerFilled ? 'Filled' : 'Not filled',
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _approving ? null : _approve,
                  icon: _approving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Approve'),
                ),
              ],
            ),
    );
  }
}

class _ReviewStatusBanner extends StatelessWidget {
  const _ReviewStatusBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.pending_actions_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Text(
              'Status: ${SurveyStatus.label(status)}',
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(value)),
    );
  }
}
