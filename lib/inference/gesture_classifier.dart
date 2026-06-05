import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/gesture.dart';

/// MLP gesture classifier powered by TFLite.
///
/// Loads a small MLP model (~45 KB) from `assets/models/classifier.tflite`.
///
/// ## Contract
///
/// | Input              | Output              |
/// |--------------------|---------------------|
/// | 126 normalized floats (hand landmarks) | [Gesture] with label + confidence |
///
/// Confidence threshold: > 60 %. Predictions below this are classified as
/// `"unknown"` per spec (no false positives above 60 %).
///
/// ## Error handling
///
/// - Missing / corrupt model file → [isInitialized] = false;
///   [classify] returns `Gesture(label: "model_not_ready", confidence: 0.0)`.
/// - Wrong input size (≠ 126) → `Gesture(label: "unknown", confidence: 0.0)`.
/// - Inference runtime failure → `Gesture(label: "error", confidence: 0.0)`.
///
/// TODO: Place the actual classifier.tflite model at
/// `assets/models/classifier.tflite` before use.
class GestureClassifier {
  Interpreter? _interpreter;
  bool _initialized = false;

  /// Gesture labels supported by the classifier.
  ///
  /// Order must match the model's output logits / softmax index.
  ///
  /// TODO: Replace this list with the exact label set from training data
  /// (WLASL subset, LSA64, or a custom dataset for Argentine Sign Language).
  static const List<String> _labels = [
    // Manual alphabet (LSA / LSA64 subset).
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z',
    // Common word gestures.
    'hola',
    'gracias',
    'por_favor',
    'adios',
    'si',
    'no',
    'ayuda',
    'agua',
    'comida',
    'casa',
    'familia',
    'amigo',
  ];

  /// Confidence threshold: predictions below this are mapped to `"unknown"`.
  static double get confidenceThreshold => 0.6;

  /// Whether the model was loaded successfully.
  bool get isInitialized => _initialized;

  /// Number of label classes the model expects.
  int get numClasses => _labels.length;

  /// Loads the classifier.tflite model from Flutter assets.
  ///
  /// The model is a small MLP with input shape `[1, 126]` and output shape
  /// `[1, numClasses]`.
  ///
  /// Does **not** throw on failure — check [isInitialized] after calling.
  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions();
      // CPU is the default delegate in tflite_flutter.
      _interpreter = await Interpreter.fromAsset(
        'models/classifier.tflite',
        options: options,
      );
      _initialized = true;
      debugPrint(
        'GestureClassifier: model loaded ($_labels.length labels)',
      );
    } catch (e) {
      _initialized = false;
      debugPrint('GestureClassifier: failed to load model: $e');
    }
  }

  /// Classifies a 126-element landmark vector into a [Gesture].
  ///
  /// Returns a gesture with:
  /// - `"unknown"` label if the highest confidence is ≤ 60 %.
  /// - `"model_not_ready"` if [loadModel] hasn't been called or failed.
  /// - `"error"` if an inference runtime error occurred.
  Gesture classify(List<double> landmarks) {
    if (!_initialized || _interpreter == null) {
      return Gesture(
        label: 'model_not_ready',
        confidence: 0.0,
        timestamp: DateTime.now(),
      );
    }

    if (landmarks.length != 126) {
      debugPrint(
        'GestureClassifier: expected 126 landmarks, got ${landmarks.length}',
      );
      return Gesture(
        label: 'unknown',
        confidence: 0.0,
        timestamp: DateTime.now(),
      );
    }

    try {
      // Wrap input in nested lists matching [1, 126] shape.
      final input = [landmarks];
      // Output buffer matching [1, numClasses].
      final outputBuffer = Float64List(_labels.length);
      final output = [outputBuffer];

      _interpreter!.run(input, output);

      return _parseOutput(outputBuffer);
    } catch (e) {
      debugPrint('GestureClassifier: inference error: $e');
      return Gesture(
        label: 'error',
        confidence: 0.0,
        timestamp: DateTime.now(),
      );
    }
  }

  /// Finds the argmax of the softmax/logits vector and applies the threshold.
  Gesture _parseOutput(Float64List scores) {
    var maxScore = 0.0;
    var maxIndex = 0;

    for (var i = 0; i < scores.length; i++) {
      if (scores[i] > maxScore) {
        maxScore = scores[i];
        maxIndex = i;
      }
    }

    // Clamp to valid range.
    final confidence = maxScore.clamp(0.0, 1.0);

    final label =
        confidence > confidenceThreshold ? _labels[maxIndex] : 'unknown';

    return Gesture(
      label: label,
      confidence: confidence,
      timestamp: DateTime.now(),
    );
  }

  /// Releases the TFLite interpreter.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _initialized = false;
    debugPrint('GestureClassifier: disposed');
  }
}
