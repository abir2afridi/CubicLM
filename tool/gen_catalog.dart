// Generates assets/catalog/models.json from AppConstants.availableModels.
//
// Run: `dart run tool/gen_catalog.dart`
// The JSON is fetched over-the-air by ModelController (with the Dart const
// list as fallback). After editing the catalog in lib/core/constants.dart,
// re-run this script and commit both files.
import 'dart:convert';
import 'dart:io';

import 'package:cubiclm/core/constants.dart';

Future<void> main() async {
  final payload = {
    'version': 1,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'models': AppConstants.availableModels,
  };
  final out = File('assets/catalog/models.json');
  await out.parent.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  await out.writeAsString('${encoder.convert(payload)}\n');
  // ignore: avoid_print
  print(
      'Wrote ${out.path} (${AppConstants.availableModels.length} models)');
}
