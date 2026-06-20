import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_survey_data_source.dart';
import '../data/survey_repository.dart';
import '../models/duct_lora.dart';
import 'supabase_service.dart';

/// Outcome of a sync run, surfaced to the UI.
class SyncResult {
  const SyncResult({
    required this.success,
    this.sites = 0,
    this.blocks = 0,
    this.clientInputs = 0,
    this.sourcePoints = 0,
    this.inletPoints = 0,
    this.ductLoras = 0,
    this.gateways = 0,
    this.footers = 0,
    this.materialMasterItems = 0,
    this.message,
  });

  final bool success;
  final int sites;
  final int blocks;
  final int clientInputs;
  final int sourcePoints;
  final int inletPoints;
  final int ductLoras;
  final int gateways;
  final int footers;
  final int materialMasterItems;
  final String? message;
}

/// Push-only sync (Phase 3): reads all local data via [SurveyRepository] and
/// upserts it to Supabase via [SupabaseSurveyDataSource].
///
/// "Push everything" each run — data volume is tiny and upserts are idempotent.
/// The UI never touches storage directly; it only calls [pushAll].
class SyncService {
  SyncService(this._repository, this._supabase, this._remote);

  final SurveyRepository _repository;
  final SupabaseService _supabase;
  final SupabaseSurveyDataSource _remote;

  Future<SyncResult> pushAll() async {
    if (!_supabase.isConfigured) {
      return const SyncResult(
        success: false,
        message: 'Supabase is not configured.\n\nRun with '
            '--dart-define-from-file=.env so credentials are available.',
      );
    }

    await _supabase.initIfConfigured();
    if (!_supabase.isInitialized) {
      return const SyncResult(
        success: false,
        message: 'Supabase failed to initialize. Check your keys in .env.',
      );
    }

    try {
      final sites = await _repository.getSites();
      var blocks = 0;
      var clientInputs = 0;
      var sourcePoints = 0;
      var inletPoints = 0;
      var ductLoras = 0;
      var gateways = 0;
      var footers = 0;
      for (final site in sites) {
        // Site (and its blocks/client inputs) first — children FK to it.
        await _remote.pushSite(site);
        blocks += site.blocks.length;
        if (site.clientInputs != null) clientInputs++;

        final sps = await _repository.getSourcePoints(site.id);
        for (final sp in sps) {
          await _remote.pushSourcePoint(sp);
        }
        sourcePoints += sps.length;

        final ips = await _repository.getInletPoints(site.id);
        for (final ip in ips) {
          await _remote.pushInletPoint(ip);
        }
        inletPoints += ips.length;

        final dls = await _repository.getDuctLoras(site.id);
        for (final dl in dls) {
          await _remote.pushDuctLora(await _withUploadedPhoto(dl));
        }
        ductLoras += dls.length;

        final gws = await _repository.getGateways(site.id);
        for (final gw in gws) {
          await _remote.pushGateway(gw);
        }
        gateways += gws.length;

        final footer = await _repository.getFooter(site.id);
        if (footer != null) {
          await _remote.pushFooter(site.id, footer);
          footers++;
        }
      }

      // Material Master is global reference data, not site-scoped — push the
      // whole table once, outside the per-site loop.
      final materials = await _repository.getMaterialMasterItems();
      for (final material in materials) {
        await _remote.pushMaterialMasterItem(material);
      }

      return SyncResult(
        success: true,
        sites: sites.length,
        blocks: blocks,
        clientInputs: clientInputs,
        sourcePoints: sourcePoints,
        inletPoints: inletPoints,
        ductLoras: ductLoras,
        gateways: gateways,
        footers: footers,
        materialMasterItems: materials.length,
      );
    } on PostgrestException catch (e) {
      return SyncResult(
        success: false,
        message: 'Sync failed (database):\n\n'
            'message: ${e.message}\n'
            'code: ${e.code}\n'
            'details: ${e.details}\n'
            'hint: ${e.hint}',
      );
    } catch (e) {
      return SyncResult(success: false, message: 'Sync failed:\n\n$e');
    }
  }

  /// If [dl] has a locally-captured placement photo not yet uploaded, uploads
  /// it to Storage, records the remote object key locally (write-back, so we
  /// don't re-upload on the next sync), and returns the updated unit. A missing
  /// local file (already uploaded, or moved) is skipped, not an error.
  Future<DuctLora> _withUploadedPhoto(DuctLora dl) async {
    final localPath = dl.placementPhotoLocalPath;
    if (localPath == null || dl.placementPhotoRemotePath != null) return dl;
    if (!await File(localPath).exists()) return dl;

    final objectKey = 'duct_loras/${dl.id}.jpg';
    await _remote.uploadPhoto(localPath, objectKey);
    final updated = dl.withPlacementPhotoRemotePath(objectKey);
    await _repository.updateDuctLora(updated);
    return updated;
  }
}
