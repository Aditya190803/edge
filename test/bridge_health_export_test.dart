import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/health/bridge_health_export.dart';

class Writer implements BridgeHealthWriter {
  final batches = <List<Map<String, Object?>>>[];
  final versions = <int>[];
  bool succeed = true;
  Future<void> Function()? duringWrite;
  @override
  Future<bool> writeMinutes(List<Map<String, Object?>> minutes) async {
    batches.add(minutes);
    await duringWrite?.call();
    return succeed;
  }

  @override
  Future<bool> writeNight(
    String day,
    int version,
    Map<String, dynamic> bundle,
  ) async {
    versions.add(version);
    return succeed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late Writer writer;
  late BridgeHealthExporter exporter;
  var enabled = true;
  var nights = <Map<String, dynamic>>[];
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE decoded_onehz(rec_ts INTEGER PRIMARY KEY,hr INTEGER,source TEXT)',
    );
    writer = Writer();
    enabled = true;
    nights = [];
    exporter = BridgeHealthExporter(
      database: () async => db,
      writer: writer,
      enabled: () async => enabled,
      nights: () async => nights,
    );
    await exporter.initialize();
  });
  tearDown(() async {
    await db.close();
  });

  Future<void> retentionPrune() async {
    await db.transaction((tx) async {
      await tx.insert('bridge_export_meta', {
        'key': 'retention_prune',
        'value': '1',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.delete('decoded_onehz');
      await tx.delete(
        'bridge_export_meta',
        where: 'key=?',
        whereArgs: ['retention_prune'],
      );
    });
  }

  test(
    'retention prune never queues deletion of exported health history',
    () async {
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 72});
      await exporter.exportPending();
      await retentionPrune();
      expect(await db.query('decoded_onehz'), isEmpty);
      expect(await db.query('bridge_hr_outbox'), isEmpty);
      expect((await exporter.exportPending()).heartRateMinutes, 0);
      expect(writer.batches, hasLength(1));
      // Genuine corrections still delete their matching stable health identity.
      await db.insert('decoded_onehz', {'rec_ts': 180, 'hr': 80});
      await db.delete('decoded_onehz');
      await exporter.exportPending();
      expect(writer.batches.last.single['bpm'], null);
    },
  );

  test(
    'pending HR keeps captured measurements through flagged raw prune',
    () async {
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 60});
      await db.insert('decoded_onehz', {'rec_ts': 121, 'hr': 100});
      final before = (await db.query('bridge_hr_outbox')).single;
      await retentionPrune();
      expect((await db.query('bridge_hr_outbox')).single, before);
      expect((await exporter.exportPending()).success, true);
      expect(writer.batches.single.single['bpm'], 80);
    },
  );

  test(
    'failed retention transaction rolls back flag and resumes correction deletes',
    () async {
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 72});
      await exporter.exportPending();
      await expectLater(
        db.transaction((tx) async {
          await tx.insert('bridge_export_meta', {
            'key': 'retention_prune',
            'value': '1',
          });
          await tx.delete('decoded_onehz');
          throw StateError('interrupted prune');
        }),
        throwsStateError,
      );
      expect(
        await db.query(
          'bridge_export_meta',
          where: 'key=?',
          whereArgs: ['retention_prune'],
        ),
        isEmpty,
      );
      await db.delete('decoded_onehz');
      await exporter.exportPending();
      expect(writer.batches.last.single['bpm'], null);
    },
  );

  test('native adapter never invents sleep or scalar timestamps', () async {
    const channel = MethodChannel('openstrap/bridge_health');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final native = BridgeHealthExporter(
      database: () async => db,
      enabled: () async => true,
      nights: () async => [
        {
          'day': '2026-10-03',
          'bundle': {
            'scalars': {'rmssd': 40, 'rhr': null, 'resp_rate': 0},
          },
        },
      ],
    );
    expect((await native.exportPending()).success, true);
    final arguments =
        calls.singleWhere((call) => call.method == 'upsertNight').arguments
            as Map;
    expect(arguments['time'], null);
    expect(arguments['session'], null);
    expect(arguments['scalars'], isEmpty);
  });

  test('first initialization seeds retained HR exactly once', () async {
    final retained = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await retained.execute(
        'CREATE TABLE decoded_onehz(rec_ts INTEGER PRIMARY KEY,hr INTEGER,source TEXT)',
      );
      await retained.insert('decoded_onehz', {'rec_ts': 120, 'hr': 72});
      final bridge = BridgeHealthExporter(
        database: () async => retained,
        writer: writer,
        enabled: () async => true,
        nights: () async => [],
      );
      expect((await bridge.exportPending()).heartRateMinutes, 1);
      await bridge.initialize();
      expect((await bridge.exportPending()).heartRateMinutes, 0);
      expect(writer.batches.single.single['bpm'], 72);
    } finally {
      await retained.close();
    }
  });

  test('external sensor updates never enqueue band tombstones', () async {
    await db.insert('decoded_onehz', {
      'rec_ts': 120,
      'hr': 72,
      'source': 'external',
    });
    await db.update('decoded_onehz', {'hr': 80}, where: 'rec_ts=120');
    expect((await exporter.exportPending()).heartRateMinutes, 0);
    expect(writer.batches, isEmpty);
  });

  test(
    'upgrade defers old dates in background and foreground replays them',
    () async {
      await db.execute(
        'CREATE TABLE sync_cursor(name TEXT PRIMARY KEY,value TEXT,updated_at INTEGER)',
      );
      await db.insert('sync_cursor', {
        'name': 'health_export_through',
        'value': '2026-10-02',
      });
      await db.delete(
        'bridge_export_meta',
        where: 'key=?',
        whereArgs: ['legacy_cutoff'],
      );
      exporter = BridgeHealthExporter(
        database: () async => db,
        writer: writer,
        enabled: () async => true,
        nights: () async => nights,
        now: () => DateTime(2026, 10, 3, 10),
      );
      await exporter.initialize();
      final oldMinute = DateTime(2026, 10, 3, 9).millisecondsSinceEpoch ~/ 1000;
      final newMinute = DateTime(2026, 10, 4, 9).millisecondsSinceEpoch ~/ 1000;
      await db.insert('decoded_onehz', {'rec_ts': oldMinute, 'hr': 70});
      await db.insert('decoded_onehz', {'rec_ts': newMinute, 'hr': 80});
      nights = [
        {'day': '2026-10-03', 'bundle': <String, dynamic>{}},
        {'day': '2026-10-04', 'bundle': <String, dynamic>{}},
      ];
      final background = await exporter.exportPending();
      expect(background.heartRateMinutes, 1);
      expect(background.nightlyDays, 1);
      expect(writer.batches.single.single['minute'], newMinute);
      expect((await db.query('bridge_hr_outbox')).single['minute'], oldMinute);
      final foreground = await exporter.exportPending(
        allowLegacyMigration: true,
      );
      expect(foreground.heartRateMinutes, 1);
      expect(foreground.nightlyDays, 1);
      expect(await db.query('bridge_hr_outbox'), isEmpty);
      // The cutoff is a one-shot persisted decision, not a moving date boundary.
      await exporter.initialize();
      expect(
        (await db.query(
          'bridge_export_meta',
          where: 'key=?',
          whereArgs: ['legacy_cutoff'],
        )).single['value'],
        '${DateTime(2026, 10, 4).millisecondsSinceEpoch}',
      );
    },
  );

  test(
    'fresh installs configure write-only export with no legacy cutoff',
    () async {
      expect(
        (await db.query(
          'bridge_export_meta',
          where: 'key=?',
          whereArgs: ['legacy_cutoff'],
        )).single['value'],
        '0',
      );
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 70});
      expect((await exporter.exportPending()).heartRateMinutes, 1);
    },
  );

  test(
    'local reset seeds versions newer than retained Health Connect identities',
    () async {
      var now = DateTime(2026, 10, 3);
      exporter = BridgeHealthExporter(
        database: () async => db,
        writer: writer,
        enabled: () async => true,
        nights: () async => nights,
        now: () => now,
      );
      nights = [
        {'day': '2026-10-03', 'bundle': <String, dynamic>{}},
      ];
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 72});
      await exporter.exportPending();
      final oldMinuteVersion =
          writer.batches.single.single['generation'] as int;
      final oldNightVersion = writer.versions.single;
      await db.transaction((tx) async {
        await tx.delete('decoded_onehz');
        await tx.delete('bridge_hr_outbox');
        await tx.delete('bridge_export_sequence');
        await tx.delete('bridge_export_meta');
        await tx.delete('bridge_night_export');
      });
      now = DateTime.now().add(const Duration(days: 1));
      await exporter.initialize();
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 80});
      await exporter.exportPending();
      expect(
        writer.batches.last.single['generation'] as int,
        greaterThan(oldMinuteVersion),
      );
      expect(writer.versions.last, greaterThan(oldNightVersion));
    },
  );

  test(
    'night failures persist retry delay and preserve same version',
    () async {
      var now = DateTime(2026, 10, 3);
      nights = [
        {'day': '2026-10-03', 'bundle': <String, dynamic>{}},
      ];
      exporter = BridgeHealthExporter(
        database: () async => db,
        writer: writer,
        enabled: () async => true,
        nights: () async => nights,
        now: () => now,
      );
      writer.succeed = false;
      expect((await exporter.exportPending()).success, false);
      expect((await exporter.exportPending()).nightlyDays, 0);
      expect(writer.versions, hasLength(1));
      final attemptedVersion = writer.versions.single;
      now = now.add(const Duration(minutes: 6));
      writer.succeed = true;
      expect((await exporter.exportPending()).nightlyDays, 1);
      expect(writer.versions, [attemptedVersion, attemptedVersion]);
    },
  );

  test(
    'raw HR exports without any day_result, averages minutes and abstains',
    () async {
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 60});
      await db.insert('decoded_onehz', {'rec_ts': 121, 'hr': 100});
      await db.insert('decoded_onehz', {'rec_ts': 180, 'hr': 0});
      await db.insert('decoded_onehz', {
        'rec_ts': 240,
        'hr': 90,
        'source': 'external',
      });
      final result = await exporter.exportPending();
      expect(result.success, true);
      expect(writer.batches.single.length, 2);
      expect(
        writer.batches.single.singleWhere((row) => row['minute'] == 120)['bpm'],
        80,
      );
      expect(
        writer.batches.single.singleWhere((row) => row['minute'] == 180)['bpm'],
        null,
      );
      expect(await db.query('bridge_hr_outbox'), isEmpty);
    },
  );
  test(
    'failure and process restart replay the same persistent identity/version',
    () async {
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 60});
      writer.succeed = false;
      expect((await exporter.exportPending()).success, false);
      final attempted = writer.batches.single.single;
      exporter = BridgeHealthExporter(
        database: () async => db,
        writer: writer,
        enabled: () async => true,
        nights: () async => [],
      );
      writer.succeed = true;
      expect((await exporter.exportPending()).success, true);
      expect(writer.batches.last.single, attempted);
    },
  );
  test('correction during write survives captured-generation clear', () async {
    await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 60});
    writer.duringWrite = () async {
      writer.duringWrite = null;
      await db.update('decoded_onehz', {'hr': 90}, where: 'rec_ts=120');
    };
    expect((await exporter.exportPending()).success, true);
    expect(writer.batches.length, 2);
    expect(writer.batches.first.single['bpm'], 60);
    expect(writer.batches.last.single['bpm'], 90);
    expect(
      writer.batches.last.single['generation'] as int,
      greaterThan(writer.batches.first.single['generation'] as int),
    );
  });
  test(
    'replacement, timestamp move and deletion enqueue corrections',
    () async {
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 60});
      await exporter.exportPending();
      await db.insert('decoded_onehz', {
        'rec_ts': 120,
        'hr': 80,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await exporter.exportPending();
      expect(writer.batches.last.single['bpm'], 80);
      await db.update('decoded_onehz', {'rec_ts': 180}, where: 'rec_ts=120');
      await exporter.exportPending();
      expect(
        writer.batches.last.singleWhere((row) => row['minute'] == 120)['bpm'],
        null,
      );
      expect(
        writer.batches.last.singleWhere((row) => row['minute'] == 180)['bpm'],
        80,
      );
      await db.delete('decoded_onehz');
      await exporter.exportPending();
      expect(writer.batches.last.single['bpm'], null);
    },
  );
  test(
    'disabled export preserves outbox, simultaneous calls share flight',
    () async {
      await db.insert('decoded_onehz', {'rec_ts': 120, 'hr': 60});
      enabled = false;
      await exporter.exportPending();
      expect(writer.batches, isEmpty);
      expect(await db.query('bridge_hr_outbox'), hasLength(1));
      enabled = true;
      final first = exporter.exportPending();
      final second = exporter.exportPending();
      expect(identical(first, second), true);
      await first;
      expect(writer.batches, hasLength(1));
    },
  );
  test(
    'nightly export fingerprint persists and correction increments version',
    () async {
      nights = [
        {
          'day': '2026-10-03',
          'bundle': {
            'scalars': {'rmssd': 30},
          },
        },
      ];
      expect((await exporter.exportPending()).nightlyDays, 1);
      expect((await exporter.exportPending()).nightlyDays, 0);
      nights.single['bundle'] = {
        'scalars': {'rmssd': 40},
      };
      expect((await exporter.exportPending()).nightlyDays, 1);
      expect(writer.versions, hasLength(2));
      expect(writer.versions.last, greaterThan(writer.versions.first));
    },
  );
}
