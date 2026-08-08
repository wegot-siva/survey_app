// A photo whose metadata has synced but whose image is still downloading must
// be SHOWN, not hidden.
//
// Every form used to build its display list as
// `if (d.localPath != null) PhotoView(d.localPath!, ...)` while its callbacks
// indexed the unfiltered model list. That is a wrong-photo-deletion bug: with
// drafts [A(pending), B, C] the widget shows [B, C], so tapping remove on C
// passes index 1, and the screen removes the model's index 1 — which is B.
//
// It stayed nearly unreachable only because photo downloads used to block the
// pull, so by the time any form opened, every pulled photo already had a
// file. Deferring downloads to a background pass removes exactly that
// protection and makes the pending state routine, which is why these tests
// arrived with that change.
//
// The fix is to keep the displayed list 1:1 with the model list, so an index
// always means the same photo. These tests pin that property on the shared
// widget; the screens' half of it is passing an unfiltered list.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/ui/widgets/photo_capture_field.dart';

Widget _host({
  required List<PhotoView> photos,
  ValueChanged<int>? onRemoved,
  ValueChanged<int>? onEdit,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MultiPhotoCaptureField(
        label: 'Photos',
        photos: photos,
        onAdded: (_) {},
        onRemoved: onRemoved ?? (_) {},
        onEdit: onEdit,
      ),
    ),
  );
}

void main() {
  testWidgets('a photo still downloading renders a placeholder rather than '
      'vanishing', (tester) async {
    await tester.pumpWidget(_host(photos: const [
      PhotoView(null, uploaded: true),
    ]));
    await tester.pump();

    expect(find.text('Downloading'), findsOneWidget);
  });

  testWidgets('remove passes the index of the photo actually tapped, even '
      'behind a pending one', (tester) async {
    final removed = <int>[];
    // Model order: 0 pending, 1 real, 2 real. Under the old filtering the
    // widget only rendered indices 1 and 2 as positions 0 and 1, so tapping
    // the LAST thumbnail reported 1 and the screen deleted the middle photo.
    await tester.pumpWidget(_host(
      photos: const [
        PhotoView(null, uploaded: true),
        PhotoView('/tmp/b.jpg', uploaded: true),
        PhotoView('/tmp/c.jpg', uploaded: true),
      ],
      onRemoved: removed.add,
    ));
    await tester.pump();

    final closes = find.byIcon(Icons.close);
    expect(closes, findsNWidgets(3),
        reason: 'all three photos are removable, including the pending one');

    await tester.tap(closes.last, warnIfMissed: false);
    await tester.pump();

    expect(removed, [2],
        reason: 'the last thumbnail is model index 2, not 1');
  });

  testWidgets('a pending photo offers no edit affordance — there is no file '
      'to mark up', (tester) async {
    final edited = <int>[];
    await tester.pumpWidget(_host(
      photos: const [
        PhotoView(null, uploaded: true),
        PhotoView('/tmp/b.jpg', uploaded: true),
      ],
      onEdit: edited.add,
    ));
    await tester.pump();

    expect(find.byIcon(Icons.edit), findsOneWidget,
        reason: 'only the downloaded photo is editable');
  });

  testWidgets('a fully downloaded set shows no placeholder', (tester) async {
    await tester.pumpWidget(_host(photos: const [
      PhotoView('/tmp/a.jpg', uploaded: true),
      PhotoView('/tmp/b.jpg', uploaded: true),
    ]));
    await tester.pump();

    expect(find.text('Downloading'), findsNothing);
  });
}
