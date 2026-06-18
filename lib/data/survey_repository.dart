import '../models/client_inputs.dart';
import '../models/inlet_point.dart';
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
}
