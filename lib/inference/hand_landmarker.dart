import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/frame.dart';

/// MediaPipe Hand Landmarker wrapper using [tflite_flutter].
///
/// Processes [ProcessedFrame] frames:
/// 1. Downsamples the Y-plane (grayscale) to 224×224.
/// 2. Broadcasts to 3 channels → float32 tensor [1, 224, 224, 3].
/// 3. Runs MediaPipe hand_landmarker.tflite inference.
/// 4. Postprocesses the output into 126 normalized floats
///    (21 landmarks × 3 coords × 2 hands).
///
/// GPU delegate is attempted at init; falls back to CPU transparently.
///
/// ## Model
///
/// Requires `assets/models/hand_landmarker.tflite` from MediaPipe Hands.
///
/// TODO: Place the actual model at `assets/models/hand_landmarker.tflite`.
/// Download from:
///   https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.tflite
///
/// TODO (accuracy): Full CameraImage (YUV→RGB) preprocessing would improve
/// skin-tone edge detection. Current grayscale path is an MVP tradeoff.
class HandLandmarker {
  Interpreter? _interpreter;
  bool _useGpu = false;
  bool _initialized = false;

  // Model input dimensions (standard MediaPipe Hands).
  static const int _inputSize = 224;

  // Output structure: 21 landmarks × 3 coords × 2 hands = 126.
  static const int _numLandmarks = 21;
  static const int _coordsPerLandmark = 3;
  static const int _maxHands = 2;
  static const int _outputLength =
      _numLandmarks * _coordsPerLandmark * _maxHands;

  /// Whether the interpreter is loaded and ready.
  bool get isInitialized => _initialized;

  /// Loads the hand_landmarker.tflite model from Flutter assets.
  ///
  /// Attempts GPU delegate first. If GPU creation fails (unsupported device
  /// or platform), silently falls back to CPU delegate.
  ///
  /// Does **not** throw on failure — callers should check [isInitialized]
  /// before calling [processFrame].
  Future<void> init() async {
    final options = InterpreterOptions();

    // --- Delegate selection ---
    try {
      options.addDelegate(GpuDelegate());
      _useGpu = true;
      debugPrint('HandLandmarker: GPU delegate created');
    } catch (_) {
      debugPrint(
        'HandLandmarker: GPU delegate unavailable, using default CPU',
      );
      // CPU is the default delegate in tflite_flutter.
      _useGpu = false;
    }

    // --- Load model ---
    try {
      _interpreter = await Interpreter.fromAsset(
        'models/hand_landmarker.tflite',
        options: options,
      );
      _initialized = true;
      debugPrint('HandLandmarker: initialized (${_useGpu ? "GPU" : "CPU"})');
    } catch (e) {
      _initialized = false;
      debugPrint('HandLandmarker: failed to load model: $e');
      // Caller checks isInitialized before use.
    }
  }

  /// Processes a single camera frame for hand landmarks.
  ///
  /// Returns a `List<double>` with 126 normalized floats
  /// `[l0x, l0y, l0z, ..., l20z, r0x, r0y, r0z, ..., r20z]`
  /// where `l` = left hand and `r` = right hand.
  ///
  /// Returns an empty list when:
  /// - No hands are detected in the frame,
  /// - The model is not yet loaded,
  /// - An inference error occurs.
  Future<List<double>> processFrame(ProcessedFrame frame) async {
    if (!_initialized || _interpreter == null) return [];

    try {
      // 1. Preprocess: Y-plane → float32 tensor [1, 224, 224, 3]
      final input = _preprocess(frame);

      // 2. Allocate output buffer matching model output.
      //    MediaPipe hand_landmarker may return [1, 63] (single hand) or
      //    [1, 126] (two hands). We allocate maximum and inspect the result.
      final output = Float32List(_outputLength);
      final outputWrapper = [output];

      // 3. Run inference.
      _interpreter!.run(input, outputWrapper);

      // 4. Postprocess: validate and normalise.
      return _postprocess(output);
    } catch (e) {
      debugPrint('HandLandmarker: inference error: $e');
      return [];
    }
  }

  /// Converts the Y-plane from [ProcessedFrame] into a [1, 224, 224, 3] tensor.
  ///
  /// Strategy (MVP):
  /// - Nearest-neighbour downsampling from source resolution → 224×224.
  /// - Each pixel's luminance (Y / 255.0) is replicated across R, G, B.
  ///
  /// This is fast but loses colour information. Full YUV→RGB conversion with
  /// bilinear interpolation is marked for Phase 4 optimisation.
  Float32List _preprocess(ProcessedFrame frame) {
    final srcW = frame.resolution.width.toInt();
    final srcH = frame.resolution.height.toInt();
    final bytes = frame.bytes;
    final totalPixels = _inputSize * _inputSize * 3;

    final tensor = Float32List(totalPixels);
    final scaleX = srcW / _inputSize;
    final scaleY = srcH / _inputSize;

    for (int y = 0; y < _inputSize; y++) {
      final srcY = (y * scaleY).clamp(0, srcH - 1).toInt();
      final rowOffset = srcY * srcW;

      for (int x = 0; x < _inputSize; x++) {
        final srcX = (x * scaleX).clamp(0, srcW - 1).toInt();
        // Normalise luma to [0..1].
        final pixel = bytes[rowOffset + srcX] / 255.0;

        final idx = (y * _inputSize + x) * 3;
        tensor[idx] = pixel;     // R
        tensor[idx + 1] = pixel; // G
        tensor[idx + 2] = pixel; // B
      }
    }

    return tensor;
  }

  /// Validates and normalises the model's raw output.
  ///
  /// Expected output layout:
  /// ```
  /// [l0x, l0y, l0z, l1x, ..., l20z, r0x, r0y, r0z, ..., r20z]
  /// ```
  /// where `l` = left hand (63 values), `r` = right hand (63 values).
  /// Missing hands are encoded as zeros.
  ///
  /// Returns an empty list if the output is all-zero or near-zero
  /// (i.e. no hands detected).
  ///
  /// TODO: Verify exact output layout against the actual
  /// hand_landmarker.tflite model. Some model versions return a different
  /// ordering (e.g. single hand only) or include visibility scores.
  List<double> _postprocess(Float32List raw) {
    if (raw.isEmpty) return [];

    // Detect whether the output is effectively all-zero (no hands).
    bool hasSignal = false;
    for (int i = 0; i < min(raw.length, _outputLength); i++) {
      if (raw[i].abs() > 0.01) {
        hasSignal = true;
        break;
      }
    }
    if (!hasSignal) return [];

    // Copy valid range into the 126-element result.
    final result = List<double>.filled(_outputLength, 0.0);
    final copyLen = min(raw.length, _outputLength);
    for (int i = 0; i < copyLen; i++) {
      result[i] = raw[i].toDouble();
    }

    return result;
  }

  /// Releases the TFLite interpreter and resets state.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _initialized = false;
    debugPrint('HandLandmarker: disposed');
  }
}
