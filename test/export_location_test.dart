import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/utils/export_file.dart';

/// Export destination helpers: the subfolder name comes from user input,
/// so it must be sanitized before it ever reaches MediaStore or the
/// filesystem. Pure logic — no platform channels involved.
void main() {
  group('sanitizeExportSubfolder', () {
    test('keeps normal names untouched', () {
      expect(ExportFile.sanitizeExportSubfolder('CubicLM'), 'CubicLM');
      expect(ExportFile.sanitizeExportSubfolder('My Exports'), 'My Exports');
    });

    test('strips filesystem-illegal characters', () {
      expect(ExportFile.sanitizeExportSubfolder('a/b\\c:d*e?f"g<h>i|j'),
          'abcdefghij');
    });

    test('collapses whitespace and trims', () {
      expect(
          ExportFile.sanitizeExportSubfolder('  lots   of   space  '),
          'lots of space');
    });

    test('rejects blank and dot-only names', () {
      expect(ExportFile.sanitizeExportSubfolder(''), '');
      expect(ExportFile.sanitizeExportSubfolder('   '), '');
      expect(ExportFile.sanitizeExportSubfolder('.'), '');
      expect(ExportFile.sanitizeExportSubfolder('..'), '');
    });

    test('caps length at 32 chars', () {
      final long = List.filled(50, 'a').join();
      expect(ExportFile.sanitizeExportSubfolder(long).length, 32);
    });
  });
}
