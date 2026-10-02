// Page previews for design review — `--dart-define=PREVIEW=true`.
//
// Writes each case to test/_preview/<name>.png (untracked) at phone width and
// the full scroll height of the page, so a reviewer sees the whole screen
// rather than the first viewport. Off by default: CI never writes files.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const kPreview = bool.fromEnvironment('PREVIEW');

/// Only cases whose name contains this run (`--dart-define=ONLY=home`).
const kOnly = String.fromEnvironment('ONLY');

/// Text scale for previews (`--dart-define=SCALE=3.1`), to see overflow.
final kPreviewScale =
    double.tryParse(const String.fromEnvironment('SCALE')) ?? 1.0;

bool previewWants(String name) => kOnly.isEmpty || name.contains(kOnly);

Future<void> savePreview(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('test/_preview/$name.png')..createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Grows the view to the page's full scroll height (capped) so a ListView
/// renders top to bottom in one picture.
Future<void> growToContent(WidgetTester tester, {double width = 390}) async {
  var h = 844.0;
  for (var i = 0; i < 3; i++) {
    final scrollables = find.byType(Scrollable).evaluate();
    var extra = 0.0;
    for (final e in scrollables) {
      final s = (e as StatefulElement).state as ScrollableState;
      if (s.axisDirection == AxisDirection.down) {
        final p = s.position;
        if (p.hasContentDimensions && p.maxScrollExtent > extra) {
          extra = p.maxScrollExtent;
        }
      }
    }
    if (extra <= 0) break;
    h = (h + extra).clamp(844.0, 6000.0);
    tester.view.physicalSize = Size(width * 2, h * 2);
    await tester.pumpAndSettle();
  }
}

final _previewKey = GlobalKey();

/// Pump [framed] (a whole MaterialApp) at phone size, grow it to its content
/// and write it out. The boundary wraps the app, so a page that is its own
/// Scaffold is captured the same way as a bare component.
Future<void> shoot(WidgetTester tester, Widget framed, String name) async {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(key: _previewKey, child: framed));
  await tester.pumpAndSettle();
  await growToContent(tester);
  await savePreview(tester, _previewKey, name);
}
