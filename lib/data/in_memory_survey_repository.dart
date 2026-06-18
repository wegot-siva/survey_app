import '../models/client_inputs.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../services/id_service.dart';
import 'survey_repository.dart';

/// Phase 0 storage: everything lives in a map and is lost on restart.
/// Swappable for a real DB later — the UI only sees [SurveyRepository].
class InMemorySurveyRepository implements SurveyRepository {
  InMemorySurveyRepository(this._idService);

  final IdService _idService;
  final Map<String, Site> _sites = {};
  final Map<String, SourcePoint> _sourcePoints = {};

  @override
  Future<List<Site>> getSites() async => _sites.values.toList(growable: false);

  @override
  Future<Site?> getSiteById(String id) async => _sites[id];

  @override
  Future<Site> createSite({
    required String name,
    List<String> blocks = const [],
  }) async {
    final site = Site(
      id: _idService.newId(),
      name: name,
      blocks: List.unmodifiable(blocks),
    );
    _sites[site.id] = site;
    return site;
  }

  @override
  Future<void> updateSite(Site site) async {
    _sites[site.id] = site;
  }

  @override
  Future<void> saveClientInputs(String siteId, ClientInputs inputs) async {
    final site = _sites[siteId];
    if (site == null) {
      throw StateError('Cannot save client inputs: site "$siteId" not found.');
    }
    _sites[siteId] = site.copyWith(clientInputs: inputs);
  }

  @override
  Future<List<SourcePoint>> getSourcePoints(String siteId) async => _sourcePoints
      .values
      .where((sp) => sp.siteId == siteId)
      .toList(growable: false);

  @override
  Future<SourcePoint> addSourcePoint(SourcePoint sourcePoint) async {
    final stored = sourcePoint.copyWithId(_idService.newId());
    _sourcePoints[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateSourcePoint(SourcePoint sourcePoint) async {
    _sourcePoints[sourcePoint.id] = sourcePoint;
  }

  @override
  Future<void> deleteSourcePoint(String id) async {
    _sourcePoints.remove(id);
  }
}
