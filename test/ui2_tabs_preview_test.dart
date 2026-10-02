// Design previews of the three tabs that load their own data — Nutrition,
// Workout, Wellness — plus the whole shell. `--dart-define=PREVIEW=true`
// writes them to test/_preview (untracked); without it the file is skipped.
//
// They read through AppState and the real repository over a throwaway,
// empty sqflite database, so what they show is each tab's first-run state: the
// state a new user meets, and the one most likely to look unfinished.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/coach/coach_config.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/state/locale_controller.dart';
import 'package:openstrap_edge/ui2/activity/day_strain.dart';
import 'package:openstrap_edge/ui2/profile/data.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart';
import 'package:openstrap_edge/ui2/profile/gestures.dart';
import 'package:openstrap_edge/ui2/profile/phone_import.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import 'support/app_type.dart';
import 'support/preview.dart';

Widget _app(AppState app, Widget child, {double? scale}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(Brightness.dark),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(scale ?? kPreviewScale)),
    child: child!,
  ),
  home: MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<LocaleController>.value(
        value: LocaleController.seed(null),
      ),
      ChangeNotifierProvider<UnitsController>.value(
        value: UnitsController.seed(UnitSystem.metric),
      ),
      ChangeNotifierProvider<CoachConfig>.value(value: CoachConfig()),
    ],
    child: child,
  ),
);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 40; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

// Synthetic readings for visual review only. Writes go to the disposable
// preview database; the application never imports this fixture.
class _PopulatedRepo extends LocalRepositoryImpl {
  _PopulatedRepo() : super(getProfileMap: () => const {});

  @override
  Future<Map<String, dynamic>> getToday() async => {
    ...await super.getToday(),
    'daily': {
      'calories_total': {'value': 2400, 'confidence': .8, 'tier': 'ESTIMATE'},
    },
  };

  @override
  Future<Map<String, dynamic>> getDayStress(String date) async => {
    ...await super.getDayStress(date),
    'stress': {'score': 34, 'level': 'low'},
  };
}

Future<void> _seed() async {
  final db = await LocalDb.instance;
  final now = DateTime.now();
  final date = todayLabel();
  for (var i = 0; i < 7; i++) {
    final day = DateTime(now.year, now.month, now.day - i);
    for (final (meal, hour, kcal) in [
      ('breakfast', 8, 480.0),
      ('lunch', 13, 720.0),
      ('dinner', 20, 850.0),
    ]) {
      await NutritionDb.put(
        db,
        FoodEntry(
          id: 'preview-$i-$meal',
          date: dayLabelOf(day),
          meal: meal,
          label: '$meal · sample log',
          kcal: kcal,
          proteinG: 30,
          carbsG: 80,
          fatG: 22,
          fibreG: 8,
          atTs:
              DateTime(
                day.year,
                day.month,
                day.day,
                hour,
              ).millisecondsSinceEpoch ~/
              1000,
        ),
      );
    }
  }
  final ts = now.millisecondsSinceEpoch ~/ 1000;
  await LocalDb.putSession({
    'id': 'preview-run',
    'start_ts': ts - 7200,
    'end_ts': ts - 4500,
    'type': 'Running',
    'status': 'complete',
    'duration_min': 45,
    'calories': 385,
    'strain': 10.4,
    'avg_hr': 142,
    'max_hr': 174,
    'steps': 5400,
    'created_at': ts,
  });
  await LocalDb.putBreathingSession(
    startedAt: ts - 3600,
    endedAt: ts - 3300,
    pattern: 'resonance',
    seconds: 300,
  );
  await _PopulatedRepo().postJournalMetrics(date, {
    'mood': const JournalMetricValue(4),
    'water_ml': const JournalMetricValue(1500),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppType();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_tabs_preview.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final tabs = <String, Widget>{
    'tab_nutrition': const Scaffold(body: SafeArea(child: NutritionScreen())),
    'tab_workout': const Scaffold(body: SafeArea(child: WorkoutScreen())),
    'tab_wellness': const Scaffold(body: SafeArea(child: WellnessScreen())),
    // Pushed screens, each its own Scaffold.
    'scr_journal': const JournalCompose(),
    'scr_breathing': const CalmBreathing(),
    'scr_log_food': const Scaffold(body: LogFoodSheet()),
    'scr_timeline': const DayTimelineScreen(),
    'scr_ecg': const EcgHomeScreen(),
    'scr_naps': const NapsScreen(),
    'scr_day_strain': const DayStrainDetail(),
    'scr_coach_setup': const CoachSetup(),
    'scr_coach': const CoachScreen(),
    'scr_data': const DataScreen(),
    'scr_phone_import': const PhoneImport(),
    'scr_gestures': const BandGestures(),
    'scr_my_devices': const MyDevices(),
    'scr_signal_priority': const SignalPriorityScreen(),
  };

  group('preview', () {
    tabs.forEach((name, screen) {
      if (!previewWants(name)) return;
      testWidgets(name, (t) async {
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        app.repo = LocalRepositoryImpl(getProfileMap: () => const {});
        final key = GlobalKey();
        t.view.physicalSize = const Size(390 * 2, 2600 * 2);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        await t.pumpWidget(RepaintBoundary(key: key, child: _app(app, screen)));
        await _settle(t);
        await savePreview(t, key, name);
      });
    });
  }, skip: !kPreview);

  group('populated preview', () {
    for (final (name, screen, tab) in <(String, Widget, String?)>[
      ('nutrition_today', const NutritionScreen(), null),
      ('nutrition_week', const NutritionScreen(), 'Week'),
      ('nutrition_goals', const NutritionScreen(), 'Goals'),
      ('workout_history', const WorkoutScreen(), 'History'),
      ('wellness_mind', const WellnessScreen(), null),
      ('wellness_habits', const WellnessScreen(), 'Habits'),
    ]) {
      if (!previewWants(name)) continue;
      testWidgets(name, (t) async {
        await t.runAsync(_seed);
        final app = AppState.forTesting()..repo = _PopulatedRepo();
        addTearDown(app.dispose);
        final key = GlobalKey();
        t.view.physicalSize = const Size(390 * 2, 2600 * 2);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: _app(app, Scaffold(body: SafeArea(child: screen)),
                scale: kPreview ? kPreviewScale : 3.1),
          ),
        );
        await _settle(t);
        if (tab != null) {
          for (
            var i = 0;
            i < 5 && find.text(tab).hitTestable().evaluate().isEmpty;
            i++
          ) {
            await t.drag(find.byType(SubTabs), const Offset(-180, 0));
            await t.pumpAndSettle();
          }
          expect(find.text(tab).hitTestable(), findsOneWidget);
          await t.tap(find.text(tab).first);
          await _settle(t);
        }
        expect(t.takeException(), isNull);
        if (kPreview) await savePreview(t, key, 'populated_$name');
      });
    }
  });

  for (final (name, screen) in <(String, Widget)>[
    ('journal', const JournalCompose()),
    ('breathing', const CalmBreathing()),
  ]) {
    testWidgets('$name fits at 3.1x text', (t) async {
      final app = AppState.forTesting()
        ..repo = LocalRepositoryImpl(getProfileMap: () => const {});
      addTearDown(app.dispose);
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(app, screen, scale: 3.1));
      await _settle(t);
      expect(t.takeException(), isNull);
    });
  }
}
