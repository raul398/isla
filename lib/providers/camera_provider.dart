import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../capture/camera_service.dart';
import '../capture/frame_skipper.dart';
import '../models/frame.dart';

// ---------------------------------------------------------------------------
// Camera Service Provider
// ---------------------------------------------------------------------------

/// Singleton provider that creates and manages the [CameraService] lifecycle.
///
/// The service is initialised on first access. [ref.onDispose] guarantees
/// that the underlying camera controller is released when the provider is
/// disposed (e.g. when leaving the capture screen).
final cameraServiceProvider = Provider<CameraService>((ref) {
  final service = CameraService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ---------------------------------------------------------------------------
// Camera Initialisation Provider
// ---------------------------------------------------------------------------

/// Async provider that triggers [CameraService.initCamera] and completes
/// when the camera is ready.
///
/// Widgets can watch this provider to show a loading indicator while the
/// camera is being initialised.
final cameraInitProvider = FutureProvider<void>((ref) async {
  final service = ref.read(cameraServiceProvider);
  await service.initCamera();
});

// ---------------------------------------------------------------------------
// Frame Stream Provider
// ---------------------------------------------------------------------------

/// Stream provider that delivers [ProcessedFrame]s at ~10–15 FPS.
///
/// Pipeline:
/// 1. Waits for [cameraInitProvider] to complete (camera ready).
/// 2. Listens to the raw [CameraImage] stream from [CameraService].
/// 3. Applies [FrameSkipper] to throttle from 30 FPS native to ~10–15 FPS.
/// 4. Converts each accepted [CameraImage] into a [ProcessedFrame] with
///    raw bytes, resolution metadata, and capture timestamp.
///
/// Loading / error states are surfaced to widgets via [AsyncValue]:
/// - **Loading**: camera is initialising (before init completes).
/// - **Error**: camera init failed, no camera available, or stream error.
/// - **Data**: a new [ProcessedFrame] is available for the pipeline.
final frameStreamProvider = StreamProvider<ProcessedFrame>((ref) async* {
  // Block until the camera is fully initialised.
  // If init fails, the await throws and the error propagates to AsyncValue.
  await ref.watch(cameraInitProvider.future);

  final service = ref.read(cameraServiceProvider);
  final skipper = FrameSkipper();

  await for (final image in service.frameStream) {
    if (skipper.shouldProcessFrame()) {
      yield ProcessedFrame(
        bytes: image.planes[0].bytes,
        resolution: Size(image.width.toDouble(), image.height.toDouble()),
        timestamp: DateTime.now(),
      );
    }
  }
});
