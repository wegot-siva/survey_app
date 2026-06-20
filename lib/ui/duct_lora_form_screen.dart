import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/survey_repository.dart';
import '../models/duct_lora.dart';
import '../models/site.dart';
import '../services/photo_file_store.dart';
import 'widgets/form_fields.dart';

/// Add or edit a single Duct LoRa unit. All fields optional (partial saves).
///
/// [availableSeries] are the distinct Series values entered on this site's
/// inlet points — the unit's "series served" is chosen from those.
class DuctLoraFormScreen extends StatefulWidget {
  const DuctLoraFormScreen({
    super.key,
    required this.repository,
    required this.site,
    required this.availableSeries,
    this.existing,
  });

  final SurveyRepository repository;
  final Site site;
  final List<String> availableSeries;
  final DuctLora? existing;

  @override
  State<DuctLoraFormScreen> createState() => _DuctLoraFormScreenState();
}

class _DuctLoraFormScreenState extends State<DuctLoraFormScreen> {
  late final TextEditingController _rssi;
  late final TextEditingController _cableLength;

  String? _block;
  final Set<String> _seriesServed = {};

  bool? _accessibleForService;
  bool? _powerPointAvailableShielded;
  bool? _separateMcbForSeries;
  bool? _upsPowerSupply;

  final ImagePicker _picker = ImagePicker();
  final PhotoFileStore _photoStore = PhotoFileStore();
  String? _placementPhotoLocalPath;
  String? _placementPhotoRemotePath;
  bool _capturing = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _rssi = TextEditingController(text: e?.rssiIfTcl?.toString() ?? '');
    _cableLength = TextEditingController(
      text: e?.cableLength?.toString() ?? '',
    );

    _block = (e?.block != null && widget.site.blocks.contains(e!.block))
        ? e.block
        : null;
    _seriesServed.addAll(e?.seriesServed ?? const {});

    _accessibleForService = e?.accessibleForService;
    _powerPointAvailableShielded = e?.powerPointAvailableShielded;
    _separateMcbForSeries = e?.separateMcbForSeries;
    _upsPowerSupply = e?.upsPowerSupply;

    _placementPhotoLocalPath = e?.placementPhotoLocalPath;
    _placementPhotoRemotePath = e?.placementPhotoRemotePath;
  }

  Future<void> _capturePlacementPhoto() async {
    setState(() => _capturing = true);
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 2000,
      );
      if (shot == null) {
        if (mounted) setState(() => _capturing = false);
        return;
      }
      // Copy out of the cache into stable storage immediately (offline-first).
      final savedPath = await _photoStore.saveCapture(shot.path);
      if (!mounted) return;
      setState(() {
        _placementPhotoLocalPath = savedPath;
        // A new capture must be re-uploaded — drop any previous remote key.
        _placementPhotoRemotePath = null;
        _capturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture photo: $e')),
      );
    }
  }

  @override
  void dispose() {
    _rssi.dispose();
    _cableLength.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final draft = DuctLora(
      id: widget.existing?.id ?? '',
      siteId: widget.site.id,
      block: _block,
      seriesServed: Set.unmodifiable(_seriesServed),
      accessibleForService: _accessibleForService,
      rssiIfTcl: double.tryParse(_rssi.text.trim()),
      powerPointAvailableShielded: _powerPointAvailableShielded,
      separateMcbForSeries: _separateMcbForSeries,
      upsPowerSupply: _upsPowerSupply,
      cableLength: double.tryParse(_cableLength.text.trim()),
      placementPhotoLocalPath: _placementPhotoLocalPath,
      placementPhotoRemotePath: _placementPhotoRemotePath,
    );

    if (widget.existing == null) {
      await widget.repository.addDuctLora(draft);
    } else {
      await widget.repository.updateDuctLora(draft);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Duct LoRa unit saved.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Add Duct LoRa' : 'Edit Duct LoRa',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppDropdownField<String>(
            label: 'Block',
            value: _block,
            items: widget.site.blocks,
            itemLabel: (b) => b,
            emptyHint: 'No blocks on this site — add them via the site first.',
            onChanged: (v) => setState(() => _block = v),
          ),
          MultiSelectChips<String>(
            label: 'Series served',
            items: widget.availableSeries,
            itemLabel: (s) => s,
            selected: _seriesServed,
            emptyHint:
                'No series found — add inlet points with a Series first.',
            helperText: 'Max 20 sensors per unit.',
            onChanged: (next) => setState(() {
              _seriesServed
                ..clear()
                ..addAll(next);
            }),
          ),
          YesNoField(
            label: 'Accessible for service',
            value: _accessibleForService,
            onChanged: (v) => setState(() => _accessibleForService = v),
          ),
          AppTextField(
            controller: _rssi,
            label: 'RSSI value (if TCL)',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')),
            ],
          ),
          YesNoField(
            label: 'Power point available / shielded',
            value: _powerPointAvailableShielded,
            onChanged: (v) =>
                setState(() => _powerPointAvailableShielded = v),
          ),
          YesNoField(
            label: 'Separate MCB for series (max 4)',
            value: _separateMcbForSeries,
            onChanged: (v) => setState(() => _separateMcbForSeries = v),
          ),
          YesNoField(
            label: 'UPS power supply',
            value: _upsPowerSupply,
            onChanged: (v) => setState(() => _upsPowerSupply = v),
          ),
          AppTextField(
            controller: _cableLength,
            label: 'Duct LoRa cable length (pending confirmation)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),

          const FormSectionLabel('Photos'),
          _PlacementPhotoField(
            localPath: _placementPhotoLocalPath,
            uploaded: _placementPhotoRemotePath != null,
            capturing: _capturing,
            onCapture: _capturing ? null : _capturePlacementPhoto,
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
            label: const Text('Save Duct LoRa unit'),
          ),
        ],
      ),
    );
  }
}

/// Capture + preview for the Duct LoRa placement photo (photo slice 1).
///
/// Shows the captured image as a thumbnail (read from the local file, so it
/// works fully offline), an uploaded/pending indicator, and a capture/retake
/// button. The photo uploads to Storage on the next sync.
class _PlacementPhotoField extends StatelessWidget {
  const _PlacementPhotoField({
    required this.localPath,
    required this.uploaded,
    required this.capturing,
    required this.onCapture,
  });

  final String? localPath;
  final bool uploaded;
  final bool capturing;
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = localPath != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Duct LoRa location / placement',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          if (hasPhoto)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(localPath!),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 160,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Text('Saved photo unavailable.'),
                ),
              ),
            ),
          if (hasPhoto) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  uploaded ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  size: 16,
                  color: Theme.of(context).hintColor,
                ),
                const SizedBox(width: 6),
                Text(
                  uploaded ? 'Uploaded' : 'Saved on device — uploads on next sync',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onCapture,
            icon: capturing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_camera_outlined),
            label: Text(hasPhoto ? 'Retake photo' : 'Take photo'),
          ),
        ],
      ),
    );
  }
}
