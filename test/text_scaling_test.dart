// Tests for the text-scale work (UI audit P1, item 5).
//
// ## An important correction to the audit's premise
//
// The audit claimed hardcoded `fontSize:` "breaks text scaling". That is
// true on the web, but NOT in Flutter: `Text` applies
// `MediaQuery.textScaler` to whatever size its style carries, so
// `TextStyle(fontSize: 20)` still doubles when the OS font setting doubles.
// Measured directly before changing anything: a hardcoded 20px line
// rendered 29px tall at 1x and 57px at 2x.
//
// So moving AppTextStyles onto the TextTheme is a *consistency* win — one
// type scale, honoured everywhere, responding to theme changes — not an
// accessibility fix, and these tests do not pretend otherwise.
//
// The real large-text risk is layout: text that grows inside a box that
// doesn't. That is what the overflow tests below actually guard, and it is
// independent of where the font size came from.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/models/site.dart';
import 'package:survey_app/models/source_point.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/ui/source_points_list_screen.dart';
import 'package:survey_app/ui/theme/app_theme.dart';
import 'package:survey_app/ui/widgets/load_error_view.dart';
import 'package:survey_app/ui/widgets/photo_capture_field.dart';

/// Renders [child] under a given [TextScaler], the way the OS font-size
/// setting reaches a real app.
Widget _scaled(Widget child, {required double scale}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: child),
  ),
);

/// Pumps [child] at [scale] and returns any overflow errors Flutter raised.
///
/// Overflow is reported through [FlutterError.onError] rather than thrown,
/// so it has to be captured deliberately — a plain `pumpWidget` stays green
/// while the user looks at a yellow-and-black striped bar.
Future<List<String>> _overflowsAt(
  WidgetTester tester,
  Widget child, {
  required double scale,
}) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  await tester.pumpWidget(_scaled(child, scale: scale));
  await tester.pump();
  FlutterError.onError = previous;
  return errors
      .where((e) => e.toLowerCase().contains('overflow'))
      .toList(growable: false);
}

void main() {
  group('AppTextStyles', () {
    testWidgets('resolve from the ambient TextTheme, not fixed sizes', (
      tester,
    ) async {
      late TextStyle? title;
      late TextStyle? subtitle;
      late TextStyle? label;
      late TextTheme textTheme;

      await tester.pumpWidget(
        _scaled(
          Builder(
            builder: (context) {
              textTheme = Theme.of(context).textTheme;
              title = AppTextStyles.title(context);
              subtitle = AppTextStyles.subtitle(context);
              label = AppTextStyles.label(context);
              return const SizedBox();
            },
          ),
          scale: 1,
        ),
      );

      // Compared against the theme as resolved in a real context: ThemeData's
      // raw textTheme leaves fontSize null until it is.
      expect(title?.fontSize, textTheme.titleLarge?.fontSize);
      expect(title?.fontWeight, FontWeight.w600);
      expect(subtitle?.fontSize, textTheme.titleMedium?.fontSize);
      expect(label?.fontSize, textTheme.bodyMedium?.fontSize);
      expect(
        [title, subtitle, label].map((s) => s?.fontSize),
        everyElement(isNotNull),
      );
    });
  });

  group('layouts hold at the largest text setting', () {
    // 2.0 is past Android's largest accessibility step, so anything that
    // survives here survives every real device setting.
    const largest = 2.0;

    testWidgets('the photo field, whose thumbnails are a fixed 96px box', (
      tester,
    ) async {
      final field = MultiPhotoCaptureField(
        label: 'Site photos',
        // A photo still downloading renders the placeholder that carries
        // text inside that fixed box — the tightest spot in this widget.
        photos: const [PhotoView(null)],
        onAdded: (_) {},
        onRemoved: (_) {},
      );

      expect(await _overflowsAt(tester, field, scale: 1), isEmpty);
      expect(await _overflowsAt(tester, field, scale: largest), isEmpty);
    });

    testWidgets('the load-failure screen', (tester) async {
      final view = LoadErrorView(
        onRetry: () {},
        details: StateError('database is locked'),
      );

      expect(await _overflowsAt(tester, view, scale: 1), isEmpty);
      expect(await _overflowsAt(tester, view, scale: largest), isEmpty);
    });

    testWidgets('a point list row with the "Incomplete" badge', (tester) async {
      final repository = InMemorySurveyRepository(IdService());
      final Site site = await repository.createSite(name: 'Scaling Site');
      // A point with no apartment recorded is what shows the badge, so the
      // row carries title, badge and subtitle all on one line.
      await repository.addSourcePoint(
        SourcePoint(id: '', siteId: site.id),
      );

      final screen = SourcePointsListScreen(
        repository: repository,
        site: site,
      );

      // Pumped inside its own Scaffold via _scaled; the screen brings its
      // own, which nests harmlessly.
      final atNormal = await _overflowsAt(tester, screen, scale: 1);
      await tester.pumpAndSettle();
      expect(atNormal, isEmpty);

      final atLargest = await _overflowsAt(tester, screen, scale: largest);
      await tester.pumpAndSettle();
      expect(atLargest, isEmpty);
    });
  });
}
