import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/start_card.dart';
import 'package:openstrap_edge/ui2/theme.dart';

import 'support/app_type.dart';

/// This card was built blind once and shipped three defects a rendered check
/// would have caught immediately: a negative `Container.margin` (Flutter
/// asserts `margin.isNonNegative`), artwork stacked UNDER the copy, and
/// `'\$count activities'` with the dollar escaped, which printed the literal
/// text to the user. The Strata card has no artwork, but the other two
/// failure shapes are still worth pinning.
///
/// It is excluded from the gallery on purpose — a full-width card cannot be
/// photographed in a ~179 px component cell without the fixture, not the card,
/// being what the golden shows. This stands in for that.
void main() {
  setUpAll(loadAppType);

  Future<void> pump(WidgetTester t, {double scale = 1.0}) async {
    t.view.physicalSize = const Size(390 * 2, 600 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(builder: (c) {
          // COPY the ambient MediaQuery and override only the scale. Building
          // a bare MediaQueryData here sets `size` to zero, which rendered the
          // card at 0 width — a green test about a card nobody can see.
          return MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            // The real parent: a scrolling list with the usual gutter.
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: const [
                StartCard(
                  label: 'START A SESSION',
                  count: 71,
                  noun: 'activities',
                  accent: C.domMove,
                ),
              ],
            ),
          );
        }),
      ),
    ));
  }

  testWidgets('it builds inside a scroll view', (t) async {
    await pump(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('the count is interpolated, not printed literally', (t) async {
    await pump(t);
    expect(find.text('71'), findsOneWidget);
    expect(find.text('activities'), findsOneWidget);
    expect(find.textContaining(r'$count'), findsNothing);
  });

  testWidgets('it fills the width its list gives it', (t) async {
    await pump(t);
    expect(t.getSize(find.byType(StartCard)).width, 390 - 32);
  });

  testWidgets('the default subline is there', (t) async {
    await pump(t);
    expect(find.text('Pick one and go'), findsOneWidget);
  });

  testWidgets('nothing overflows at 2.0x or 3.1x text', (t) async {
    for (final scale in const [2.0, 3.1]) {
      await pump(t, scale: scale);
      expect(t.takeException(), isNull, reason: 'at ${scale}x');
    }
  });

  testWidgets('the wellness card is the same component, its own colour',
      (t) async {
    t.view.physicalSize = const Size(390 * 2, 600 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: ListView(children: const [
          StartCard(
            label: 'START A SITTING',
            count: 3,
            noun: 'exercises',
            accent: C.domMind,
          ),
        ]),
      ),
    ));
    expect(t.takeException(), isNull);
    // The count is what the picker offers, not what the tab contains.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('exercises'), findsOneWidget);
    expect(find.text('START A SITTING'), findsOneWidget);
  });
}
