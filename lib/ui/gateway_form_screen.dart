import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/survey_repository.dart';
import '../models/gateway.dart';
import '../models/site.dart';
import '../models/survey_options.dart';
import '../models/survey_photo.dart';
import 'widgets/form_fields.dart';
import 'widgets/photo_capture_field.dart';

/// Add or edit a single gateway. All fields optional (partial saves).
class GatewayFormScreen extends StatefulWidget {
  const GatewayFormScreen({
    super.key,
    required this.repository,
    required this.site,
    this.existing,
  });

  final SurveyRepository repository;
  final Site site;
  final Gateway? existing;

  @override
  State<GatewayFormScreen> createState() => _GatewayFormScreenState();
}

class _GatewayFormScreenState extends State<GatewayFormScreen> {
  late final TextEditingController _locationDescription;
  late final TextEditingController _quantity;
  late final TextEditingController _wifiInterferenceDetails;
  late final TextEditingController _mountingHardware;

  GatewayPlacement? _placement;
  final Set<String> _blocksCovered = {};
  UplinkType? _uplinkType;
  bool? _wifiInterferenceCheck;
  SimCoverage? _simCoverage;
  bool? _uninterruptedPowerSource;

  /// Captured gateway-location photos (single slot, multiple allowed). Loaded
  /// on edit; reconciled on save.
  final List<PhotoDraft> _locationPhotos = [];

  bool _saving = false;

  bool get _usesRouter =>
      _uplinkType == UplinkType.router || _uplinkType == UplinkType.both;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) _loadPhotos(e.id);

    _locationDescription = TextEditingController(
      text: e?.locationDescription ?? '',
    );
    _quantity = TextEditingController(text: e?.quantity?.toString() ?? '');
    _wifiInterferenceDetails = TextEditingController(
      text: e?.wifiInterferenceDetails ?? '',
    );
    _mountingHardware = TextEditingController(
      text: e?.mountingHardwareNeeded ?? '',
    );

    _placement = e?.placement;
    _blocksCovered.addAll(
      (e?.blocksCovered ?? const {}).where(widget.site.blocks.contains),
    );
    _uplinkType = e?.uplinkType;
    _wifiInterferenceCheck = e?.wifiInterferenceCheck;
    _simCoverage = e?.simCoverage;
    _uninterruptedPowerSource = e?.uninterruptedPowerSource;
  }

  @override
  void dispose() {
    _locationDescription.dispose();
    _quantity.dispose();
    _wifiInterferenceDetails.dispose();
    _mountingHardware.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos(String ownerId) async {
    final loaded = await widget.repository.getPhotos(
      PhotoOwner.gateway,
      ownerId,
    );
    if (!mounted) return;
    setState(() {
      for (final p in loaded) {
        if (p.slot == PhotoSlot.gatewayLocation) {
          _locationPhotos.add(
            PhotoDraft(id: p.id, localPath: p.localPath, remotePath: p.remotePath),
          );
        }
      }
    });
  }

  void _onLocationAdded(String localPath) {
    setState(() => _locationPhotos.add(PhotoDraft(localPath: localPath)));
  }

  void _onLocationRemoved(int index) {
    setState(() => _locationPhotos.removeAt(index));
  }

  List<SurveyPhoto> _photoListFor(String ownerId) {
    final list = <SurveyPhoto>[];
    for (var i = 0; i < _locationPhotos.length; i++) {
      final draft = _locationPhotos[i];
      if (draft.localPath == null) continue;
      list.add(
        SurveyPhoto(
          id: draft.id,
          ownerType: PhotoOwner.gateway,
          ownerId: ownerId,
          slot: PhotoSlot.gatewayLocation,
          position: i,
          localPath: draft.localPath,
          remotePath: draft.remotePath,
        ),
      );
    }
    return list;
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // Drop the WiFi answer if the uplink no longer involves a router.
    final wifiCheck = _usesRouter ? _wifiInterferenceCheck : null;
    final wifiDetails = (_usesRouter && wifiCheck == true)
        ? _wifiInterferenceDetails.text.trim()
        : '';

    final draft = Gateway(
      id: widget.existing?.id ?? '',
      siteId: widget.site.id,
      placement: _placement,
      locationDescription: _locationDescription.text.trim(),
      blocksCovered: Set.unmodifiable(_blocksCovered),
      quantity: int.tryParse(_quantity.text.trim()),
      uplinkType: _uplinkType,
      wifiInterferenceCheck: wifiCheck,
      wifiInterferenceDetails: wifiDetails,
      simCoverage: _simCoverage,
      uninterruptedPowerSource: _uninterruptedPowerSource,
      mountingHardwareNeeded: _mountingHardware.text.trim(),
    );

    final String ownerId;
    if (widget.existing == null) {
      final stored = await widget.repository.addGateway(draft);
      ownerId = stored.id;
    } else {
      await widget.repository.updateGateway(draft);
      ownerId = widget.existing!.id;
    }
    await widget.repository.setPhotos(
      PhotoOwner.gateway,
      ownerId,
      _photoListFor(ownerId),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gateway saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add gateway' : 'Edit gateway'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppDropdownField<GatewayPlacement>(
            label: 'Indoor / outdoor',
            value: _placement,
            items: GatewayPlacement.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _placement = v),
          ),
          AppTextField(
            controller: _locationDescription,
            label: 'Location description',
            maxLines: 2,
          ),
          MultiSelectChips<String>(
            label: 'Blocks covered',
            items: widget.site.blocks,
            itemLabel: (b) => b,
            selected: _blocksCovered,
            emptyHint: 'No blocks on this site — add them via the site first.',
            onChanged: (next) => setState(() {
              _blocksCovered
                ..clear()
                ..addAll(next);
            }),
          ),
          AppTextField(
            controller: _quantity,
            label: 'Quantity',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          AppDropdownField<UplinkType>(
            label: 'Uplink type',
            value: _uplinkType,
            items: UplinkType.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _uplinkType = v),
          ),
          if (_usesRouter) ...[
            YesNoField(
              label: 'WiFi interference check',
              value: _wifiInterferenceCheck,
              onChanged: (v) => setState(() => _wifiInterferenceCheck = v),
            ),
            if (_wifiInterferenceCheck == true)
              AppTextField(
                controller: _wifiInterferenceDetails,
                label: 'WiFi interference details',
                maxLines: 2,
              ),
          ],
          AppDropdownField<SimCoverage>(
            label: 'SIM coverage',
            value: _simCoverage,
            items: SimCoverage.values,
            itemLabel: (v) => v.label,
            onChanged: (v) => setState(() => _simCoverage = v),
          ),
          YesNoField(
            label: 'Uninterrupted power source',
            value: _uninterruptedPowerSource,
            onChanged: (v) => setState(() => _uninterruptedPowerSource = v),
          ),
          AppTextField(
            controller: _mountingHardware,
            label: 'Mounting hardware needed',
            maxLines: 2,
          ),

          const FormSectionLabel('Photos'),
          MultiPhotoCaptureField(
            label: 'Gateway location',
            photos: [
              for (final d in _locationPhotos)
                if (d.localPath != null) PhotoView(d.localPath!, uploaded: d.uploaded),
            ],
            onAdded: _onLocationAdded,
            onRemoved: _onLocationRemoved,
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
            label: const Text('Save gateway'),
          ),
        ],
      ),
    );
  }
}
