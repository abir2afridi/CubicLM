import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:cubiclm/services/app_log_service.dart';

/// Deduplication: identical rows collapse (count + last-seen bump),
/// any single-symbol change stays its own row.
void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(AppLogService());
  });
  tearDown(Get.reset);

  Future<AppLogService> settledLogs(WidgetTester tester) async {
    // A frame must exist for the service's post-frame flush to run.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    return Get.find<AppLogService>();
  }

  /// Flushes the service's post-frame batch: pump() alone only runs when
  /// a frame is scheduled, so schedule one explicitly.
  Future<void> flushLogs(WidgetTester tester) async {
    tester.binding.scheduleFrame();
    await tester.pump();
  }

  testWidgets('identical errors collapse to one row with count',
      (tester) async {
    final logs = await settledLogs(tester);
    logs.error('same', details: 'trace');
    logs.error('same', details: 'trace');
    logs.error('diff', details: 'trace');
    await flushLogs(tester);

    expect(logs.entries.length, 2);
    expect(logs.entries[0].message, 'diff');
    expect(logs.entries[0].count, 1);
    expect(logs.entries[1].message, 'same');
    expect(logs.entries[1].count, 2);
    expect(logs.errorCount, 3); // occurrences
    expect(logs.uniqueErrorCount, 2); // rows
    expect(
      logs.entries[1].lastAt.isAfter(logs.entries[1].timestamp) ||
          logs.entries[1].lastAt
              .isAtSameMomentAs(logs.entries[1].timestamp),
      isTrue,
    );
  });

  testWidgets('one changed symbol is a new row', (tester) async {
    final logs = await settledLogs(tester);
    logs.error('same', details: 'trace');
    logs.error('same!', details: 'trace');
    logs.error('same', details: 'trace!');
    await flushLogs(tester);

    expect(logs.entries.length, 3);
    expect(logs.errorCount, 3);
  });

  testWidgets('export renders repeats once with count header',
      (tester) async {
    final logs = await settledLogs(tester);
    logs.error('boom', details: 'stack');
    logs.error('boom', details: 'stack');
    await flushLogs(tester);

    final text = await logs.exportFullLogs();
    expect(text.contains('×2'), isTrue);
    // Body appears exactly once despite two occurrences.
    expect('stack'.allMatches(text).length, 1);
  });

  test('legacy persisted rows load with count 1', () {    final e = AppLogEntry.fromJson({
      't': DateTime.now().toIso8601String(),
      'l': 'ERROR',
      'm': 'old',
      'd': null,
      'c': 'system',
    });
    expect(e.count, 1);
    expect(e.lastAt, e.timestamp);
  });

  test('round-trip preserves count and last-seen', () {
    final e = AppLogEntry(
      level: 'ERROR',
      message: 'x',
      count: 7,
      lastAt: DateTime.now(),
    );
    final back = AppLogEntry.fromJson(e.toJson());
    expect(back.count, 7);
    expect(back.lastAt, e.lastAt);
  });

  testWidgets('GetX empty-scope hint demotes to DEBUG, never errors',
      (tester) async {
    final logs = await settledLogs(tester);
    logs.error(
        '[Get] the improper use of a GetX has been detected. foo');
    logs.warning(
        '[Get] the improper use of a GetX has been detected. bar');
    await flushLogs(tester);

    expect(logs.entries.length, 2);
    expect(logs.entries.every((e) => e.level == 'DEBUG'), isTrue);
    expect(logs.errorCount, 0);
    expect(logs.warningCount, 0);
  });

  testWidgets('framework assertion + overlay errors match patterns',
      (tester) async {
    final logs = await settledLogs(tester);
    logs.error(
        "'package:flutter/src/widgets/framework.dart': Failed assertion: line 6271 pos 12: '_dependents.isEmpty': is not true.");
    logs.error('Duplicate GlobalKeys detected in widget tree.',
        details: '_OverlayEntryWidgetState _RenderTheater');
    await flushLogs(tester);

    final titles =
        logs.detectedPatterns.map((p) => p.id).toSet();
    expect(titles.contains('flutter_framework'), isTrue);
    expect(titles.contains('overlay_issue'), isTrue);
    expect(logs.untrackedErrors, isEmpty);
  });

  testWidgets('unmatched red rows surface as untracked', (tester) async {
    final logs = await settledLogs(tester);
    logs.error('Negative prompt rejected by engine v9');
    await flushLogs(tester);

    expect(logs.untrackedErrors.length, 1);
    expect(logs.untrackedErrors.first.message,
        'Negative prompt rejected by engine v9');
  });

  testWidgets('service init failures match the service_init pattern',
      (tester) async {
    final logs = await settledLogs(tester);
    logs.error('Service DeviceInfoService failed to init',
        details: 'TimeoutException after 0:00:04');
    await flushLogs(tester);

    final ids = logs.detectedPatterns.map((p) => p.id).toSet();
    expect(ids.contains('service_init'), isTrue);
    expect(logs.untrackedErrors, isEmpty);
  });
}
