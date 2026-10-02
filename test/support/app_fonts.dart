// The type the app actually ships on Android, registered for the test harness.
//
// lib/ui2 asks for the platform face first ('.SF Pro Text' for text, '.SF Pro
// Display' for numerals) and falls back to the bundled Inter / Inter Display.
// The harness has no SF, so without this it would draw every glyph in its
// square fallback font — and the overflow sweeps would be measuring boxes,
// not the type a non-Apple user sees. Registering Inter under the platform
// names too makes the sweeps measure exactly what Android renders.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

Future<void> _load(List<String> families, List<String> files) async {
  for (final family in families) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File(f)
          .readAsBytes()
          .then((b) => ByteData.sublistView(Uint8List.fromList(b))));
    }
    await loader.load();
  }
}

/// Inter as the text face and Inter Display as the numeral face, each under
/// both its own name and the platform name lib/ui2 asks for first.
Future<void> loadShippedFonts() async {
  const dir = 'assets/fonts/Inter';
  await _load(const ['Inter', '.SF Pro Text'], [
    for (final w in const ['Regular', 'Medium', 'SemiBold', 'Bold'])
      '$dir/Inter-$w.ttf',
  ]);
  await _load(const ['Inter Display', '.SF Pro Display'], [
    for (final w in const ['SemiBold', 'Bold']) '$dir/InterDisplay-$w.ttf',
  ]);
}
