import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/health/bridge_health_export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

class Sink implements BridgeHealthWriter {
  @override
  Future<bool> writeMinutes(List<Map<String, Object?>> rows) async => true;
  @override
  Future<bool> writeNight(
    String day,
    int version,
    Map<String, dynamic> bundle,
  ) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late BridgeHealthExporter exporter;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LocalDb.close();
    LocalDb.dbName = 'bridge_retention_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    db = await LocalDb.instance;
    exporter = BridgeHealthExporter(
      database: () async => db,
      writer: Sink(),
      enabled: () async => true,
      nights: () async => [],
    );
    await exporter.initialize();
    await db.insert('decoded_onehz', {'rec_ts': 120, 'counter': 1, 'hr': 72});
  });
  tearDown(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });
  test(
    'real retention holds pending export, then prunes without health tombstone',
    () async {
      await LocalDb.pruneDecodedBeforeRecTs(300);
      expect(await db.query('decoded_onehz'), hasLength(1));
      expect((await exporter.exportPending()).success, true);
      await LocalDb.pruneDecodedBeforeRecTs(300);
      expect(await db.query('decoded_onehz'), isEmpty);
      expect(await db.query('bridge_hr_outbox'), isEmpty);
      expect(
        await db.query(
          'bridge_export_meta',
          where: 'key=?',
          whereArgs: ['retention_prune'],
        ),
        isEmpty,
      );
    },
  );
  test(
    'the real capture trigger uses an index for each minute aggregate',
    () async {
      final definition =
          (await db.rawQuery(
                "SELECT sql FROM sqlite_master WHERE type='trigger' AND name='bridge_hr_insert'",
              )).single['sql']
              as String;
      final start = definition.indexOf('SELECT AVG(hr)');
      final end = definition.indexOf('),', start);
      final query = definition
          .substring(start, end)
          .replaceAll('NEW.rec_ts', '120');
      final plan = await db.rawQuery('EXPLAIN QUERY PLAN $query');
      expect(
        plan.any((row) => (row['detail'] as String).contains('SEARCH')),
        true,
        reason: '$plan',
      );
    },
  );

  test('raw unknown archive survives real retention', () async {
    await db.execute(
      "INSERT INTO raw_archive (reason,captured_at,hex,packet_type) VALUES ('unknown_version',0,'01',1)",
    );
    await exporter.exportPending();
    await LocalDb.pruneDecodedBeforeRecTs(300);
    expect(await db.query('raw_archive'), hasLength(1));
  });
  test('local wipe does not leave exported-delete queue', () async {
    await LocalDb.wipeAll();
    await db.delete('bridge_hr_outbox');
    expect(await db.query('decoded_onehz'), isEmpty);
    expect(await db.query('bridge_hr_outbox'), isEmpty);
    await exporter.initialize();
    await db.insert('decoded_onehz', {'rec_ts': 180, 'counter': 2, 'hr': 80});
    expect((await exporter.exportPending()).heartRateMinutes, 1);
  });
}
