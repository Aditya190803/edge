// The row that goes off the edge, and the thing that says so.
//
// Two halves. The first is the measurement that justifies the affordance at
// all — the Wellness and Health tab sets against the width they actually get
// on the three phone sizes we ship to, at the four text scales the design
// system claims to survive. Those numbers are the reason `ScrollHint` exists
// and the reason the alternative (make it fit) was refused, so they are
// asserted rather than written in a comment nobody re-runs.
//
// The second is the honesty contract: absent when the content fits, present
// when it does not, gone at the end of the scroll.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// The type the app ships. Without it the harness measures its fallback
/// glyphs, and a width assertion against the wrong font is a width assertion
/// against nothing.
Future<void> _loadType() async {
  // The one bundled family, so a golden shows the type the app ships.
  for (final e in const {
    'Figtree': 'assets/fonts/Figtree',
  }.entries) {
    final loader = FontLoader(e.key);
    for (final f in Directory(e.value)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))) {
      loader.addFont(f
          .readAsBytes()
          .then((b) => ByteData.sublistView(Uint8List.fromList(b))));
    }
    await loader.load();
  }
}

/// One `SubTabs` chip: the label at its own weight, plus S.x4 of padding on
/// each side, floored at the 44 pt tap minimum.
double _chip(String label, double scale, {required bool active}) {
  final t = TextPainter(
    text: TextSpan(
      text: label,
      style:
          F.cap.copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w500),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  final w = t.width + 2 * S.x4;
  return w < S.tap ? S.tap : w;
}

/// The row's laid-out width: the control's 3 pt inset each side, every chip,
/// and the 2 pt seam between segments.
double _row(List<String> labels, double scale, {double pad = S.x4}) {
  var w = 6.0 + 2.0 * (labels.length - 1);
  for (var i = 0; i < labels.length; i++) {
    final c = _chip(labels[i], scale, active: i == 0);
    w += pad == S.x4 ? c : c - 2 * (S.x4 - pad);
  }
  return w;
}

const _wellness = ['Mind', 'Recovery', 'Habits', 'Medication', 'Cycle'];
const _health = ['Overview', 'Explore', 'Trends', 'Vitals', 'Labs'];

/// Screen width minus the S.x4 gutter each side that every screen holding a
/// `SubTabs` puts around it.
double _viewport(double screen) => screen - 2 * S.x4;

Widget _harness(Widget child, {double scale = 1.0}) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: SizedBox(height: S.tap, child: ScrollHint(child: child)),
            ),
          ),
        ),
      ),
    );

ListView _pills(int n) => ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: n,
      separatorBuilder: (_, _) => const SizedBox(width: S.x2),
      itemBuilder: (_, i) => Pill('Tab $i', C.blue),
    );

