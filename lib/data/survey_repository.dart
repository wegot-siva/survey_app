import '../models/client_inputs.dart';
import '../models/site.dart';

/// The single gateway between the UI and stored survey data.
///
/// PROJECT RULE: UI/screens must NEVER touch storage directly — all reads and
/// writes go through a [SurveyRepository]. The Phase 0 implementation is
/// in-memory; later phases swap in a real DB behind this same interface.
abstract class SurveyRepository {
  Future<List<Site>> getSites();

  Future<Site?> getSiteById(String id);

  /// Creates and persists a new site, returning the stored instance.
  Future<Site> createSite({required String name, List<String> blocks});

  Future<void> updateSite(Site site);

  /// Saves (or replaces) the Client inputs form for an existing site.
  Future<void> saveClientInputs(String siteId, ClientInputs inputs);
}
