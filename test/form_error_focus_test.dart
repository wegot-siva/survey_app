// Tests for FormErrorFocus — the helper that takes the user to the first
// field left in error by a failed save.
//
// The case that matters is the one that motivated it: the invalid field is
// far enough above the Save button to be completely off-screen when Save is
// pressed. A test that only checks an already-visible field would pass just
// as happily with no implementation at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/ui/widgets/form_error_focus.dart';
import 'package:survey_app/ui/widgets/form_fields.dart';

/// A stand-in with the same shape as the real survey forms: a tall
/// SingleChildScrollView + Column of [AppTextField]s, errors assigned in
/// setState on save, Save at the very bottom.
class _Harness extends StatefulWidget {
  const _Harness({required this.fieldCount, required this.invalidIndexes});

  final int fieldCount;
  final Set<int> invalidIndexes;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _formRoot = GlobalKey();
  late final List<TextEditingController> _controllers = [
    for (var i = 0; i < widget.fieldCount; i++) TextEditingController(),
  ];
  final _errors = <int, String?>{};

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    setState(() {
      for (var i = 0; i < widget.fieldCount; i++) {
        _errors[i] = widget.invalidIndexes.contains(i) ? 'Required' : null;
      }
    });
    FormErrorFocus.revealFirst(_formRoot);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            key: _formRoot,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.fieldCount; i++)
                AppTextField(
                  controller: _controllers[i],
                  label: 'Field $i',
                  errorText: _errors[i],
                ),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}

/// How far the scrollable has been scrolled from the top.
double _offset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

/// Whether [finder]'s widget currently sits inside the viewport.
///
/// Geometry rather than : these labels live inside an
/// [InputDecorator], whose own pointer area swallows the hit test, so a
/// perfectly visible label reports as un-hit-testable.
bool _onScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final view = tester.view;
  final height = view.physicalSize.height / view.devicePixelRatio;
  return rect.bottom > 0 && rect.top < height;
}

void main() {
  testWidgets('scrolls an off-screen invalid field back into view', (
    tester,
  ) async {
    // 30 fields puts field 1 far above the fold on any test surface.
    await tester.pumpWidget(
      const _Harness(fieldCount: 30, invalidIndexes: {1}),
    );

    // Get to Save at the bottom, exactly as a user filling the form would.
    await tester.dragUntilVisible(
      find.text('Save'),
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    final scrolledDown = _offset(tester);
    expect(scrolledDown, greaterThan(0));
    // Not findsNothing: SingleChildScrollView builds every child, which is
    // exactly why the walk can see them. hitTestable is what distinguishes
    // "built" from "actually on screen".
    expect(
      _onScreen(tester, find.text('Field 1')),
      isFalse,
      reason: 'the field must be off-screen for this test to mean anything',
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      _offset(tester),
      lessThan(scrolledDown),
      reason: 'a failed save should scroll back up to the offending field',
    );
    expect(_onScreen(tester, find.text('Field 1')), isTrue);
  });

  testWidgets('picks the topmost error, not just any error', (tester) async {
    await tester.pumpWidget(
      const _Harness(fieldCount: 30, invalidIndexes: {4, 20}),
    );

    await tester.dragUntilVisible(
      find.text('Save'),
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Field 4 is the first error in document order; field 20 is nearer the
    // Save button, so landing on 20 would mean the walk stopped at whatever
    // happened to be closest rather than the topmost.
    expect(_onScreen(tester, find.text('Field 4')), isTrue);
  });

  testWidgets('focuses the revealed field so typing goes straight into it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _Harness(fieldCount: 30, invalidIndexes: {2}),
    );

    await tester.dragUntilVisible(
      find.text('Save'),
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final focused = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .where((e) => e.focusNode.hasFocus);
    expect(focused, hasLength(1));
    expect(focused.single.controller.text, isEmpty);
  });

  testWidgets('a clean save scrolls nowhere', (tester) async {
    await tester.pumpWidget(
      const _Harness(fieldCount: 30, invalidIndexes: {}),
    );

    await tester.dragUntilVisible(
      find.text('Save'),
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    final before = _offset(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(_offset(tester), before);
  });
}
