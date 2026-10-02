// The type the app ships, loaded into the test harness.
//
// Read from the bundle's FontManifest.json — every family the app declares in
// pubspec.yaml plus every package font (the Lucide icon glyphs) — so a face
// added to or dropped from the app is added to or dropped from every golden
// and width assertion at the same moment. Without it the harness measures its
// fallback block glyphs, and a width assertion against the wrong font is a
// width assertion against nothing.
import 'dart:convert';

import 'package:flutter/services.dart';

Future<void> loadAppType() async {
  final manifest = jsonDecode(
      await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final fam in manifest) {
    final loader = FontLoader((fam as Map)['family'] as String);
    for (final f in (fam['fonts'] as List)) {
      loader.addFont(rootBundle.load((f as Map)['asset'] as String));
    }
    await loader.load();
  }
}
