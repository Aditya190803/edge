import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/adapters/_registry.dart';
import '../ble/adapters/host.dart';
import '../ble/adapters/whoop_gen4.dart';
import '../ble/android_background.dart';
import '../ble/ble_engine.dart';
import '../ble/ble_state.dart' show withScanLock;
import '../compute/derivation_engine.dart';
import '../compute/derive_scheduler.dart';
import '../compute/profile.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../health/bridge_health_export.dart';
import '../sync/band_ownership.dart';
import '../sync/edge_tracking.dart';
import '../sync/paired_device.dart';
import '../sync/reset_gate.dart';

const kBridgeSyncPausedKey = 'bridge_sync_paused';

/// The small hardware seam lets regression tests exercise failed operations and
/// pause races without pretending a Bluetooth peripheral is connected.
abstract class BridgeBackend {
  void attach({
    required void Function(DeviceState) onState,
    required void Function() onCommitted,
    required void Function(bool) onOffload,
    required void Function() onDerived,
  });
  Future<void> initialize();
  Future<PairedDevice?> loadPairing();
  Future<void> savePairing(PairedDevice device);
  Future<void> clearPairing();
  Future<void> wipe();
  Future<DateTime?> newestDataAt();
  Future<List<ScanResult>> scan();
  Future<bool> connect(String remoteId);
  Future<void> disconnect();
  Future<void> sync();
  Future<void> startService();
  Future<void> stopService();
  Future<void> associate(String remoteId);
  Future<bool> batteryExempt();
  Future<HealthLinkState> checkHealth();
  Future<HealthLinkState> requestHealth();
  Future<BridgeExportResult> export({bool allowLegacyMigration = false});
  void stored();
  void offload(bool active);
  void setBackground(bool background);
  void dispose();
}

class BridgeCoordinator extends ChangeNotifier with WidgetsBindingObserver {
  BridgeCoordinator({
    BridgeBackend? backend,
    this.exportDelay = const Duration(seconds: 5),
    this.retryInterval = const Duration(minutes: 1),
    this.dataRefreshDelay = const Duration(seconds: 1),
  }) : _backend = backend ?? _NativeBridgeBackend() {
    _backend.attach(
      onState: _onState,
      onCommitted: _onCommitted,
      onOffload: (active) {
        syncing = active;
        _backend.offload(active);
        _changed();
      },
      onDerived: _scheduleExport,
    );
  }

