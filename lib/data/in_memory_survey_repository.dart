import '../models/client_inputs.dart';
import '../models/duct_lora.dart';
import '../models/footer.dart';
import '../models/gateway.dart';
import '../models/inlet_point.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_photo.dart';
import '../services/id_service.dart';
import 'survey_repository.dart';

/// Phase 0 storage: everything lives in a map and is lost on restart.
/// Swappable for a real DB later — the UI only sees [SurveyRepository].
class InMemorySurveyRepository implements SurveyRepository {
  InMemorySurveyRepository(this._idService);

  final IdService _idService;
  final Map<String, Site> _sites = {};
  final Map<String, SourcePoint> _sourcePoints = {};
  final Map<String, InletPoint> _inletPoints = {};
  final Map<String, DuctLora> _ductLoras = {};
  final Map<String, Gateway> _gateways = {};
  final Map<String, Footer> _footers = {};
  final Map<String, MaterialMasterItem> _materialMasterItems = {};
  final Map<String, SurveyPhoto> _photos = {};

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
  Future<void> updateSiteBlocks(String siteId, List<String> blocks) async {
    final site = _sites[siteId];
    if (site == null) {
      throw StateError('Cannot update blocks: site "$siteId" not found.');
    }
    _sites[siteId] = site.copyWith(blocks: List.unmodifiable(blocks));
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

  @override
  Future<List<InletPoint>> getInletPoints(String siteId) async => _inletPoints
      .values
      .where((ip) => ip.siteId == siteId)
      .toList(growable: false);

  @override
  Future<InletPoint> addInletPoint(InletPoint inletPoint) async {
    final stored = inletPoint.copyWithId(_idService.newId());
    _inletPoints[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateInletPoint(InletPoint inletPoint) async {
    _inletPoints[inletPoint.id] = inletPoint;
  }

  @override
  Future<void> deleteInletPoint(String id) async {
    _inletPoints.remove(id);
  }

  @override
  Future<List<DuctLora>> getDuctLoras(String siteId) async => _ductLoras.values
      .where((d) => d.siteId == siteId)
      .toList(growable: false);

  @override
  Future<DuctLora> addDuctLora(DuctLora ductLora) async {
    final stored = ductLora.copyWithId(_idService.newId());
    _ductLoras[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateDuctLora(DuctLora ductLora) async {
    _ductLoras[ductLora.id] = ductLora;
  }

  @override
  Future<void> deleteDuctLora(String id) async {
    _ductLoras.remove(id);
  }

  @override
  Future<List<Gateway>> getGateways(String siteId) async => _gateways.values
      .where((g) => g.siteId == siteId)
      .toList(growable: false);

  @override
  Future<Gateway> addGateway(Gateway gateway) async {
    final stored = gateway.copyWithId(_idService.newId());
    _gateways[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateGateway(Gateway gateway) async {
    _gateways[gateway.id] = gateway;
  }

  @override
  Future<void> deleteGateway(String id) async {
    _gateways.remove(id);
  }

  @override
  Future<Footer?> getFooter(String siteId) async => _footers[siteId];

  @override
  Future<void> saveFooter(String siteId, Footer footer) async {
    if (!_sites.containsKey(siteId)) {
      throw StateError('Cannot save footer: site "$siteId" not found.');
    }
    _footers[siteId] = footer;
  }

  @override
  Future<List<MaterialMasterItem>> getMaterialMasterItems() async =>
      _materialMasterItems.values.toList(growable: false);

  @override
  Future<MaterialMasterItem> addMaterialMasterItem(
    MaterialMasterItem item,
  ) async {
    final stored = item.copyWithId(_idService.newId());
    _materialMasterItems[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateMaterialMasterItem(MaterialMasterItem item) async {
    _materialMasterItems[item.id] = item;
  }

  @override
  Future<void> deleteMaterialMasterItem(String id) async {
    _materialMasterItems.remove(id);
  }

  @override
  Future<List<SurveyPhoto>> getPhotos(String ownerType, String ownerId) async {
    final list =
        _photos.values
            .where((p) => p.ownerType == ownerType && p.ownerId == ownerId)
            .toList()
          ..sort((a, b) {
            final bySlot = a.slot.compareTo(b.slot);
            return bySlot != 0 ? bySlot : a.position.compareTo(b.position);
          });
    return List.unmodifiable(list);
  }

  @override
  Future<void> setPhotos(
    String ownerType,
    String ownerId,
    List<SurveyPhoto> photos,
  ) async {
    final keepIds = photos.where((p) => p.id.isNotEmpty).map((p) => p.id).toSet();
    _photos.removeWhere(
      (id, p) =>
          p.ownerType == ownerType &&
          p.ownerId == ownerId &&
          !keepIds.contains(id),
    );
    for (final photo in photos) {
      if (photo.id.isEmpty) {
        final stored = photo.copyWithId(_idService.newId());
        _photos[stored.id] = stored;
      } else {
        _photos[photo.id] = photo;
      }
    }
  }

  @override
  Future<List<SurveyPhoto>> getAllPhotos() async =>
      _photos.values.toList(growable: false);

  @override
  Future<void> updatePhoto(SurveyPhoto photo) async {
    _photos[photo.id] = photo;
  }
}
