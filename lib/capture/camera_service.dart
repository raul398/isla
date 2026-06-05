import 'dart:async';

import 'package:camera/camera.dart';

/// Wraps the [CameraController] and exposes a raw frame stream.
///
/// Responsibilities:
/// - Selects the front camera (falls back to rear, then throws).
/// - Initialises at 1280×720 (medium preset, Android Phase 1).
/// - Exposes a broadcast [Stream] of [CameraImage] at native 30 FPS.
/// - Manages controller lifecycle via [dispose].
///
/// The image stream starts when the first listener subscribes and stops
/// when the last listener cancels (lazy start/stop via broadcast controller).
class CameraService {
  CameraController? _controller;
  StreamController<CameraImage>? _frameController;
  bool _initialized = false;

  /// Whether [initCamera] completed successfully.
  bool get isInitialized => _initialized;

  /// Initialises the front camera at 1280×720 (medium preset).
  ///
  /// Camera selection: front → rear → [CameraException].
  /// Audio is disabled (sign language capture does not need mic input).
  Future<void> initCamera() async {
    final cameras = await availableCameras();
    final camera = _selectCamera(cameras);

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();

    // Broadcast controller: starts image delivery on first subscriber,
    // stops on last cancellation — avoids wasting resources when idle.
    _frameController = StreamController<CameraImage>.broadcast(
      onListen: () {
        _controller!
            .startImageStream((image) => _frameController!.add(image))
            .catchError((Object e) {
          _frameController?.addError(e);
        });
      },
      onCancel: () {
        _controller?.stopImageStream();
      },
    );

    _initialized = true;
  }

  /// A broadcast stream of raw camera frames at native 30 FPS.
  ///
  /// Throws [StateError] if [initCamera] has not been called.
  /// The stream delivers frames only while at least one listener is active.
  Stream<CameraImage> get frameStream {
    _ensureInitialized();
    return _frameController!.stream;
  }

  /// Selects the front camera, falling back to rear.
  ///
  /// Throws [CameraException] if neither camera is available.
  CameraDescription _selectCamera(List<CameraDescription> cameras) {
    for (final cam in cameras) {
      if (cam.lensDirection == CameraLensDirection.front) return cam;
    }
    for (final cam in cameras) {
      if (cam.lensDirection == CameraLensDirection.back) return cam;
    }
    throw CameraException(
      'NoCameraAvailable',
      'No front or rear camera found on this device.',
    );
  }

  void _ensureInitialized() {
    if (!_initialized || _controller == null) {
      throw StateError(
        'CameraService not initialized. Call initCamera() first.',
      );
    }
  }

  /// Releases all camera resources.
  ///
  /// Safe to call multiple times. After disposal the service must be
  /// re-initialised via [initCamera] before further use.
  Future<void> dispose() async {
    _initialized = false;
    await _controller?.stopImageStream();
    await _controller?.dispose();
    await _frameController?.close();
    _controller = null;
    _frameController = null;
  }
}
