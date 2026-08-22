import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:cubiclm/services/app_log_service.dart';
import 'package:cubiclm/views/log_view.dart';

/// Mounts the real LogView to prove the GetX "improper use" throw is gone.
void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(AppLogService());
  });
  tearDown(Get.reset);

  testWidgets('LogView mounts without the GetX improper-use error',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogView()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('ALL'), findsOneWidget);
  });

  testWidgets('tapping a filter chip rebuilds via the Obx', (tester) async {
    final logs = Get.find<AppLogService>();
    logs.error('boom');
    logs.info('hello');

    await tester.pumpWidget(const MaterialApp(home: LogView()));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Scope to the chip: "ERROR" also appears as a log entry's level text.
    final errorChip = find.descendant(
      of: find.byType(ChoiceChip),
      matching: find.text('ERROR'),
    );
    expect(errorChip, findsOneWidget);

    await tester.tap(errorChip);
    await tester.pump();
    // A rebuild happened and no reactive-scope error was thrown.
    expect(tester.takeException(), isNull);
  });
}
