import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/camera_provider.dart';

/// Live camera preview with optional landmark debug overlay.
///
/// ## Layout
///
/// Covers the full available width with flexible height (used in a flex
/// layout as the top half of the screen). Spans the parent horizontally.
///
/// ## States
///
/// | Camera state   | UI                                  |
/// |----------------|--------------------------------------|
/// | Loading        | [CircularProgressIndicator]          |
/// | Error          | Icon + "Cámara no disponible" + msg  |
/// | Ready          | Live [CameraPreview]                 |
///
/// ## Landmark overlay
///
/// When [showLandmarks] is `true` a debugging overlay is drawn on top of
/// the camera feed. Green dots represent detected hand landmarks (21 per
/// hand). The overlay is a pass-through touch zone.
class CameraFeed extends ConsumerWidget {
  /// Whether to render the hand-landmark debug overlay.
  final bool showLandmarks;

  const CameraFeed({super.key, this.showLandmarks = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraInitAsync = ref.watch(cameraInitProvider);

    return cameraInitAsync.when(
      // -------------------------------------------------------------------
      // Loading
      // -------------------------------------------------------------------
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Iniciando cámara…',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),

      // -------------------------------------------------------------------
      // Error
      // -------------------------------------------------------------------
      error: (Object e, StackTrace _) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                'Cámara no disponible',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Text(
                '$e',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Asegúrate de que la cámara está habilitada en los ajustes '
                'del dispositivo.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),

      // -------------------------------------------------------------------
      // Ready — show live preview
      // -------------------------------------------------------------------
      data: (_) => Stack(
        fit: StackFit.expand,
        children: [
          // Live camera preview (native Texture widget).
          const _CameraPreviewWidget(),

          // Optional debug overlay.
          if (showLandmarks)
            const CustomPaint(
              painter: _LandmarkOverlayPainter(),
              size: Size.infinite,
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Internal widgets
// ===========================================================================

/// Renders the native camera preview using the [CameraController] managed
/// by [CameraService].
///
/// This widget is only rendered inside the `data` branch of
/// [cameraInitProvider], which guarantees the controller is initialised and
/// ready.
class _CameraPreviewWidget extends ConsumerWidget {
  const _CameraPreviewWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(cameraServiceProvider).controller;

    if (controller == null || !controller.value.isInitialized) {
      // Safety guard — should never be reached since this widget is only
      // rendered after cameraInitProvider has completed.
      return const Center(child: CircularProgressIndicator());
    }

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.width ??
              (controller.description.sensorOrientation == 90 ||
                      controller.description.sensorOrientation == 270
                  ? controller.value.previewSize?.height ?? 640
                  : controller.value.previewSize?.width ?? 640),
          height: controller.value.previewSize?.height ??
              (controller.description.sensorOrientation == 90 ||
                      controller.description.sensorOrientation == 270
                  ? controller.value.previewSize?.width ?? 480
                  : controller.value.previewSize?.height ?? 480),
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

/// Debug overlay that renders hand landmarks as green dots.
///
/// Currently renders a placeholder crosshair. When the HandLandmarker
/// pipeline is wired to the UI, this will draw 21 circles per detected
/// hand using the latest landmark data from the inference stream.
class _LandmarkOverlayPainter extends CustomPainter {
  const _LandmarkOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // TODO: wire landmark output from inference stream to draw actual dots.
    // For now, a subtle corner markers indicate debug mode is active.
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const double markerLen = 24.0;
    const double gap = 12.0;

    // Top-left corner.
    canvas.drawLine(
        const Offset(gap, gap + markerLen), const Offset(gap, gap), paint);
    canvas.drawLine(
        const Offset(gap, gap), const Offset(gap + markerLen, gap), paint);

    // Top-right corner.
    canvas.drawLine(
        Offset(size.width - gap - markerLen, gap),
        Offset(size.width - gap, gap),
        paint);
    canvas.drawLine(
        Offset(size.width - gap, gap),
        Offset(size.width - gap, gap + markerLen),
        paint);

    // Bottom-left corner.
    canvas.drawLine(
        Offset(gap, size.height - gap),
        Offset(gap, size.height - gap - markerLen),
        paint);
    canvas.drawLine(
        Offset(gap, size.height - gap),
        Offset(gap + markerLen, size.height - gap),
        paint);

    // Bottom-right corner.
    canvas.drawLine(
        Offset(size.width - gap, size.height - gap - markerLen),
        Offset(size.width - gap, size.height - gap),
        paint);
    canvas.drawLine(
        Offset(size.width - gap - markerLen, size.height - gap),
        Offset(size.width - gap, size.height - gap),
        paint);
  }

  @override
  bool shouldRepaint(covariant _LandmarkOverlayPainter oldDelegate) => false;
}
