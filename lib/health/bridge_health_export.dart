import 'dart:async';
import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db.dart';
import '../data/series_codec.dart';
import 'health_sleep_session.dart';

const kHealthSyncEnabledKey = 'health_sync_enabled';

enum HealthLinkState { unknown, ready, notInstalled, needsUpdate, unsupported }

class BridgeExportResult {
  const BridgeExportResult({
    this.heartRateMinutes = 0,
    this.nightlyDays = 0,
    this.success = true,
  });
  final int heartRateMinutes;
  final int nightlyDays;
  final bool success;
}

abstract interface class BridgeHealthWriter {
  Future<bool> writeMinutes(List<Map<String, Object?>> minutes);
  Future<bool> writeNight(String day, int version, Map<String, dynamic> bundle);
}

class _NativeWriter implements BridgeHealthWriter {
  static const channel = MethodChannel('openstrap/bridge_health');
  Future<void> configureLegacy(int cutoff, bool allowRead) async {
    if (await channel.invokeMethod<bool>('configureLegacy', {
          'cutoff': cutoff,
          'allowRead': allowRead,
        }) !=
        true) {
      throw StateError('Health migration configuration failed');
    }
  }

  @override
  Future<bool> writeMinutes(List<Map<String, Object?>> minutes) async =>
      await channel.invokeMethod<bool>('upsertMinutes', {'minutes': minutes}) ==
      true;
  @override
  Future<bool> writeNight(
    String day,
    int version,
    Map<String, dynamic> bundle,
  ) async {
    final session = normalizeHealthSleepSession(bundle);
    final scalars = bundle['scalars'] as Map? ?? const {};
    final values = <String, num>{};
    for (final key in ['rhr', 'rmssd', 'resp_rate']) {
      final value = scalars[key];
      if (value is num && value.isFinite && value > 0) values[key] = value;
    }
    // A scalar's timestamp belongs to a measured sleep window.
    final midpoint = session == null
        ? null
        : (session.start.millisecondsSinceEpoch +
                  session.end.millisecondsSinceEpoch) ~/
              2;
    return await channel.invokeMethod<bool>('upsertNight', {
          'day': day,
          'version': version,
          'session': session?.toMap(),
          'time': midpoint,
          'scalars': midpoint == null ? <String, num>{} : values,
        }) ==
        true;
  }
}

/// Durable minute outbox: raw ingestion commits its pending export atomically.
/// Export success clears only the captured generation, never a newer correction.
class BridgeHealthExporter {
  BridgeHealthExporter({
    Future<Database> Function()? database,
    BridgeHealthWriter? writer,
    Future<bool> Function()? enabled,
    Future<List<Map<String, dynamic>>> Function()? nights,
    DateTime Function()? now,
  }) : _database = database ?? (() => LocalDb.instance),
       _writer = writer ?? _NativeWriter(),
       _enabled =
           enabled ??
           (() async =>
               (await SharedPreferences.getInstance()).getBool(
                 kHealthSyncEnabledKey,
               ) ==
               true),
       _nights = nights ?? _loadNights,
       _now = now ?? DateTime.now;
  static final shared = BridgeHealthExporter();
  final Future<Database> Function() _database;
  final BridgeHealthWriter _writer;
  final Future<bool> Function() _enabled;
  final Future<List<Map<String, dynamic>>> Function() _nights;
  final DateTime Function() _now;
  Future<BridgeExportResult>? _flight;
  bool _flightAllowsLegacy = false;
  final _health = Health();

  static Future<List<Map<String, dynamic>>> _loadNights() async {
    final result = <Map<String, dynamic>>[];
    for (final row in await LocalDb.recentDayResultsMeta(40)) {
      if (row['skipped'] == 1 || row['partial'] == 1) continue;
      final day = row['day_id'] as String;
      final payload = (await LocalDb.dayResult(day))?['payload_json'];
      if (payload is String) {
        result.add({
          'day': day,
          'bundle': SeriesCodec.decodePayload(
            (jsonDecode(payload) as Map).cast<String, dynamic>(),
          ),
        });
      }
    }
    return result;
  }

  Future<HealthLinkState> check() async {
    try {
      await _health.configure();
      final status = await _health.getHealthConnectSdkStatus();
      return switch (status) {
        HealthConnectSdkStatus.sdkAvailable => HealthLinkState.ready,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
          HealthLinkState.needsUpdate,
        _ => HealthLinkState.notInstalled,
      };
    } catch (_) {
      return HealthLinkState.unsupported;
    }
  }

  Future<HealthLinkState> request() async {
    final state = await check();
    if (state != HealthLinkState.ready) return state;
    await initialize();
    final legacy = await _legacyCutoff(await _database()) > 0;
    await _health.requestAuthorization(
      [
        HealthDataType.HEART_RATE,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        HealthDataType.RESPIRATORY_RATE,
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_REM,
      ],
      permissions: List.filled(
        9,
        legacy ? HealthDataAccess.READ_WRITE : HealthDataAccess.WRITE,
      ),
    );
    return state;
  }

