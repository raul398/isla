import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/translation.dart';
import 'inference_provider.dart';

// ---------------------------------------------------------------------------
// Translation State
// ---------------------------------------------------------------------------

/// Immutable state holder for the streaming caption display.
///
/// Mirrors the progressive-confirmation model from the spec:
/// - [confirmedText] accumulates finalized portions (displayed in white).
/// - [partialText] shows the current best-guess (displayed in grey).
/// - [lastGestureTime] drives the 5‑second idle auto‑clear.
class TranslationState {
  final String confirmedText;
  final String partialText;
  final bool isFinal;
  final DateTime? lastGestureTime;

  const TranslationState({
    this.confirmedText = '',
    this.partialText = '',
    this.isFinal = false,
    this.lastGestureTime,
  });

  TranslationState copyWith({
    String? confirmedText,
    String? partialText,
    bool? isFinal,
    DateTime? lastGestureTime,
    /// Pass `true` to explicitly set [lastGestureTime] to `null`.
    bool clearLastGestureTime = false,
  }) {
    return TranslationState(
      confirmedText: confirmedText ?? this.confirmedText,
      partialText: partialText ?? this.partialText,
      isFinal: isFinal ?? this.isFinal,
      lastGestureTime:
          clearLastGestureTime ? null : (lastGestureTime ?? this.lastGestureTime),
    );
  }

  /// True when no content is displayed (idle or cleared after timeout).
  bool get isEmpty => confirmedText.isEmpty && partialText.isEmpty;
}

// ---------------------------------------------------------------------------
// CaptionProvider
// ---------------------------------------------------------------------------

/// Listens to the inference pipeline and manages progressive confirmation.
///
/// ## 5‑frame confirmation (spec: streaming-captions / progressive-confirmation)
///
/// A sliding window tracks the last 5 [Translation.partialText] values.
/// When all 5 are equal and non‑empty the gesture is considered *confirmed*
/// and promoted from grey to white.
///
/// Additionally, when [Translation.isFinal] is `true` (sequence window
/// expired), the partial text is immediately promoted to confirmed.
///
/// ## 5‑second idle clear (spec: streaming-captions / empty-state)
///
/// A timer resets on every incoming translation. If no translation arrives
/// within 5 seconds both confirmed and partial text are cleared.
class CaptionProvider extends StateNotifier<AsyncValue<TranslationState>> {
  final Ref _ref;
  Timer? _clearTimer;

  /// Sliding window of the last [kConfirmationFrames] partial texts.
  final List<String> _lastPartialTexts = [];

  /// Frames needed to confirm a gesture (spec requirement).
  static const int kConfirmationFrames = 5;

  /// Idle timeout after which captions are cleared (spec requirement).
  static const Duration kIdleTimeout = Duration(seconds: 5);

  CaptionProvider(this._ref)
      : super(const AsyncValue.data(TranslationState())) {
    // Subscribe to the inference pipeline stream.
    _ref.listen<AsyncValue<Translation>>(
      inferenceStreamProvider,
      (AsyncValue<Translation>? _, AsyncValue<Translation> next) {
        next.when(
          data: _onTranslation,
          error: (Object e, StackTrace st) {
            state = AsyncValue.error(e, st);
          },
          loading: () {
            // Models still initialising — keep current display state.
          },
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // Translation handler
  // -----------------------------------------------------------------------

  void _onTranslation(Translation t) {
    _resetClearTimer();

    final current = state.asData?.value ?? const TranslationState();
    final now = DateTime.now();

    // --- 1. Update gesture confirmation buffer ---

    if (t.partialText.isNotEmpty) {
      _lastPartialTexts.add(t.partialText);
      if (_lastPartialTexts.length > kConfirmationFrames) {
        _lastPartialTexts.removeAt(0);
      }
    } else {
      // Empty partial → gesture window is closed; reset buffer.
      _lastPartialTexts.clear();
    }

    // --- 2. Decide whether to confirm ---

    final bool shouldConfirm =
        t.isFinal || _isGestureConfirmed(t.partialText);

    late final String newConfirmed;
    late final String newPartial;

    if (t.partialText.isEmpty) {
      // Empty translation — just reset partial text.
      newConfirmed = current.confirmedText;
      newPartial = '';
    } else if (shouldConfirm) {
      // Promote partial → confirmed.
      newConfirmed = current.confirmedText.isEmpty
          ? t.partialText
          : '${current.confirmedText} ${t.partialText}';
      newPartial = '';
      _lastPartialTexts.clear();
    } else {
      // Not yet confirmed — keep in partial (grey) zone.
      newConfirmed = current.confirmedText;
      newPartial = t.partialText;
    }

    // --- 3. Emit new state ---

    state = AsyncValue.data(TranslationState(
      confirmedText: newConfirmed,
      partialText: newPartial,
      isFinal: t.isFinal,
      lastGestureTime: now,
    ));
  }

  // -----------------------------------------------------------------------
  // Confirmation logic
  // -----------------------------------------------------------------------

  /// Returns `true` when 5+ consecutive frames report the same non‑empty
  /// partial text (spec: progressive-confirmation happy path).
  bool _isGestureConfirmed(String currentPartial) {
    if (_lastPartialTexts.length < kConfirmationFrames) return false;
    if (currentPartial.isEmpty) return false;
    final first = _lastPartialTexts.first;
    return _lastPartialTexts.every((t) => t == first);
  }

  // -----------------------------------------------------------------------
  // Idle timer
  // -----------------------------------------------------------------------

  void _resetClearTimer() {
    _clearTimer?.cancel();
    _clearTimer = Timer(kIdleTimeout, () {
      state = const AsyncValue.data(TranslationState());
      _lastPartialTexts.clear();
    });
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Manually reset all state (e.g. when the user navigates away).
  void reset() {
    _clearTimer?.cancel();
    _lastPartialTexts.clear();
    state = const AsyncValue.data(TranslationState());
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _lastPartialTexts.clear();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Riverpod provider for the streaming caption state.
///
/// Widgets watch this to render the CaptionBox:
/// - **loading**: "Inicializando…" (grey, italic)
/// - **error**: "Error en traducción" (red)
/// - **data**: [TranslationState] with confirmed text (white) + partial (grey)
final captionProvider =
    StateNotifierProvider<CaptionProvider, AsyncValue<TranslationState>>(
  (ref) => CaptionProvider(ref),
);
