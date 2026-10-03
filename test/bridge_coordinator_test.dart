import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openstrap_edge/ble/adapters/_registry.dart';
import 'package:openstrap_edge/bridge/coordinator.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_edge/health/bridge_health_export.dart';
import 'package:openstrap_edge/sync/band_ownership.dart';
import 'package:openstrap_edge/sync/paired_device.dart';

class FakeBackend implements BridgeBackend {
  PairedDevice? saved;
  late void Function(DeviceState) reportState;
  late void Function() committed;
  late void Function(bool) reportOffload;
  int connects = 0;
  int disconnects = 0;
  int exports = 0;
  int storedCalls = 0;
  bool holdOffload = false;
  bool service = false;
  bool throwScan = false;
  bool throwService = false;
  bool throwExport = false;
  bool wiped = false;
  DateTime? newest;
  int dataQueries = 0;
  final List<bool> legacyMigrationRequests = [];
  Completer<bool>? connection;
  Completer<BridgeExportResult>? exportResult;

  @override
  void attach({
    required void Function(DeviceState) onState,
    required void Function() onCommitted,
    required void Function(bool) onOffload,
    required void Function() onDerived,
  }) {
    reportState = onState;
    committed = onCommitted;
    reportOffload = onOffload;
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<PairedDevice?> loadPairing() async => saved;
  @override
  Future<void> savePairing(PairedDevice device) async {
    saved = device;
  }

  @override
  Future<void> clearPairing() async {
    saved = null;
  }

  @override
  Future<DateTime?> newestDataAt() async {
    dataQueries++;
    return newest;
  }

  @override
  Future<void> wipe() async {
    expect(service, isFalse);
    expect(saved, isNull);
    wiped = true;
  }

  @override
  Future<List<ScanResult>> scan() async {
    if (throwScan) throw StateError('Bluetooth off');
    return [];
  }

  @override
  Future<bool> connect(String remoteId) async {
    connects++;
    final ok = connection == null ? true : await connection!.future;
    if (ok) {
      reportState(DeviceState(connection: 'connected')..generation = 'gen4');
    }
    return ok;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    reportState(DeviceState());
  }

  @override
  Future<void> sync() async {}
  @override
  Future<void> startService() async {
    if (throwService) throw StateError('Background start denied');
    service = true;
  }

  @override
  Future<void> stopService() async {
    service = false;
  }

  @override
  Future<void> associate(String remoteId) async {}
  @override
  Future<bool> batteryExempt() async => true;
  @override
  Future<HealthLinkState> checkHealth() async => HealthLinkState.ready;
  @override
  Future<HealthLinkState> requestHealth() async => HealthLinkState.ready;
  @override
  Future<BridgeExportResult> export({bool allowLegacyMigration = false}) async {
    exports++;
    legacyMigrationRequests.add(allowLegacyMigration);
    if (throwExport) throw StateError('permission denied');
    return exportResult == null
        ? const BridgeExportResult(heartRateMinutes: 1)
        : await exportResult!.future;
  }

  @override
  void stored() {
    storedCalls++;
  }

  @override
  void offload(bool active) {
    holdOffload = active;
  }

  @override
  void setBackground(bool background) {}
  @override
  void dispose() {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BandOwnership.resetForTest();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  });

  test(
    'scan accepts Gen4 UUID or name-only fallback, rejects explicit Gen5',
    () {
      expect(acceptsWhoop4Advertisement([kWhoopGen4.service]), isTrue);
      expect(acceptsWhoop4Advertisement([kWhoopGen5.service]), isFalse);
      expect(acceptsWhoop4Advertisement([kWhoopGen4.service, 'fd4b']), isFalse);
      expect(acceptsWhoop4Advertisement([]), isFalse);
      expect(acceptsWhoop4Advertisement([], name: 'WHOOP 4'), isTrue);
      expect(acceptsWhoop4Advertisement(['fd4b'], name: 'WHOOP'), isFalse);
    },
  );

  test(
    'freshness uses newest physiological timestamp and coalesces commit queries',
    () async {
      final old = DateTime(2024, 1, 2);
      final backend = FakeBackend()..newest = old;
      final coordinator = BridgeCoordinator(
        backend: backend,
        dataRefreshDelay: const Duration(milliseconds: 1),
      );
      await coordinator.initialize();
      expect(coordinator.lastDataAt, old);
      backend.committed();
      backend.committed();
      backend.committed();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(coordinator.lastDataAt, old);
      expect(backend.dataQueries, 2);
      coordinator.dispose();
    },
  );