  Future<void> install() => _health.installHealthConnect();
  Future<void> openSettings() async {
    try {
      await const AndroidIntent(
        action: 'android.health.connect.action.HEALTH_HOME_SETTINGS',
      ).launch();
    } catch (_) {
      await const AndroidIntent(
        action: 'androidx.health.ACTION_HEALTH_CONNECT_SETTINGS',
      ).launch();
    }
  }

  Future<void> initialize() async {
    final db = await _database();
    await db.transaction((tx) async {
      await tx.execute(
        'CREATE TABLE IF NOT EXISTS bridge_export_sequence (id INTEGER PRIMARY KEY CHECK(id=1), value INTEGER NOT NULL)',
      );
      // A local reset cannot recycle versions below records still in Health
      // Connect. The epoch seed gives a fresh store a newer version namespace.
      await tx.execute(
        'INSERT OR IGNORE INTO bridge_export_sequence VALUES(1,?)',
        [_now().microsecondsSinceEpoch],
      );
      await tx.execute(
        'CREATE TABLE IF NOT EXISTS bridge_hr_outbox (minute INTEGER PRIMARY KEY, bpm REAL, generation INTEGER NOT NULL)',
      );
      await tx.execute(
        'CREATE TABLE IF NOT EXISTS bridge_export_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await tx.execute(
        'CREATE TABLE IF NOT EXISTS bridge_night_export (day TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, version INTEGER NOT NULL, ok INTEGER NOT NULL DEFAULT 0, retry_ms INTEGER NOT NULL DEFAULT 0)',
      );
      final migration = await tx.query(
        'bridge_export_meta',
        where: 'key=?',
        whereArgs: ['legacy_cutoff'],
      );
      if (migration.isEmpty) {
        final hasCursorTable = (await tx.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_cursor'",
        )).isNotEmpty;
        final oldExports =
            hasCursorTable &&
            (await tx.rawQuery(
              "SELECT name FROM sync_cursor WHERE name IN ('health_export_through','health_export_retry_state') AND value IS NOT NULL AND value != '' LIMIT 1",
            )).isNotEmpty;
        final now = _now();
        // Today's anonymous full-day record can already exist on upgrade.
        final cutoff = oldExports
            ? DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch
            : 0;
        await tx.insert('bridge_export_meta', {
          'key': 'legacy_cutoff',
          'value': '$cutoff',
        });
      }
      String enqueue(String row) =>
          '''
        UPDATE bridge_export_sequence SET value=value+1 WHERE id=1;
        INSERT OR REPLACE INTO bridge_hr_outbox(minute,bpm,generation)
        SELECT ($row.rec_ts/60)*60,
          (SELECT AVG(hr) FROM decoded_onehz WHERE rec_ts>=($row.rec_ts/60)*60 AND rec_ts<($row.rec_ts/60)*60+60 AND $kPrimaryBandSourceSql AND hr>0 AND hr<=300),
          value FROM bridge_export_sequence WHERE id=1;
      ''';
      await tx.execute('DROP TRIGGER IF EXISTS bridge_hr_insert');
      await tx.execute(
        'CREATE TRIGGER IF NOT EXISTS bridge_hr_insert AFTER INSERT ON decoded_onehz WHEN NEW.$kPrimaryBandSourceSql BEGIN ${enqueue('NEW')} END',
      );
      // Retention removes raw backing rows, not durable health history. The
      // pruning transaction marks that intent and clears it before committing.
      // Replace the initial trigger definition for already initialized bridges.
      await tx.execute('DROP TRIGGER IF EXISTS bridge_hr_delete');
      await tx.execute(
        "CREATE TRIGGER bridge_hr_delete AFTER DELETE ON decoded_onehz WHEN OLD.$kPrimaryBandSourceSql AND NOT EXISTS(SELECT 1 FROM bridge_export_meta WHERE key='retention_prune' AND value='1') BEGIN ${enqueue('OLD')} END",
      );
      await tx.execute('DROP TRIGGER IF EXISTS bridge_hr_update');
      await tx.execute(
        'CREATE TRIGGER IF NOT EXISTS bridge_hr_update AFTER UPDATE ON decoded_onehz WHEN OLD.$kPrimaryBandSourceSql OR NEW.$kPrimaryBandSourceSql BEGIN ${enqueue('OLD')} ${enqueue('NEW')} END',
      );
      final seeded = await tx.query(
        'bridge_export_meta',
        where: 'key=?',
        whereArgs: ['seeded'],
      );
      if (seeded.isEmpty) {
        await tx.execute(
          'UPDATE bridge_export_sequence SET value=value+1 WHERE id=1',
        );
        await tx.execute(
          'INSERT OR IGNORE INTO bridge_hr_outbox SELECT (rec_ts/60)*60,AVG(hr),(SELECT value FROM bridge_export_sequence WHERE id=1) FROM decoded_onehz WHERE $kPrimaryBandSourceSql AND hr>0 AND hr<=300 GROUP BY (rec_ts/60)*60',
        );
        await tx.insert('bridge_export_meta', {'key': 'seeded', 'value': '1'});
      }
    });
  }

  Future<int> _legacyCutoff(Database db) async {
    final rows = await db.query(
      'bridge_export_meta',
      where: 'key=?',
      whereArgs: ['legacy_cutoff'],
    );
    return rows.isEmpty ? 0 : int.tryParse(rows.single['value'] as String) ?? 0;
  }

  Future<BridgeExportResult> exportPending({
    bool allowLegacyMigration = false,
  }) {
    final pending = _flight;
    if (pending != null) {
      // A foreground Sync must still perform migration if it arrives during
      // a background write-only pass, rather than losing the user's gesture.
      if (allowLegacyMigration && !_flightAllowsLegacy) {
        return pending.then((_) => exportPending(allowLegacyMigration: true));
      }
      return pending;
    }
    _flightAllowsLegacy = allowLegacyMigration;
    return _flight = _export(allowLegacyMigration).whenComplete(() {
      _flight = null;
    });
  }

  Future<BridgeExportResult> _export(bool allowLegacyMigration) async {
    if (!await _enabled()) return const BridgeExportResult();
    var minutes = 0;
    var nights = 0;
    var success = true;
    try {
      await initialize();
      final db = await _database();
      final cutoff = await _legacyCutoff(db);
      if (_writer is _NativeWriter) {
        await (_writer).configureLegacy(cutoff, allowLegacyMigration);
      }
      final deferred = cutoff > 0 && !allowLegacyMigration;
      // Bound one wake slot even if ingestion keeps producing corrections.
      for (
        var batchNumber = 0;
        batchNumber < 24 && await _enabled();
        batchNumber++
      ) {
        // Finish pure-write dates before touching migration backlog. A read
        // permission failure on an old day cannot hold today's data hostage.
        var batch = await db.query(
          'bridge_hr_outbox',
          where: cutoff > 0 ? 'minute >= ?' : null,
          whereArgs: cutoff > 0 ? [cutoff ~/ 1000] : null,
          orderBy: 'minute DESC',
          limit: 500,
        );
        if (batch.isEmpty && cutoff > 0 && allowLegacyMigration) {
          batch = await db.query(
            'bridge_hr_outbox',
            where: 'minute < ?',
            whereArgs: [cutoff ~/ 1000],
            orderBy: 'minute DESC',
            limit: 500,
          );
        }
        if (batch.isEmpty) break;
        if (!await _writer.writeMinutes(batch)) {
          success = false;
          break;
        }
        await db.transaction((tx) async {
          for (final row in batch) {
            await tx.delete(
              'bridge_hr_outbox',
              where: 'minute=? AND generation=?',
              whereArgs: [row['minute'], row['generation']],
            );
          }
        });
        minutes += batch.length;
      }
      for (final night in await _nights()) {
        if (!await _enabled()) break;
        final day = night['day'] as String;
        if (deferred && DateTime.parse(day).millisecondsSinceEpoch < cutoff) {
          continue;
        }
        final bundle = (night['bundle'] as Map).cast<String, dynamic>();
        final sc = bundle['scalars'] as Map? ?? const {};
        // Persist only export-relevant input, so unrelated readiness recomputes
        // never rewrite a night's health records.
        final fingerprint = jsonEncode([
          normalizeHealthSleepSession(bundle)?.toMap(),
          sc['rhr'],
          sc['rmssd'],
          sc['resp_rate'],
        ]);
        final previous = await db.query(
          'bridge_night_export',
          where: 'day=?',
          whereArgs: [day],
        );
        final old = previous.isEmpty ? null : previous.single;
        final changed = old?['fingerprint'] != fingerprint;
        if (!changed &&
            (old?['ok'] == 1 ||
                (old?['retry_ms'] as int? ?? 0) >
                    _now().millisecondsSinceEpoch)) {
          continue;
        }
        final version = changed
            ? await db.transaction((tx) async {
                await tx.execute(
                  'UPDATE bridge_export_sequence SET value=value+1 WHERE id=1',
                );
                return (await tx.query(
                      'bridge_export_sequence',
                    )).single['value']
                    as int;
              })
            : old!['version'] as int;
        await db.insert('bridge_night_export', {
          'day': day,
          'fingerprint': fingerprint,
          'version': version,
          'ok': 0,
          'retry_ms': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        bool wrote;
        try {
          wrote = await _writer.writeNight(day, version, bundle);
        } catch (_) {
          wrote = false;
        }
        await db.update(
          'bridge_night_export',
          {
            'ok': wrote ? 1 : 0,
            'retry_ms': wrote
                ? 0
                : _now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
          },
          where: 'day=? AND version=?',
          whereArgs: [day, version],
        );
        if (wrote) {
          nights++;
        } else {
          success = false;
        }
      }
    } catch (_) {
      success = false;
    }
    return BridgeExportResult(
      heartRateMinutes: minutes,
      nightlyDays: nights,
      success: success,
    );
  }
}
