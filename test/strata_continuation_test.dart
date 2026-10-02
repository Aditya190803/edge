import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/app_type.dart';
import 'support/preview.dart';

const _day = '2026-09-25';
const _burned = Metric(value: 2400, confidence: .8, tier: MetricTier.estimate);

FoodEntry _food(String id, double? kcal) =>
    FoodEntry(id: id, date: _day, meal: 'lunch', label: id, kcal: kcal);

Widget _frame(Widget child, double scale) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(Brightness.dark),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

List<StrataBand> _bands(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<StrataBand>()
    .toList();

void main() {
  setUpAll(loadAppType);

  for (final scale in [1.0, 3.1]) {
    for (final scenario in ['complete', 'floor', 'unknown', 'zero']) {
      testWidgets('nutrition $scenario retains amounts and bounds at $scale', (
        t,
      ) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final entries = switch (scenario) {
          'floor' => [_food('known', 1200), _food('unknown', null)],
          'unknown' => [_food('unknown', null)],
          'zero' => [_food('zero', 0)],
          _ => [_food('known', 1200)],
        };
        final widget = DayEnergyCard(
          day: rollupDay(_day, entries, today: _day),
          burned: _burned,
        );
        await t.pumpWidget(_frame(widget, scale));
        expect(t.takeException(), isNull);
        expect(find.text('2400 kcal'), findsOneWidget);
        if (scenario == 'unknown') {
          expect(_bands(t), isEmpty);
          expect(find.text('BALANCE'), findsNothing);
          expect(find.text('LOGGED TODAY'), findsOneWidget);
        } else {
          expect(_bands(t).map((b) => b.frac), [
            scenario == 'zero' ? 0.0 : .5,
            1.0,
          ]);
          expect(
            find.text(scenario == 'floor' ? 'BALANCE AT LEAST' : 'BALANCE'),
            findsOneWidget,
          );
          expect(
            find.text('At least'),
            scenario == 'floor' ? findsOneWidget : findsNothing,
          );
        }
        if (kPreview) {
          await shoot(t, _frame(widget, scale), 'nutrition_${scenario}_$scale');
        }
      });
    }
  }

  testWidgets('nutrition draws no comparative scale without a burned reading', (
    t,
  ) async {
    await t.pumpWidget(
      _frame(
        DayEnergyCard(
          day: rollupDay(_day, [_food('known', 1200)], today: _day),
        ),
        1,
      ),
    );
    expect(_bands(t), isEmpty);
    expect(find.text('BURNED'), findsNothing);
  });

  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'health shows lead values once and keeps their source date at $scale',
      (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        const data = HealthData(
          today: {
            'status': {'showing_prior_overnight': true, 'overnight_day': _day},
            'daily': {
              'resting_hr': {'value': 52, 'confidence': .8, 'tier': 'HIGH'},
            },
            'hrv': {'rmssd': 68, 'confidence': .8},
          },
        );
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(body: HealthScreen(data: data)),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('52'), findsOneWidget);
        expect(find.text('68'), findsOneWidget);
        expect(find.text('RESTING HEART RATE'), findsOneWidget);
        expect(find.text('Resting heart rate'), findsNothing);
        expect(find.textContaining('Overnight ·'), findsOneWidget);
        expect(find.textContaining('RMSSD, asleep ·'), findsOneWidget);
      },
    );

    testWidgets('cycle unknown phase stays unknown and count fits at $scale', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const widget = CycleTab(data: CycleData(enabled: true, cycleDay: 31));
      await t.pumpWidget(_frame(widget, scale));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('31'), findsOneWidget);
      expect(find.text('counted from your last logged start'), findsOneWidget);
      if (kPreview) {
        await shoot(t, _frame(widget, scale), 'cycle_current_$scale');
      }
    });
  }

  testWidgets('journal mood can still be selected and cleared', (t) async {
    int? mood;
    await t.pumpWidget(
      _frame(
        StatefulBuilder(
          builder: (c, setState) => MoodPicker(
            value: mood,
            onChanged: (v) => setState(() => mood = v),
          ),
        ),
        1,
      ),
    );
    await t.tap(find.bySemanticsLabel('Mood 3 of 5'));
    await t.pumpAndSettle();
    expect(mood, 3);
    await t.tap(
      find.bySemanticsLabel('Mood 3 of 5, selected. Activate to clear.'),
    );
    await t.pumpAndSettle();
    expect(mood, isNull);
    expect(find.text('Not answered yet'), findsOneWidget);
  });
}
