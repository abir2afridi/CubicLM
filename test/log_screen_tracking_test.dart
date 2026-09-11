import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/app_log_service.dart';

/// Screen tracking for diagnostics: every ERROR/WARNING row stamps the
/// open screen so a pasted log pinpoints WHERE it happened. Pure stack
/// logic — safe without widget bindings.
void main() {
  AppLogService fresh() => AppLogService();

  group('screen stack', () {
    test('starts unknown', () {
      expect(fresh().currentScreen, '');
    });

    test('tab switch resets the stack', () {
      final log = fresh();
      log.pushScreen('Slide Maker');
      log.setTabScreen('Chat');
      expect(log.currentScreen, 'Chat');
      log.pushScreen('Slide Maker');
      log.setTabScreen('Explore');
      expect(log.currentScreen, 'Explore');
    });

    test('push/pop nest editors', () {
      final log = fresh();
      log.setTabScreen('Toolkit');
      log.pushScreen('Slide Maker');
      expect(log.currentScreen, 'Slide Maker');
      log.popScreen('Slide Maker');
      expect(log.currentScreen, 'Toolkit');
    });

    test('mismatched pop is harmless', () {
      final log = fresh();
      log.setTabScreen('Chat');
      log.popScreen('Something Else');
      expect(log.currentScreen, 'Chat');
      log.popScreen();
      log.popScreen();
      expect(log.currentScreen, '');
    });

    test('empty labels never enter', () {
      final log = fresh();
      log.pushScreen('');
      expect(log.currentScreen, '');
    });

    test('trail keeps newest-first history capped at 8', () {
      final log = fresh();
      for (var i = 0; i < 12; i++) {
        log.pushScreen('S$i');
      }
      expect(log.screenTrail.length, 8);
      expect(log.screenTrail.first, 'S11');
    });
  });

  group('entry screen round-trip', () {
    test('screen persists through JSON', () {
      final e = AppLogEntry(
        level: 'ERROR',
        message: 'boom',
        screen: 'Slide Maker',
      );
      final back = AppLogEntry.fromJson(e.toJson());
      expect(back.screen, 'Slide Maker');
    });

    test('missing screen defaults to blank (old files)', () {
      final back = AppLogEntry.fromJson({
        't': DateTime.now().toIso8601String(),
        'l': 'ERROR',
        'm': 'old',
      });
      expect(back.screen, '');
    });

    test('export shows the screen', () {
      final e = AppLogEntry(
        level: 'ERROR',
        message: 'boom',
        screen: 'Slide Maker',
      );
      expect(e.formatForExport(), contains('[screen=Slide Maker]'));
    });
  });
}
