/// A captured photo linked to any survey record (photo slice 2).
///
/// Polymorphic + slot-based so one table serves every photo field across
/// source/inlet/gateway/footer: ([ownerType], [ownerId]) identifies the parent
/// record, [slot] names the field. Fixed-slot fields keep one row per slot;
/// the Footer's "site media" uses many rows in the same slot, ordered by
/// [position]. (Duct LoRa's placement photo predates this and stays on its own
/// columns — see [DuctLora].)
///
/// Offline-first, mirroring the Duct LoRa photo: [localPath] is set on capture;
/// [remotePath] (the Storage object key) is filled in by sync after upload.
class SurveyPhoto {
  const SurveyPhoto({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.slot,
    this.position = 0,
    this.localPath,
    this.remotePath,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;
  final String ownerType;
  final String ownerId;
  final String slot;
  final int position;
  final String? localPath;
  final String? remotePath;

  SurveyPhoto copyWithId(String newId) => SurveyPhoto(
    id: newId,
    ownerType: ownerType,
    ownerId: ownerId,
    slot: slot,
    position: position,
    localPath: localPath,
    remotePath: remotePath,
  );

  /// Returns a copy carrying the Storage object key of a just-uploaded photo.
  SurveyPhoto withRemotePath(String path) => SurveyPhoto(
    id: id,
    ownerType: ownerType,
    ownerId: ownerId,
    slot: slot,
    position: position,
    localPath: localPath,
    remotePath: path,
  );
}

/// Owner-type tokens stored in [SurveyPhoto.ownerType].
class PhotoOwner {
  const PhotoOwner._();

  static const sourcePoint = 'source_point';
  static const inletPoint = 'inlet_point';
  static const gateway = 'gateway';
  static const footer = 'footer';
}

/// Slot tokens stored in [SurveyPhoto.slot], grouped by owner.
class PhotoSlot {
  const PhotoSlot._();

  // Source point
  static const inletMarked = 'inlet_marked';
  static const powerSource = 'power_source';
  static const wiringRouting = 'wiring_routing';
  static const antennaRouting = 'antenna_routing';

  // Inlet point
  static const shaftLocationMarked = 'shaft_location_marked';
  static const cableRouting = 'cable_routing';
  static const shaftAccess = 'shaft_access';
  static const shaftInternal = 'shaft_internal';

  // Gateway
  static const gatewayLocation = 'location';

  // Footer (multiple photos share this slot)
  static const siteMedia = 'site_media';
}
