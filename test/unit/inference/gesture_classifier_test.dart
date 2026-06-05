import 'package:flutter_test/flutter_test.dart';

import 'package:isla/inference/gesture_classifier.dart';

void main() {
  group('GestureClassifier', () {
    late GestureClassifier classifier;

    setUp(() {
      classifier = GestureClassifier();
    });

    tearDown(() {
      classifier.dispose();
    });

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    test('confidence threshold is 0.6 (spec: gesture-classifier edge)', () {
      expect(GestureClassifier.confidenceThreshold, 0.6);
    });

    test('numClasses returns 38 (26 letters + 12 word gestures)', () {
      expect(classifier.numClasses, 38);
    });

    test('initial state is not initialized', () {
      expect(classifier.isInitialized, isFalse);
    });

    // -------------------------------------------------------------------------
    // Error — model not loaded
    // -------------------------------------------------------------------------
    test('classify returns model_not_ready when loadModel was not called '
        '(spec: gesture-classifier edge)', () {
      final gesture = classifier.classify(List.filled(126, 0.5));

      expect(gesture.label, 'model_not_ready',
          reason: 'controlled error, not a crash');
      expect(gesture.confidence, 0.0);
      expect(gesture.timestamp, isNotNull);
    });

    // -------------------------------------------------------------------------
    // NOTE on coverage gap
    // -------------------------------------------------------------------------
    // The following scenarios from the spec REQUIRE a real .tflite model
    // (or a dependency injection point for a mock Interpreter, which the
    // current implementation does not expose):
    //
    // 1. Happy path: valid landmarks → Gesture with label + confidence > 0.6
    //    Requires: _interpreter.run() returning a Float64List where the
    //    argmax ≥ 0.6.
    //
    // 2. Threshold: confidence < 0.6 → label "unknown"
    //    Requires: _interpreter.run() returning a Float64List where the
    //    argmax < 0.6.
    //
    // 3. Interpreter runtime crash → Gesture(label: "error", confidence: 0.0)
    //
    // These tests will be enabled when the project adds a test model fixture
    // or exposes interpreter injection. For now, the integration test
    // (pipeline_test.dart) exercises the full data path at the
    // SequenceTranslator + CaptionProvider level.
    //
    // See also: sdd/core-pipeline-senas/design — GestureClassifier DI
    // is a known future enhancement for Phase 6 (hardening).
  });
}
