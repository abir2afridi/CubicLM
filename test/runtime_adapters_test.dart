import 'package:flutter_test/flutter_test.dart';

import 'package:cubiclm/services/runtime/framework_runtime.dart';
import 'package:cubiclm/services/runtime/project_detector.dart';

void main() {
  group('runtimeFor adapters', () {
    test('vite args bind loopback with the given port', () {
      final args = runtimeFor(ProjectKind.vite).devArgs(5174);
      expect(args, containsAll(['--host', '127.0.0.1', '--port', '5174']));
      expect(args, isNot(contains('5173')));
    });

    test('next args use -H/-p with the given port', () {
      final args = runtimeFor(ProjectKind.nextjs).devArgs(3005);
      expect(args, containsAll(['-H', '127.0.0.1', '-p', '3005']));
      expect(args, isNot(contains('3000')));
    });

    test('static has no dev process', () {
      expect(() => runtimeFor(ProjectKind.staticSite).devArgs(80),
          throwsUnsupportedError);
      expect(() => runtimeFor(ProjectKind.unknown).devArgs(80),
          throwsUnsupportedError);
    });

    test('every kind resolves a labeled adapter', () {
      for (final k in ProjectKind.values) {
        final r = runtimeFor(k);
        expect(r.label.isNotEmpty, isTrue);
      }
      // Node kinds map 1:1; static + unknown share StaticRuntime.
      expect(runtimeFor(ProjectKind.vite).kind, ProjectKind.vite);
      expect(runtimeFor(ProjectKind.nextjs).kind, ProjectKind.nextjs);
      expect(runtimeFor(ProjectKind.nodeGeneric).kind,
          ProjectKind.nodeGeneric);
    });
  });
}
