import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/camera_provider.dart';
import 'camera_feed.dart';
import 'caption_box.dart';

/// Root view of the ISLA app.
///
/// Layout is split vertically:
/// - **Top half (flex: 1)**: [CameraFeed] — live camera preview.
/// - **Divider**: subtle 1px line.
/// - **Bottom half (flex: 1)**: [CaptionBox] — streaming Spanish captions.
///
/// ## Camera lifecycle
///
/// Camera initialisation is triggered by watching [cameraInitProvider].
/// When this view leaves the widget tree the provider's `onDispose`
/// callback releases the underlying [CameraService].
///
/// ## Permission handling
///
/// If the camera cannot be initialised (denied permission, no camera, etc.)
/// the [CameraFeed] widget renders an error message with guidance to enable
/// the camera in system settings.
class MainView extends ConsumerWidget {
  const MainView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Trigger camera init and keep the provider alive while this view is
    // mounted. The CameraFeed widget handles loading/error/data UI through
    // its own watch on cameraInitProvider.
    ref.watch(cameraInitProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top half — live camera preview.
            const Expanded(
              flex: 1,
              child: CameraFeed(),
            ),

            // Subtle divider.
            Container(
              height: 1,
              color: Colors.grey[800],
            ),

            // Bottom half — streaming captions.
            const Expanded(
              flex: 1,
              child: CaptionBox(),
            ),
          ],
        ),
      ),
    );
  }
}