  final BridgeBackend _backend;
  final Duration exportDelay;
  final Duration retryInterval;
  final Duration dataRefreshDelay;
  bool initialized = false;
  String? initializationError;
  PairedDevice? paired;
  DeviceState state = DeviceState();
  bool scanning = false;
  List<ScanResult> scanResults = [];
  bool busy = false;
  bool syncing = false;
  bool paused = false;
  String? error;
  DateTime? lastDataAt;
  DateTime? lastExportAt;
  HealthLinkState healthState = HealthLinkState.unknown;
  bool healthSyncEnabled = false;
  bool batteryOptimizationIgnored = false;
  bool _disposed = false;
  bool _exporting = false;
  bool _exportPending = false;
  bool _manualExportPending = false;
  bool _deleting = false;
  bool _refreshingData = false;
  bool _dataRefreshPending = false;
  int _dataRevision = 0;
  int _intent = 0;
  Timer? _supervisor;
  Timer? _exportTimer;
  Timer? _dataTimer;
  Future<void>? _initializing;
  Future<void> _controls = Future<void>.value();
  BandLease? _lease;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    initializationError = null;
    error = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      paused = prefs.getBool(kBridgeSyncPausedKey) ?? false;
      healthSyncEnabled = prefs.getBool(kHealthSyncEnabledKey) ?? false;
      final lastExport = prefs.getInt('bridge_last_export_ms');
      lastExportAt = lastExport == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastExport);
      await _backend.initialize();
      paired = await _backend.loadPairing();
      await _refreshDataTime();
      if (paired?.generation == 'gen5') {
        error = 'This bridge supports WHOOP 4. Unpair the saved WHOOP 5/MG.';
      }
      WidgetsBinding.instance.addObserver(this);
      _backend.setBackground(
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed,
      );
      initialized = true;
      _supervisor = Timer.periodic(retryInterval, (_) {
        unawaited(_connect());
        _scheduleExport();
      });
      await refreshStatus();
      if (!paused && paired != null && paired!.generation != 'gen5') {
        await _backend.startService();
        unawaited(_connect());
      }
      _scheduleExport();
    } catch (e) {
      _supervisor?.cancel();
      _supervisor = null;
      WidgetsBinding.instance.removeObserver(this);
      initialized = false;
      initializationError = e.toString();
      error = initializationError;
      _initializing = null;
    } finally {
      _changed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setBackground(state != AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) unawaited(refreshStatus());
  }

  void setBackground(bool background) => _backend.setBackground(background);

  void _onState(DeviceState value) {
    if (_disposed) return;
    state = value;
    _changed();
  }

  void _onCommitted() {
    if (_disposed || _deleting) return;
    _scheduleDataTime();
    _backend.stored();
    _scheduleExport();
    _changed();
  }

  void _scheduleDataTime() {
    if (_disposed || _deleting) return;
    _dataRefreshPending = true;
    _dataTimer ??= Timer(dataRefreshDelay, () {
      _dataTimer = null;
      unawaited(_refreshDataTime());
    });
  }

  Future<void> _refreshDataTime() async {
    if (_disposed || _deleting || _refreshingData) return;
    final revision = _dataRevision;
    _refreshingData = true;
    _dataRefreshPending = false;
    try {
      final newest = await _backend.newestDataAt();
      if (!_disposed && revision == _dataRevision) lastDataAt = newest;
    } catch (e) {
      error = e.toString();
    } finally {
      _refreshingData = false;
      if (_dataRefreshPending) _scheduleDataTime();
      _changed();
    }
  }

  Future<void> scan() async {
    if (busy || scanning || _disposed) return;
    scanning = true;
    error = null;
    scanResults = [];
    _changed();
    try {
      scanResults = await _backend.scan();
    } catch (e) {
      error = e.toString();
    } finally {
      scanning = false;
      _changed();
    }
  }

  Future<void> pair(ScanResult result) async {
    if (busy || scanning || _disposed) return;
    if (!acceptsWhoop4Advertisement(
      result.advertisementData.serviceUuids.map((id) => id.str),
      name: '${result.device.platformName} ${result.advertisementData.advName}',
    )) {
      error = 'Only WHOOP 4 is supported.';
      _changed();
      return;
    }
    final epoch = ++_intent;
    await _control(() async {
      if (_disposed || epoch != _intent) return;
      busy = true;
      error = null;
      _changed();
      try {
        // Choosing a new band explicitly starts its sync, including after a
        // paused installation was cleared.
        paused = false;
        await (await SharedPreferences.getInstance()).setBool(
          kBridgeSyncPausedKey,
          false,
        );
        await _backend.disconnect();
        _releaseLease();
        _lease = await BandOwnership.acquireForeground();
        final ok = await _backend.connect(result.device.remoteId.str);
        if (_disposed || epoch != _intent || paused) {
          await _backend.disconnect();
          _releaseLease();
          return;
        }
        if (!ok || state.generation != 'gen4') {
          await _backend.disconnect();
          _releaseLease();
          throw StateError(
            'Could not connect to a WHOOP 4. WHOOP 5/MG is unsupported.',
          );
        }
        final device = PairedDevice(
          result.device.remoteId.str,
          state.serial,
          generation: 'gen4',
        );
        await _backend.savePairing(device);
        if (_disposed || epoch != _intent || paused) {
          await _backend.disconnect();
          _releaseLease();
          return;
        }
        paired = device;
        await _backend.startService();
        await _backend.associate(device.remoteId);
      } catch (e) {
        error = e.toString();
        await _backend.disconnect();
        _releaseLease();
      } finally {
        busy = false;
        _changed();
      }
    });
  }

  Future<void> _connect({bool manual = false}) async {
    if (!initialized ||
        _disposed ||
        paused ||
        paired == null ||
        paired!.generation == 'gen5' ||
        busy ||
        scanning ||
        state.connection == 'connected' ||
        (!manual && state.autoReconnectPaused)) {
      return;
    }
    final epoch = _intent;
    final device = paired!;
    busy = true;
    _changed();
    try {
      _lease ??= await BandOwnership.acquireForeground();
      if (_disposed || paused || epoch != _intent) return;
      final ok = await _backend.connect(device.remoteId);
      if (_disposed || paused || epoch != _intent) {
        await _backend.disconnect();
        _releaseLease();
        return;
      }
      if (!ok) {
        throw StateError('Cannot reach WHOOP 4. Will retry automatically.');
      }
      if (state.generation != 'gen4') {
        await _backend.disconnect();
        _releaseLease();
        paired = PairedDevice(
          device.remoteId,
          device.serial,
          generation: 'gen5',
        );
        throw StateError(
          'The saved device is not WHOOP 4. Unpair it to continue.',
        );
      }
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      if (paused || _disposed || paired == null || epoch != _intent) {
        _releaseLease();
      }
      _changed();
    }
  }

  Future<void> syncNow() async {
    if (paused || busy || _disposed) return;
    error = null;
    try {
      if (state.connection != 'connected') await _connect(manual: true);
      if (!paused && state.connection == 'connected') await _backend.sync();
      await _export(
        allowLegacyMigration:
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
    } catch (e) {
      error = e.toString();
    } finally {
      _changed();
    }
  }

  Future<void> _control(Future<void> Function() action) {
    final next = _controls.then((_) => action());
    _controls = next.catchError((Object e) {
      error = e.toString();
      _changed();
    });
    return next;
  }

  Future<void> setPaused(bool value) {
    // Invalidate a connection before awaiting preferences or the engine lock.
    ++_intent;
    paused = value;
    _changed();
    return _control(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kBridgeSyncPausedKey, value);
      if (value) {
        _exportTimer?.cancel();
        _exportTimer = null;
        try {
          await _backend.disconnect();
        } finally {
          _releaseLease();
          await _backend.stopService();
        }
      } else if (paired != null && paired!.generation != 'gen5') {
        await _backend.startService();
        await _connect();
        _scheduleExport();
      }
    });
  }

  Future<void> unpair() {
    ++_intent;
    paired = null;
    _changed();
    return _control(() async {
      try {
        await _backend.disconnect();
      } finally {
        _releaseLease();
        await _backend.clearPairing();
        await _backend.stopService();
      }
      syncing = false;
      _changed();
    });
  }

  Future<void> deleteLocalData() async {
    if (_deleting) return;
    _deleting = true;
    ++_dataRevision;
    _dataTimer?.cancel();
    _dataTimer = null;
    _dataRefreshPending = false;
    ResetGate.enter();
    try {
      await setPaused(true);
      await unpair();
      // A Health write already in flight must finish before its local outbox is
      // removed. Exported Health Connect records are owned by Health Connect.
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (_exporting) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Export still running. Try deleting again later.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await _backend.wipe();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('local_profile_json');
      await prefs.remove('bridge_last_export_ms');
      lastDataAt = null;
      lastExportAt = null;
      error = null;
    } finally {
      _deleting = false;
      ResetGate.leave();
      _changed();
    }
  }

  Future<void> setHealthSyncEnabled(bool value) async {
    healthSyncEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kHealthSyncEnabledKey, value);
    try {
      if (value) {
        healthState = await _backend.requestHealth();
        await _export(
          allowLegacyMigration:
              WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed,
        );
      }
    } catch (e) {
      error = e.toString();
    } finally {
      _changed();
    }
  }

  Future<void> refreshStatus() async {
    try {
      healthState = await _backend.checkHealth();
      batteryOptimizationIgnored = await _backend.batteryExempt();
    } catch (e) {
      error = e.toString();
    } finally {
      _changed();
    }
  }

  void _scheduleExport() {
    if (_disposed || _deleting || paused || !healthSyncEnabled) return;
    _exportPending = true;
    _exportTimer ??= Timer(exportDelay, () {
      _exportTimer = null;
      unawaited(_export());
    });
  }

  Future<void> _export({bool allowLegacyMigration = false}) async {
    if (_disposed || _deleting || paused || !healthSyncEnabled) return;
    if (_exporting) {
      if (allowLegacyMigration) _manualExportPending = true;
      return;
    }
    _exporting = true;
    _exportPending = false;
    try {
      final result = await _backend.export(
        allowLegacyMigration: allowLegacyMigration,
      );
      if (!result.success) {
        throw StateError('Health Connect export incomplete. Will retry.');
      }
      if (result.heartRateMinutes > 0 || result.nightlyDays > 0) {
        lastExportAt = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          'bridge_last_export_ms',
          lastExportAt!.millisecondsSinceEpoch,
        );
      }
    } catch (e) {
      error = e.toString();
    } finally {
      _exporting = false;
      if (_manualExportPending) {
        _manualExportPending = false;
        unawaited(
          _export(
            allowLegacyMigration:
                WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed,
          ),
        );
      } else if (_exportPending) {
        _scheduleExport();
      }
      _changed();
    }
  }

  void _releaseLease() {
    if (_lease != null) BandOwnership.release(_lease!);
    _lease = null;
    BandOwnership.markForegroundIntent(false);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_intent;
    WidgetsBinding.instance.removeObserver(this);
    _supervisor?.cancel();
    _exportTimer?.cancel();
    _dataTimer?.cancel();
    _backend.dispose();
    unawaited(_backend.disconnect().whenComplete(_releaseLease));
    super.dispose();
  }
}

