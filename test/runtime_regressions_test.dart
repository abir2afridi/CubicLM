import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Regression tests for two runtime crashes observed on 2026-08-22.
///
/// 1. `Obx` whose builder reads no observable eagerly -> GetX throws
///    "improper use of a GetX has been detected".
/// 2. `AnimatedContainer` lerping a `BoxShadow` from blurRadius 12 -> 0 with an
///    overshooting curve (`Curves.elasticOut`) -> `Shadow` asserts
///    "Text shadow blur radius should be non-negative".
void main() {
  group('Obx reactive registration', () {
    testWidgets(
        'throws when the builder reads observables only inside a deferred itemBuilder',
        (tester) async {
      final selected = 'ALL'.obs;
      // Plain (non-reactive) List: reading .length registers nothing.
      final filters = ['ALL', 'ERROR', 'WARNING'];

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 60,
            child: Obx(
              () => ListView.builder(
                itemCount: filters.length,
                itemBuilder: (context, index) {
                  // Deferred: runs during layout, AFTER notifyChildren checked.
                  final isSelected = selected.value == filters[index];
                  return Text('${filters[index]}:$isSelected');
                },
              ),
            ),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isA<String>().having(
          (e) => e,
          'message',
          contains('improper use of a GetX'),
        ),
      );
    });

    testWidgets('does not throw when an observable is read eagerly',
        (tester) async {
      final selected = 'ALL'.obs;
      final filters = ['ALL', 'ERROR', 'WARNING'];

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 60,
            child: Obx(() {
              // Eager read inside the Obx scope.
              final current = selected.value;
              return ListView.builder(
                itemCount: filters.length,
                itemBuilder: (context, index) =>
                    Text('${filters[index]}:${filters[index] == current}'),
              );
            }),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('BoxShadow lerp with overshooting curve', () {
    testWidgets('elasticOut lerp of blurRadius 12 -> 0 asserts on negative blur',
        (tester) async {
      Widget build(bool active) => MaterialApp(
            home: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.elasticOut,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: active ? 0.4 : 0.0),
                      blurRadius: active ? 12 : 0,
                    ),
                  ],
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(true));
      // Animate 12 -> 0; elasticOut overshoots t past 1.0, driving blur < 0.
      await tester.pumpWidget(build(false));
      await tester.pump(const Duration(milliseconds: 40));

      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('clamped blurRadius survives the same overshooting curve',
        (tester) async {
      Widget build(bool active) => MaterialApp(
            home: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic, // non-overshooting
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: active ? 0.4 : 0.0),
                      blurRadius: active ? 12 : 0,
                    ),
                  ],
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(true));
      await tester.pumpWidget(build(false));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(tester.takeException(), isNull);
      }
    });
  });
}
