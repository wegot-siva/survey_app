/// Central dropdown option lists for survey forms.
///
/// Defined ONCE here and reused across forms (Source points now, Inlet points
/// next slice) so the choices never drift between screens.
library;

enum SensorSize {
  dn25('DN25'),
  dn32('DN32'),
  dn40('DN40'),
  dn50('DN50'),
  dn100('DN100');

  const SensorSize(this.label);
  final String label;
}

enum SensorOd {
  od25('25mm'),
  od40('40mm'),
  od50('50mm'),
  od100('100mm');

  const SensorOd(this.label);
  final String label;
}

enum PipeSize {
  s25('25'),
  s32('32'),
  s40('40'),
  s50('50'),
  s100('100');

  const PipeSize(this.label);
  final String label;
}

enum PipeType {
  gi('GI'),
  cpvc('CPVC'),
  upvc('UPVC');

  const PipeType(this.label);
  final String label;
}

enum SensorType {
  wired('Wired'),
  wireless('Wireless');

  const SensorType(this.label);
  final String label;
}

enum FlowDirection {
  horizontal('Horizontal'),
  verticalDownToUp('Vertical-flow down to up'),
  verticalUpToDown('Vertical-flow up to down');

  const FlowDirection(this.label);
  final String label;
}
