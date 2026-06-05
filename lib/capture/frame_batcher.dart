import 'dart:async';

import '../models/frame.dart';

/// Circular buffer that accumulates [ProcessedFrame]s into configurable batches.
///
/// When the buffer reaches [batchSize] frames, the batch is emitted on
/// [batchStream] and the buffer resets. If frames arrive faster than they are
/// consumed and the buffer overflows, the oldest frames are dropped (circular
/// overwrite behaviour).
///
/// Default batch size is 3, matching the spec's recommended pipeline batching
/// configuration for the downstream hand landmarker.
class FrameBatcher {
  final int batchSize;
  final List<ProcessedFrame> _buffer = [];
  final StreamController<List<ProcessedFrame>> _controller;

  /// Creates a batcher that emits batches of [batchSize] frames.
  ///
  /// [batchSize] must be >= 1. Defaults to 3.
  FrameBatcher({this.batchSize = 3})
      : assert(batchSize >= 1, 'batchSize must be >= 1'),
        _controller = StreamController<List<ProcessedFrame>>.broadcast();

  /// Adds a [frame] to the internal buffer.
  ///
  /// If the buffer is full and the previous batch has not been consumed, the
  /// oldest frame is silently dropped (circular FIFO overwrite).
  /// When the buffer reaches [batchSize], the complete batch is emitted.
  void addFrame(ProcessedFrame frame) {
    if (_buffer.length >= batchSize) {
      _buffer.removeAt(0);
    }
    _buffer.add(frame);

    if (_buffer.length == batchSize) {
      _controller.add(List<ProcessedFrame>.unmodifiable(_buffer));
      _buffer.clear();
    }
  }

  /// A broadcast stream that emits completed batches as [List<ProcessedFrame>].
  Stream<List<ProcessedFrame>> get batchStream => _controller.stream;

  /// Closes the internal stream controller and clears the buffer.
  ///
  /// The batcher must not be used after this call.
  void dispose() {
    _buffer.clear();
    _controller.close();
  }
}
