/// Adaptive frame skipper that reduces 30 FPS camera input to ~10–15 FPS
/// output for the inference pipeline.
///
/// Starts with [skipFactor] = 2, which processes 1 out of every 3 incoming
/// frames, yielding approximately 10 FPS from a 30 FPS source.
///
/// If the output FPS drops below 8 (thermal throttle or downstream bottleneck),
/// [adjustForThermal] reduces the skip factor to 1, processing every other
/// frame (~15 FPS) to maximise throughput under degraded conditions.
class FrameSkipper {
  int _skipFactor = 2;
  int _counter = 0;

  /// The current skip factor — number of frames to skip between each
  /// processed frame.
  ///
  /// Effective output FPS = 30 / (_skipFactor + 1).
  /// - 2 → ~10 FPS (default)
  /// - 1 → ~15 FPS (thermal/backpressure mode)
  int get skipFactor => _skipFactor;

  /// Returns `true` for frames that should be forwarded to the pipeline.
  ///
  /// Call this method for every incoming frame. The internal counter
  /// determines whether the current frame passes through. On `true`, the
  /// counter resets and the caller should process the frame.
  bool shouldProcessFrame() {
    final shouldProcess = _counter == 0;
    _counter = (_counter + 1) % (_skipFactor + 1);
    return shouldProcess;
  }

  /// Adjusts the skip factor based on measured output FPS.
  ///
  /// If [currentFps] falls below 8, the skip factor is reduced to 1
  /// (processes every other frame → ~15 FPS). Otherwise the current
  /// factor is retained.
  void adjustForThermal(double currentFps) {
    if (currentFps < 8) {
      _skipFactor = 1;
    }
  }

  /// Resets the skipper to its initial state (skipFactor = 2, counter = 0).
  void reset() {
    _skipFactor = 2;
    _counter = 0;
  }
}
