import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'app.dart';
import 'bridge/coordinator.dart';

/// One coordinator for Activity, boot, companion presence and service recovery.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    try {
      await Future.wait([
        Workmanager().cancelByUniqueName('openstrap.derive.heavy'),
        Workmanager().cancelByUniqueName('openstrap.sync'),
      ]).timeout(const Duration(seconds: 6));
    } catch (error) {
      debugPrint('[bridge] legacy-job cleanup: $error');
    }
  }
  try {
    await FlutterBluePlus.setLogLevel(
      LogLevel.none,
      color: false,
    ).timeout(const Duration(seconds: 6));
  } catch (error) {
    debugPrint('[bridge] Bluetooth setup: $error');
  }
  final coordinator = BridgeCoordinator();
  runApp(BridgeApp(coordinator: coordinator));
  unawaited(coordinator.initialize());
}