  test(
    'automatic exports never request legacy reads even with visible UI',
    () async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      SharedPreferences.setMockInitialValues({kHealthSyncEnabledKey: true});
      final backend = FakeBackend();
      final coordinator = BridgeCoordinator(
        backend: backend,
        exportDelay: const Duration(milliseconds: 1),
      );
      await coordinator.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.legacyMigrationRequests, [false]);
      await coordinator.syncNow();
      expect(backend.legacyMigrationRequests, [false, true]);
      coordinator.dispose();
    },
  );

  test('saved Gen5 never starts service or connects', () async {
    final backend = FakeBackend()
      ..saved = PairedDevice('wrong', null, generation: 'gen5');
    final coordinator = BridgeCoordinator(backend: backend);
    await coordinator.initialize();
    expect(backend.connects, 0);
    expect(backend.service, isFalse);
    expect(coordinator.error, contains('WHOOP 5/MG'));
    coordinator.dispose();
  });

  test(
    'saved pause survives initialization and blocks headless reconnect',
    () async {
      SharedPreferences.setMockInitialValues({kBridgeSyncPausedKey: true});
      final backend = FakeBackend()
        ..saved = PairedDevice('band', null, generation: 'gen4');
      final coordinator = BridgeCoordinator(backend: backend);
      await coordinator.initialize();
      expect(coordinator.paused, isTrue);
      expect(backend.connects, 0);
      expect(backend.service, isFalse);
      coordinator.dispose();
    },
  );

  test(
    'pausing while connect awaits never leaves a late connection running',
    () async {
      final backend = FakeBackend()
        ..saved = PairedDevice('band', null, generation: 'gen4')
        ..connection = Completer<bool>();
      final coordinator = BridgeCoordinator(backend: backend);
      await coordinator.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(backend.connects, 1);
      await coordinator.setPaused(true);
      backend.connection!.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.state.connection, 'disconnected');
      expect(coordinator.busy, isFalse);
      expect(backend.service, isFalse);
      expect(BandOwnership.owner, isNull);
      coordinator.dispose();
    },
  );

  test(
    'deletion pauses, disconnects and clears pairing before wiping data',
    () async {
      final backend = FakeBackend()
        ..saved = PairedDevice('band', null, generation: 'gen4');
      final coordinator = BridgeCoordinator(backend: backend);
      await coordinator.initialize();
      await coordinator.deleteLocalData();
      expect(backend.wiped, isTrue);
      expect(coordinator.paused, isTrue);
      expect(coordinator.paired, isNull);
      expect(BandOwnership.owner, isNull);
      coordinator.dispose();
    },
  );

  test(
    'manual sync during automatic export queues a foreground migration',
    () async {
      SharedPreferences.setMockInitialValues({kHealthSyncEnabledKey: true});
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final backend = FakeBackend()
        ..exportResult = Completer<BridgeExportResult>();
      final coordinator = BridgeCoordinator(
        backend: backend,
        exportDelay: const Duration(milliseconds: 1),
      );
      await coordinator.initialize();
      backend.committed();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.legacyMigrationRequests, [false]);
      await coordinator.syncNow();
      final flight = backend.exportResult!;
      backend.exportResult = null;
      flight.complete(const BridgeExportResult(heartRateMinutes: 1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.legacyMigrationRequests, [false, true]);
      coordinator.dispose();
    },
  );

  test(
    'startup service failure remains retryable and clears old error',
    () async {
      final backend = FakeBackend()
        ..saved = PairedDevice('band4', '4', generation: 'gen4')
        ..throwService = true;
      final coordinator = BridgeCoordinator(
        backend: backend,
        retryInterval: const Duration(milliseconds: 5),
      );
      await coordinator.initialize();
      expect(coordinator.initialized, false);
      expect(
        coordinator.initializationError,
        contains('Background start denied'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.connects, 0);
      backend.throwService = false;
      await coordinator.initialize();
      expect(coordinator.initialized, true);
      expect(coordinator.initializationError, isNull);
      coordinator.dispose();
    },
  );

  test('scan failure clears scanning and permits retry', () async {
    final backend = FakeBackend()..throwScan = true;
    final coordinator = BridgeCoordinator(backend: backend);
    await coordinator.initialize();
    await coordinator.scan();
    expect(coordinator.scanning, isFalse);
    expect(coordinator.error, contains('Bluetooth off'));
    backend.throwScan = false;
    await coordinator.scan();
    expect(coordinator.error, isNull);
    coordinator.dispose();
  });

  test(
    'committed bursts export independently while offload holds derivation',
    () async {
      SharedPreferences.setMockInitialValues({kHealthSyncEnabledKey: true});
      final backend = FakeBackend();
      final coordinator = BridgeCoordinator(
        backend: backend,
        exportDelay: const Duration(milliseconds: 1),
      );
      await coordinator.initialize();
      backend.reportOffload(true);
      backend.committed();
      backend.committed();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.storedCalls, 2);
      expect(backend.exports, 1);
      expect(backend.holdOffload, isTrue);
      expect(coordinator.lastExportAt, isNotNull);
      coordinator.dispose();
    },
  );

  test(
    'failed export retries successfully and does not publish success time',
    () async {
      SharedPreferences.setMockInitialValues({kHealthSyncEnabledKey: true});
      final backend = FakeBackend()..throwExport = true;
      final coordinator = BridgeCoordinator(
        backend: backend,
        exportDelay: const Duration(milliseconds: 1),
      );
      await coordinator.initialize();
      await coordinator.syncNow();
      expect(coordinator.lastExportAt, isNull);
      backend.throwExport = false;
      await coordinator.syncNow();
      expect(coordinator.lastExportAt, isNotNull);
      coordinator.dispose();
    },
  );
}
