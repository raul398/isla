import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/caption_provider.dart';

/// Streaming caption display for the bottom half of the screen.
///
/// Renders the output of the inference pipeline with progressive
/// confirmation (spec: streaming-captions / progressive-confirmation):
///
/// | State               | UI                                           |
/// |---------------------|----------------------------------------------|
/// | Loading             | "Inicializando…" — grey, italic              |
/// | Error               | "Error en traducción" — red                  |
/// | Data (empty)        | "…" — grey, subtle                           |
/// | Data (partial)      | [confirmedText] in white + [partialText] in grey |
/// | Data (confirmed)    | [confirmedText] in white                     |
///
/// ## Idle clear (spec: streaming-captions / empty-state)
///
/// When no gesture is detected for 5 seconds the [CaptionProvider] emits an
/// empty state, which this widget renders as "…".
class CaptionBox extends ConsumerWidget {
  const CaptionBox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captionAsync = ref.watch(captionProvider);

    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: captionAsync.when(
        // -----------------------------------------------------------------
        // Loading — models are initialising
        // -----------------------------------------------------------------
        loading: () => const Center(
          child: Text(
            'Inicializando…',
            style: TextStyle(
              color: Colors.grey,
              fontStyle: FontStyle.italic,
              fontSize: 20,
            ),
          ),
        ),

        // -----------------------------------------------------------------
        // Error
        // -----------------------------------------------------------------
        error: (Object e, StackTrace _) => const Center(
          child: Text(
            'Error en traducción',
            style: TextStyle(
              color: Colors.redAccent,
              fontSize: 18,
            ),
          ),
        ),

        // -----------------------------------------------------------------
        // Data — render captions
        // -----------------------------------------------------------------
        data: (TranslationState state) {
          if (state.isEmpty) {
            return const Center(
              child: Text(
                '…',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 20,
                ),
              ),
            );
          }

          return Align(
            alignment: Alignment.bottomLeft,
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 26, height: 1.4),
                children: [
                  // Confirmed text — white, solid
                  if (state.confirmedText.isNotEmpty)
                    TextSpan(
                      text: '${state.confirmedText} ',
                      style: const TextStyle(color: Colors.white),
                    ),
                  // Partial text — grey (still in candidate zone)
                  if (state.partialText.isNotEmpty)
                    TextSpan(
                      text: state.partialText,
                      style: const TextStyle(color: Colors.grey),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
