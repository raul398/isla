import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// A processed camera frame ready for inference.
///
/// Wraps raw camera bytes together with capture metadata so downstream layers
/// (frame skipper, hand landmarker) don't need to know about the camera
/// controller internals.
class ProcessedFrame {
  /// Raw image bytes in the platform's native format (NV21 on Android).
  final Uint8List bytes;

  /// Capture resolution (width × height) of this frame.
  final Size resolution;

  /// Monotonic timestamp when the frame was captured.
  final DateTime timestamp;

  const ProcessedFrame({
    required this.bytes,
    required this.resolution,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProcessedFrame &&
          timestamp == other.timestamp &&
          resolution == other.resolution &&
          bytes == other.bytes;

  @override
  int get hashCode => Object.hash(timestamp, resolution, Object.hashAll(bytes));
}