/// A phone, not the 800 pt default surface. The whole question is what fits,
/// so the width the widgets are handed has to be a width we ship to.
void _phone(WidgetTester t, [double width = 390]) {
  t.view.physicalSize = Size(width * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(_loadType);

  group('the five-tab rows do not fit, at any width we ship to', () {
    // 360 is the Android floor we design against, 390 is the iPhone the app is
    // developed on, 430 is the largest phone. If the row fitted on any of
    // them the honest fix would be to stop it scrolling, not to decorate it.
    // Barlow is narrower than the face this was first measured in, and the
    // segmented control seams its segments with 2 pt rather than 8: both
    // five-tab rows now fit the widest phone at 1.0x, and only there. The
    // hint still earns its place on the two sizes most people hold.
    for (final screen in const [360.0, 390.0]) {
      test('${screen.toInt()} pt, 1.0x text', () {
        final vp = _viewport(screen);
        expect(_row(_wellness, 1.0), greaterThan(vp),
            reason: 'Wellness fits — drop ScrollHint rather than ship it');
        expect(_row(_health, 1.0), greaterThan(vp),
            reason: 'Health fits — drop ScrollHint rather than ship it');
      });
    }

    test('at accessibility text sizes it is not close', () {
      for (final scale in const [1.5, 2.0, 3.1]) {
        for (final labels in const [_wellness, _health]) {
          expect(_row(labels, scale), greaterThan(_viewport(430)),
              reason: 'even the widest phone at ${scale}x');
        }
      }
    });
  });

  group('the last tab is cut without help', () {
    // What the owner actually saw: on the narrowest phone the fifth segment
    // is more than half past the edge, so the row reads as ending at the
    // fourth unless something says otherwise. At 390 it is clipped, not
    // hidden — still enough for a hint that draws nothing once it fits.
    for (final labels in const [_wellness, _health]) {
      test('${labels.last} is mostly hidden at 360 pt', () {
        final chip = _chip(labels.last, 1.0, active: false);
        final hidden = _row(labels, 1.0) - _viewport(360);
        expect(hidden, greaterThan(chip / 2),
            reason: '${labels.last} hides ${hidden.toStringAsFixed(1)} pt '
                'of ${chip.toStringAsFixed(1)}');
      });
      test('${labels.last} is clipped at 390 pt', () {
        expect(_row(labels, 1.0) - _viewport(390), greaterThan(0));
      });
    }
  });

  group('ScrollHint is honest', () {
    testWidgets('draws nothing at all when the content fits', (t) async {
      _phone(t);
      await t.pumpWidget(_harness(_pills(2)));
      await t.pumpAndSettle();
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
    });

    testWidgets('marks the edge when the content does not fit', (t) async {
      _phone(t);
      await t.pumpWidget(_harness(_pills(12)));
      await t.pumpAndSettle();
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    });

    testWidgets('and is gone once you reach the end', (t) async {
      _phone(t);
      await t.pumpWidget(_harness(_pills(12)));
      await t.pumpAndSettle();
      await t.fling(find.byType(ScrollHint), const Offset(-2000, 0), 4000);
      await t.pumpAndSettle();
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
    });

    // The bug the first draft of this widget shipped, caught here rather than
    // on a phone. Lifting the mask off the tree when the hint has nothing to
    // say moves the scrollable to a different slot, which remounts it on a
    // fresh ScrollPosition at offset 0 — so reaching the end of the row threw
    // you back to the start of it, and the hint reappeared because there was
    // once again content off the edge. The row must not move when the hint
    // goes away.
    testWidgets('keeps its place when the hint goes away', (t) async {
      _phone(t);
      await t.pumpWidget(_harness(_pills(12)));
      await t.pumpAndSettle();
      await t.fling(find.byType(ScrollHint), const Offset(-2000, 0), 4000);
      await t.pumpAndSettle();
      final at = t.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(at.extentAfter, 0, reason: 'the row sprang back to the start');
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
    });

    testWidgets('appears when a text size pushes a fitting row over',
        (t) async {
      _phone(t);
      await t.pumpWidget(_harness(_pills(4)));
      await t.pumpAndSettle();
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
      await t.pumpWidget(_harness(_pills(4), scale: 3.1));
      await t.pumpAndSettle();
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    });

    testWidgets('never takes a tap from the chip underneath', (t) async {
      _phone(t);
      var tapped = -1;
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(),
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: S.tap,
                child: ScrollHint(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 6,
                    separatorBuilder: (_, _) => const SizedBox(width: S.x2),
                    itemBuilder: (_, i) => Pressable(
                      onTap: () => tapped = i,
                      child: SizedBox(
                          width: 300,
                          child: Center(child: Pill('Tab $i', C.blue))),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      // The last pixel of the row, where the chevron sits. The items are wide
      // enough that this cannot land in a separator, so a miss here is the
      // overlay eating the touch and nothing else.
      final box = t.getRect(find.byType(ScrollHint));
      await t.tapAt(Offset(box.right - 1, box.center.dy));
      await t.pumpAndSettle();
      expect(tapped, isNot(-1), reason: 'the overlay swallowed the tap');
    });
  });
}
