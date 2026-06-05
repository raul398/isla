import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inference/gesture_classifier.dart';
import '../inference/hand_landmarker.dart';
import '../inference/sequence_translator.dart';
import '../models/frame.dart';
import '../models/translation.dart';
import 'camera_provider.dart';

// ---------------------------------------------------------------------------
// Singleton Providers
// ---------------------------------------------------------------------------

/// Singleton [HandLandmarker] with automatic dispose on provider disposal.
final handLandmarkerProvider = Provider<HandLandmarker>((ref) {
  final landmarker = HandLandmarker();
  ref.onDispose(() => landmarker.dispose());
  return landmarker;
});

/// Singleton [GestureClassifier] with automatic dispose.
final gestureClassifierProvider = Provider<GestureClassifier>((ref) {
  final classifier = GestureClassifier();
  ref.onDispose(() => classifier.dispose());
  return classifier;
});

/// Singleton [SequenceTranslator] with automatic dispose.
final sequenceTranslatorProvider = Provider<SequenceTranslator>((ref) {
  final translator = SequenceTranslator();
  ref.onDispose(() => translator.dispose());
  return translator;
});

// ---------------------------------------------------------------------------
// Inference Stream Provider
// ---------------------------------------------------------------------------

/// Stream provider that connects the full inference pipeline:
///
/// ```
/// CameraImage → HandLandmarker → Landmarks (126 floats)
///                                      ↓
///                              GestureClassifier → Gesture
///                                                     ↓
///                                             SequenceTranslator → Translation
/// ```
///
/// ## States surfaced via [AsyncValue]
///
/// | AsyncValue state | Meaning                            |
/// |------------------|------------------------------------|
/// | Loading          | Models are initialising            |
/// | Data             | A new [Translation] is available   |
/// | Error            | Model load failed or stream broken |
///
/// ## Lifecycle
///
/// The provider:
/// 1. Loads the TFLite models (hand_landmarker + classifier) in parallel.
/// 2. Emits [Translation.empty()] to signal readiness.
/// 3. Subscribes to the camera frame stream from [frameStreamProvider].
/// 4. For each frame: run landmarker → classifer → translator → emit.
///
/// When no hands are detected (landmarks empty), [Translation.empty()] is
/// emitted so the UI can maintain a neutral state.
final inferenceStreamProvider = StreamProvider<Translation>((ref) {
  final controller = StreamController<Translation>();

  final landmarker = ref.read(handLandmarkerProvider);
  final classifier = ref.read(gestureClassifierProvider);
  final translator = ref.read(sequenceTranslatorProvider);

  // -----------------------------------------------------------------------
  // Step 1 — initialise models
  // -----------------------------------------------------------------------
  Future<void> initModels() async {
    try {
      await Future.wait([
        landmarker.init(),
        classifier.loadModel(),
      ]);
      // Signal readiness.
      controller.add(Translation.empty());
      debugPrint('InferenceProvider: models ready');
    } catch (e, st) {
      controller.addError(e, st);
    }
  }

  initModels();

  // -----------------------------------------------------------------------
  // Step 2 — subscribe to camera frames
  // -----------------------------------------------------------------------

  // `ref.listen` fires whenever frameStreamProvider emits a new value.
  // The callback is synchronous; async work is run in a fire-and-forget
  // helper that handles its own errors.
  ref.listen<AsyncValue<ProcessedFrame>>(
    frameStreamProvider,
    (AsyncValue<ProcessedFrame>? previous, AsyncValue<ProcessedFrame> next) {
      next.when(
        data: (frame) {
          _processFrame(
            frame: frame,
            landmarker: landmarker,
            classifier: classifier,
            translator: translator,
            controller: controller,
          );
        },
        error: (e, st) {
          // Propagate camera-level errors to the inference stream.
          controller.addError(e, st);
        },
        loading: () {
          // No frame available yet — nothing to emit.
        },
      );
    },
  );

  // -----------------------------------------------------------------------
  // Step 3 — cleanup
  // -----------------------------------------------------------------------
  ref.onDispose(() {
    controller.close();
    debugPrint('InferenceProvider: disposed');
  });

  return controller.stream;
});

// ---------------------------------------------------------------------------
// Pipeline Helpers
// ---------------------------------------------------------------------------

/// Runs landmark detection → classification → translation for one frame
/// and pipes the result into [controller].
///
/// Errors are caught internally and forwarded to [controller.addError].
Future<void> _processFrame({
  required ProcessedFrame frame,
  required HandLandmarker landmarker,
  required GestureClassifier classifier,
  required SequenceTranslator translator,
  required StreamController<Translation> controller,
}) async {
  try {
    // 1. Hand landmark detection → 126 floats or [].
    final landmarks = await landmarker.processFrame(frame);

    // 2. If no hands, emit empty translation.
    if (landmarks.isEmpty) {
      controller.add(Translation.empty());
      return;
    }

    // 3. Classify landmarks → Gesture.
    final gesture = classifier.classify(landmarks);

    // 4. Translate gesture sequence → Translation.
    final translation = translator.processGesture(gesture);

    // 5. Emit.
    controller.add(translation);
  } catch (e, st) {
    debugPrint('InferenceProvider: pipeline error: $e');
    controller.addError(e, st);
  }
}
