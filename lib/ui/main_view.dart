import 'package:flutter/material.dart';

/// Root view of the ISLA app.
///
/// In Phase 1 (Foundation) this is a placeholder. Phase 4 (UI) will wire the
/// CameraFeed (top) and CaptionBox (bottom) into this Scaffold.
class MainView extends StatelessWidget {
  const MainView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'ISLA — Cargando...',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
        ),
      ),
    );
  }
}