bool acceptsWhoop4Advertisement(Iterable<String> services, {String? name}) {
  final values = services.map((id) => id.toLowerCase()).toList();
  return (values.any((id) => id == kWhoopGen4.service.toLowerCase()) ||
          (name?.toLowerCase().contains('whoop') ?? false)) &&
      !values.any(
        (id) =>
            id == kWhoopGen5.service.toLowerCase() ||
            id.startsWith('0000fd4b') ||
            id == 'fd4b',
      );
}

class _NativeBridgeBackend implements BridgeBackend {
  late final BleEngine engine;
  late final BandHost host;
  late final DeriveScheduler scheduler;
  late void Function() _derived;
  DateTime? _lastHeavy;
  Profile _profile = const Profile();

  @override
  void attach({
    required void Function(DeviceState) onState,
    required void Function() onCommitted,
    required void Function(bool) onOffload,
    required void Function() onDerived,
  }) {
    _derived = onDerived;
    engine = BleEngine(
      onState: onState,
      onRecord: (sample, raw) async {
        if (ResetGate.active || engine.linkDeviceFamily != 'gen4') {
          throw StateError('Capture unavailable');
        }
        await LocalDb.insertRecord(raw, sample);
        onCommitted();
      },
      onRecordsBatch: (raws, samples) async {
        if (ResetGate.active || engine.linkDeviceFamily != 'gen4') {
          throw StateError('Capture unavailable');
        }
        await LocalDb.insertRecordsBatch(raws, samples);
      },
      onArchiveRecord: (raw) async {
        if (ResetGate.active || engine.linkDeviceFamily != 'gen4') {
          throw StateError('Capture unavailable');
        }
        await LocalDb.archiveRawRecord(raw);
      },
      onCommitBatch:
          (
            raws,
            samples,
            token, {
            archives,
            ecgRawPackets,
            deviceFamily,
          }) async {
            if (ResetGate.active || deviceFamily != 'gen4') {
              throw StateError('Refusing reset/non-WHOOP4 history');
            }
            await host.commitNativeBatch(
              raws,
              samples,
              token,
              archives: archives,
              ecgRawPackets: ecgRawPackets,
              deviceFamily: deviceFamily,
            );
            onCommitted();
          },
      cursorReader: (base) => LocalDb.getCursorInt(
        LocalDb.cursorKeyFor(base, LocalDb.kPrimaryDeviceId),
      ),
      onDataStored: onCommitted,
      onOffloadState: onOffload,
      isForegroundActive: () =>
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      log: debugPrint,
    );
    host = BandHost(
      adapter: WhoopFramedAdapter(engine, kWhoopGen4),
      deviceId: LocalDb.kPrimaryDeviceId,
    );
    scheduler = DeriveScheduler(
      run: ({required kind}) async {
        await DerivationEngine(
          log: debugPrint,
          background: true,
        ).run(_profile, heavy: kind == DeriveJobKind.heavy);
        _derived();
      },
      log: debugPrint,
      onChanged: () {},
    );
  }

