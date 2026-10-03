import 'dart:io';
import 'package:flutter/services.dart';

/// Connected-device foreground service retains the single bridge engine.
class EdgeTracking {
  static const _channel = MethodChannel('openstrap/edge_tracking');
  static Future<void> start() async {
    if (Platform.isAndroid) await _channel.invokeMethod('start');
  }

  static Future<void> stop() async {
    if (Platform.isAndroid) await _channel.invokeMethod('stop');
  }
}
