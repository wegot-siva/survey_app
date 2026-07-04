import '../models/bom_manual_entry.dart';
import '../models/client_inputs.dart';
import '../models/duct_lora.dart';
import '../models/footer.dart';
import '../models/gateway.dart';
import '../models/inlet_point.dart';
import '../models/material_master_audit_entry.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_photo.dart';

/// The single gateway between the UI and stored survey data.
///
/// PROJECT RULE: UI/screens must NEVER touch storage directly — all reads and
/// writes go through a [SurveyRepository]. The local implementation is sqflite;
/// an in-memory stub backs widget tests.
abstract class SurveyRepository {
  Future<List<Site>> getSites();

  Future<Site?> getSiteById(String id);

  /// Creates and persists a new site, returning the stored instance.
  Future<Site> createSite({required String name, List<String> blocks});

  Future<void> updateSite(Site site);

  /// Replaces a site's block list. Leaves the site name and client inputs
  /// untouched (unlike [updateSite], which writes the whole site).
  Future<void> updateSiteBlocks(String siteId, List<String> blocks);

  /// Saves (or replaces) the Client inputs form for an existing site.
  Future<void> saveClientInputs(String siteId, ClientInputs inputs);

  // ---- Source points (a site has many) ------------------------------------

  Future<List<SourcePoint>> getSourcePoints(String siteId);

  /// Persists a new source point, assigning it an id, and returns it.
  Future<SourcePoint> addSourcePoint(SourcePoint sourcePoint);

  Future<void> updateSourcePoint(SourcePoint sourcePoint);

  Future<void> deleteSourcePoint(String id);

  // ---- Inlet points (a site has many) -------------------------------------

  Future<List<InletPoint>> getInletPoints(String siteId);

  /// Persists a new inlet point, assigning it an id, and returns it.
  Future<InletPoint> addInletPoint(InletPoint inletPoint);

  Future<void> updateInletPoint(InletPoint inletPoint);

  Future<void> deleteInletPoint(String id);

  // ---- Duct LoRa units (a site has many) ----------------------------------

  Future<List<DuctLora>> getDuctLoras(String siteId);

  /// Persists a new Duct LoRa unit, assigning it an id, and returns it.
  Future<DuctLora> addDuctLora(DuctLora ductLora);

  Future<void> updateDuctLora(DuctLora ductLora);

  Future<void> deleteDuctLora(String id);

  // ---- Gateways (a site has many) -----------------------------------------

  Future<List<Gateway>> getGateways(String siteId);

  /// Persists a new gateway, assigning it an id, and returns it.
  Future<Gateway> addGateway(Gateway gateway);

  Future<void> updateGateway(Gateway gateway);

  Future<void> deleteGateway(String id);

  // ---- Footer (one per site, like Client inputs) --------------------------

  /// Returns the site's Footer form, or null if not filled yet.
  Future<Footer?> getFooter(String siteId);

  /// Saves (or replaces) the Footer form for an existing site.
  Future<void> saveFooter(String siteId, Footer footer);

  // ---- Material Master (admin-editable reference data, not site-scoped) ---
  //
  // Every create/edit/delete writes to the change log (material_master_audit)
  // as part of the same call — [changedByRole] is the signed-in role's label
  // (e.g. "Admin"), recorded against each audit entry.

  Future<List<MaterialMasterItem>> getMaterialMasterItems();

  /// Persists a new Material Master row, assigning it an id, and returns it.
  Future<MaterialMasterItem> addMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
  });

  /// Updates an existing row and logs one change-log entry per field that
  /// actually changed (diffed against the row currently stored under
  /// [item.id]).
  Future<void> updateMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
  });

  /// Deletes a row and logs a single change-log entry summarizing what was
  /// removed.
  Future<void> deleteMaterialMasterItem(String id, {required String changedByRole});

  /// The full Material Master change log, newest first.
  Future<List<MaterialMasterAuditEntry>> getMaterialMasterAuditLog();

  // ---- Photos (polymorphic, slot-based — photo slice 2) -------------------

  /// All photos for one owner record, ordered by slot then position.
  Future<List<SurveyPhoto>> getPhotos(String ownerType, String ownerId);

  /// Replaces the full photo set for ([ownerType], [ownerId]) with [photos]:
  /// rows not present are deleted, new ones (empty id) inserted, existing ones
  /// updated. Lets a form submit its whole desired set in one call while
  /// preserving each kept photo's remote-path linkage.
  Future<void> setPhotos(
    String ownerType,
    String ownerId,
    List<SurveyPhoto> photos,
  );

  /// Every photo across all owners — used by sync to find pending uploads.
  Future<List<SurveyPhoto>> getAllPhotos();

  /// Updates one photo row by id (e.g. sync writing back a remote path).
  Future<void> updatePhoto(SurveyPhoto photo);

  // ---- BoM manual entries (D/E/G "Add materials" picker) -------------------
  //
  // Mechanics only — not wired into any snapshot/finalize flow yet, and never
  // read by BomEngine. Reachable from the BoM preview screen for any survey
  // regardless of status.

  /// All manual entries for one survey, oldest first.
  Future<List<BomManualEntry>> getBomManualEntries(String surveyId);

  /// Persists a new manual entry, assigning it an id, and returns it.
  Future<BomManualEntry> addBomManualEntry(BomManualEntry entry);

  /// Updates an existing entry. [entry.addedBy] / [entry.addedAt] are carried
  /// over from the original entry, not re-stamped — this is an edit, not a
  /// new addition.
  Future<void> updateBomManualEntry(BomManualEntry entry);

  Future<void> deleteBomManualEntry(String id);
}
