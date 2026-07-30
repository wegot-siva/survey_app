/// One row of a site's block list, with a stable client-generated id that
/// survives sync round-trips — see Full sync Group 1's blocks-push fix.
/// Internal to the repository/sync layer: the public [Site.blocks] surface
/// stays a plain label list (see [Site]'s own doc), since neither the UI
/// nor any consumer needs a block's identity, only its content.
class Block {
  const Block({
    required this.id,
    required this.siteId,
    required this.position,
    required this.label,
  });

  final String id;
  final String siteId;
  final int position;
  final String label;
}