  @override
  Future<void> initialize() async {
    await BridgeHealthExporter.shared.initialize();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('local_profile_json');
    if (raw != null) {
      try {
        _profile = Profile.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _profile = const Profile();
      }
    }
    await scheduler.init();
  }

  @override
  Future<PairedDevice?> loadPairing() => PairedDevice.load();
  @override
  Future<void> savePairing(PairedDevice device) => PairedDevice.save(
    device.remoteId,
    device.serial,
    generation: device.generation,
  );
  @override
  Future<void> clearPairing() => PairedDevice.clear();
  @override
  Future<DateTime?> newestDataAt() async {
    final ts = await LocalDb.lastDecodedRecTs();
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  }

  @override
  Future<void> wipe() async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (scheduler.running) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'Sleep processing still running. Try deleting again later.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    scheduler.dispose();
    await LocalDb.wipeAll();
    // Decoded-row DELETE triggers can enqueue tombstones after wipeAll has
    // already visited the outbox table. Deletion is local only: do not export
    // those tombstones into the user's retained Health Connect history.
    await (await LocalDb.instance).delete('bridge_hr_outbox');
    _profile = const Profile();
    _lastHeavy = null;
    await scheduler.init();
  }

  @override
  Future<List<ScanResult>> scan() => withScanLock(_scanLocked);

  Future<List<ScanResult>> _scanLocked() async {
    final found = <String, ScanResult>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        if (acceptsWhoop4Advertisement(
          result.advertisementData.serviceUuids.map((id) => id.str),
          name:
              '${result.device.platformName} ${result.advertisementData.advName}',
        )) {
          found[result.device.remoteId.str] = result;
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(kWhoopGen4.service)],
        timeout: const Duration(seconds: 12),
      );
      await FlutterBluePlus.isScanning.where((active) => !active).first;
      if (found.isEmpty) {
        // Some WHOOP 4 firmware advertises only its name. Discovery still has
        // to identify Gen4 before pairing is saved or history can be committed.
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
        await FlutterBluePlus.isScanning.where((active) => !active).first;
      }
      return found.values.toList();
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  @override
  Future<bool> connect(String remoteId) =>
      engine.connectToRemoteId(remoteId, generationHint: 'gen4');
  @override
  Future<void> disconnect() => engine.disconnect();
  @override
  Future<void> sync() => engine.requestHistorySync();
  @override
  Future<void> startService() => EdgeTracking.start();
  @override
  Future<void> stopService() => EdgeTracking.stop();
  @override
  Future<void> associate(String remoteId) =>
      AndroidBackground.associateCompanion(remoteId);
  @override
  Future<bool> batteryExempt() =>
      AndroidBackground.isIgnoringBatteryOptimizations();
  @override
  Future<HealthLinkState> checkHealth() => BridgeHealthExporter.shared.check();
  @override
  Future<HealthLinkState> requestHealth() =>
      BridgeHealthExporter.shared.request();
  @override
  Future<BridgeExportResult> export({bool allowLegacyMigration = false}) =>
      BridgeHealthExporter.shared.exportPending(
        allowLegacyMigration: allowLegacyMigration,
      );
  @override
  void stored() {
    scheduler.markStoredData();
    if (_lastHeavy == null ||
        DateTime.now().difference(_lastHeavy!) >= const Duration(minutes: 30)) {
      _lastHeavy = DateTime.now();
      scheduler.requestHeavy();
    }
  }

  @override
  void offload(bool active) => scheduler.setOffloadActive(active);
  @override
  void setBackground(bool background) {
    engine.setBackground(background);
    scheduler.setBackground(background);
  }

  @override
  void dispose() => scheduler.dispose();
}
