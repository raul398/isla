import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isla/providers/camera_provider.dart';
import 'package:isla/ui/camera_feed.dart';

void main() {
  group('CameraFeed', () {
    // -----------------------------------------------------------------------
    // Loading state — default, no overrides needed
    // -----------------------------------------------------------------------
    testWidgets('shows CircularProgressIndicator when camera is loading',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: CameraFeed()),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'loading indicator while camera initialises');
      expect(find.text('Iniciando cámara…'), findsOneWidget,
          reason: 'loading label shown');
    });

    // -----------------------------------------------------------------------
    // Error state — camera init failed
    // -----------------------------------------------------------------------
    testWidgets('shows camera error message when init fails',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cameraInitProvider.overrideWith((ref) => Future<void>.error(
                  CameraException('NoCamera', 'No camera available'),
                )),
          ],
          child: const MaterialApp(home: CameraFeed()),
        ),
      );

      // After error, pump to let the async error propagate.
      await tester.pump();

      expect(find.text('Cámara no disponible'), findsOneWidget,
          reason: 'error title shown');
      expect(find.byIcon(Icons.videocam_off), findsOneWidget,
          reason: 'camera-off icon shown');
      expect(
        find.textContaining('Asegúrate'),
        findsOneWidget,
        reason: 'guidance text shown',
      );
    });

    // -----------------------------------------------------------------------
    // Error state — CameraException with message
    // -----------------------------------------------------------------------
    testWidgets('shows the specific error message from the exception',
        (tester) async {
      const errorMsg = 'PERMISSION_DENIED: camera access denied';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cameraInitProvider.overrideWith((ref) => Future<void>.error(
                  CameraException('PermissionDenied', errorMsg),
                )),
          ],
          child: const MaterialApp(home: CameraFeed()),
        ),
      );

      await tester.pump();

      // The error detail is rendered in a bodySmall text.
      expect(find.textContaining(errorMsg), findsOneWidget,
          reason: 'specific error message displayed');
    });

    // -----------------------------------------------------------------------
    // Data state — camera initialised (renders preview placeholder)
    // -----------------------------------------------------------------------
    testWidgets('renders camera preview container when camera is ready',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cameraInitProvider.overrideWith((ref) => Future<void>.value(null)),
          ],
          child: const MaterialApp(home: CameraFeed()),
        ),
      );

      await tester.pump();

      // When cameraInitProvider succeeds, the widget renders:
      //   Stack → [_CameraPreviewWidget, (LandmarkOverlay if showLandmarks)]
      // Since there is no real CameraController in tests,
      // _CameraPreviewWidget falls back to a safety
      // CircularProgressIndicator.
      //
      // The key assertion: we are in the "data" branch, not loading/error.
      expect(find.byType(Stack), findsOneWidget,
          reason: 'Stack layout indicates data branch is active');
      expect(find.text('Iniciando cámara…'), findsNothing,
          reason: 'no longer in loading state');
      expect(find.text('Cámara no disponible'), findsNothing,
          reason: 'no error shown');
    });

    // -----------------------------------------------------------------------
    // Config — showLandmarks passes through without crashing
    // -----------------------------------------------------------------------
    testWidgets('showLandmarks=true renders without error', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cameraInitProvider.overrideWith((ref) => Future<void>.value(null)),
          ],
          child: const MaterialApp(home: CameraFeed(showLandmarks: true)),
        ),
      );

      await tester.pump();

      // showLandmarks=true adds a CustomPaint overlay on top of the Stack.
      expect(find.byType(Stack), findsOneWidget,
          reason: 'data branch renders Stack regardless of landmarks toggle');
      // No crash is the primary assertion.
    });
  });
}
