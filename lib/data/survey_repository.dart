import '../models/client_inputs.dart';
import '../models/duct_lora.dart';
import '../models/footer.dart';
import '../models/gateway.dart';
import '../models/inlet_point.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';

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

  Future<List<MaterialMasterItem>> getMaterialMasterItems();

  /// Persists a new Material Master row, assigning it an id, and returns it.
  Future<MaterialMasterItem> addMaterialMasterItem(MaterialMasterItem item);

  Future<void> updateMaterialMasterItem(MaterialMasterItem item);

  Future<void> deleteMaterialMasterItem(String id);
}
