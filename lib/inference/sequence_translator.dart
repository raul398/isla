import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/gesture.dart';
import '../models/translation.dart';

/// Translates sequences of classified [Gesture]s into Spanish [Translation]s.
///
/// ## Temporal window
///
/// Gestures are accumulated in a sliding 2-second window.
///
/// - Gestures within the window contribute to a running partial phrase.
/// - When the window expires — or a gap > 2 s is detected between consecutive
///   gestures — the buffer is **flushed** and the final phrase is promoted to
///   [Translation.confirmedText].
/// - A new window starts automatically after each flush.
///
/// ## Streaming output
///
/// Each call to [processGesture] emits a [Translation] with the current
/// partial text. When flushed, a final [Translation] with `isFinal: true` is
/// emitted. Subscribe via [output].
///
/// ## Decoding strategy (MVP)
///
/// The current implementation uses a **rule-based decoder**:
///
/// - Single gesture → its isolated meaning (e.g. `"hola"` → `"hola"`).
/// - Letter sequence → joined string (e.g. `"H", "O", "L", "A"` → `"HOLA"`).
/// - Mixed sequence → space-separated words (e.g. `"yo", "quiero", "agua"`
///   → `"yo quiero agua"`).
///
/// TODO: Replace the rule-based decoder with the LSTM model
/// (`assets/models/lstm.tflite`) for proper sequence-to-phrase translation.
/// The LSTM would take a sequence of one-hot encoded gesture labels and
/// output text tokens via a small vocabulary decoder.
class SequenceTranslator {
  final Duration _windowDuration;

  /// Gestures in the current temporal window.
  final List<Gesture> _buffer = [];

  /// Timestamp when the current window started.
  DateTime? _windowStart;

  /// Timer that fires when the window expires.
  Timer? _windowTimer;

  /// Accumulated confirmed text from previously flushed windows.
  String _confirmedText = '';

  /// Broadcast stream controller for live translation updates.
  final StreamController<Translation> _outputController =
      StreamController<Translation>.broadcast();

  /// A broadcast stream of [Translation]s emitted as gestures are processed
  /// and windows expire.
  Stream<Translation> get output => _outputController.stream;

  /// Creates a translator with the given [windowDuration].
  ///
  /// Default window is 2 seconds per spec.
  SequenceTranslator({Duration? windowDuration})
      : _windowDuration = windowDuration ?? const Duration(seconds: 2);

  /// Processes a single classified gesture.
  ///
  /// Returns the current [Translation] and emits it on [output].
  ///
  /// Gestures with labels `"unknown"` or `"model_not_ready"` are silently
  /// skipped — they do not contribute to the buffer.
  Translation processGesture(Gesture gesture) {
    // Filter non-gestures.
    if (gesture.label == 'unknown' ||
        gesture.label == 'model_not_ready' ||
        gesture.label == 'error') {
      final current = _buildTranslation(isFinal: false);
      _outputController.add(current);
      return current;
    }

    final now = gesture.timestamp;

    // --- Window management ---
    if (_buffer.isEmpty) {
      // First gesture — start a new window.
      _windowStart = now;
      _buffer.add(gesture);
    } else {
      final lastGesture = _buffer.last;
      final gap = now.difference(lastGesture.timestamp);

      if (gap > _windowDuration) {
        // Gap exceeds window — flush the current buffer before appending.
        final flushed = _flush();
        _outputController.add(flushed);
        _windowStart = now;
        _buffer.add(gesture);
      } else {
        // Normal append within window.
        _buffer.add(gesture);
      }
    }

    // Reset the window expiry timer.
    _windowTimer?.cancel();
    _windowTimer = Timer(_windowDuration, () {
      final flushed = _flush();
      _outputController.add(flushed);
    });

    final translation = _buildTranslation(isFinal: false);
    _outputController.add(translation);
    return translation;
  }

  /// Force-flushes the current window.
  ///
  /// The accumulated gesture sequence is decoded, promoted to confirmed text,
  /// and the buffer is cleared. Returns the final [Translation].
  Translation flush() {
    final translation = _flush();
    _outputController.add(translation);
    return translation;
  }

  /// Internal flush — no [output] emission; returns the translation.
  Translation _flush() {
    _windowTimer?.cancel();
    _windowTimer = null;

    if (_buffer.isEmpty) {
      return Translation.empty();
    }

    final decoded = _decodeBuffer(_buffer);

    // Append to confirmed text with separator.
    if (_confirmedText.isNotEmpty && decoded.isNotEmpty) {
      _confirmedText = '$_confirmedText $decoded';
    } else if (decoded.isNotEmpty) {
      _confirmedText = decoded;
    }

    _buffer.clear();
    _windowStart = null;

    return Translation(
      partialText: '',
      confirmedText: _confirmedText,
      isFinal: true,
    );
  }

  /// Builds a non-final [Translation] from the current buffer contents.
  Translation _buildTranslation({required bool isFinal}) {
    final partialText = _decodeBuffer(_buffer);
    return Translation(
      partialText: partialText,
      confirmedText: _confirmedText,
      isFinal: isFinal,
    );
  }

  /// Resets all state — clears buffer, confirmed text, and timers.
  ///
  /// Useful when the user requests a fresh translation session.
  void reset() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _buffer.clear();
    _windowStart = null;
    _confirmedText = '';
    _outputController.add(Translation.empty());
  }

  // ---------------------------------------------------------------------------
  // Decoding
  // ---------------------------------------------------------------------------

  /// Decodes a buffer of [Gesture]s into a Spanish string.
  ///
  /// Current implementation is rule-based.
  ///
  /// TODO: Replace with LSTM inference:
  /// ```dart
  /// final input = _encodeGestureSequence(buffer);
  /// final output = Float64List(vocabSize);
  /// _lstmInterpreter!.run([input], [output]);
  /// return _decodeTokens(output);
  /// ```
  String _decodeBuffer(List<Gesture> buffer) {
    if (buffer.isEmpty) return '';
    if (buffer.length == 1) {
      return _gestureToText(buffer[0].label);
    }

    return _ruleBasedDecode(buffer);
  }

  /// Converts a single gesture label to its Spanish representation.
  String _gestureToText(String label) {
    // Normalise: lowercase, replace underscores with spaces.
    switch (label.toLowerCase()) {
      // Manual alphabet.
      case 'a': return 'a';
      case 'b': return 'b';
      case 'c': return 'c';
      case 'd': return 'd';
      case 'e': return 'e';
      case 'f': return 'f';
      case 'g': return 'g';
      case 'h': return 'h';
      case 'i': return 'i';
      case 'j': return 'j';
      case 'k': return 'k';
      case 'l': return 'l';
      case 'm': return 'm';
      case 'n': return 'n';
      case 'o': return 'o';
      case 'p': return 'p';
      case 'q': return 'q';
      case 'r': return 'r';
      case 's': return 's';
      case 't': return 't';
      case 'u': return 'u';
      case 'v': return 'v';
      case 'w': return 'w';
      case 'x': return 'x';
      case 'y': return 'y';
      case 'z': return 'z';

      // Word gestures (LSA / LSA64 subset).
      case 'hola': return 'hola';
      case 'gracias': return 'gracias';
      case 'por_favor': return 'por favor';
      case 'adios': return 'adiós';
      case 'si': return 'sí';
      case 'no': return 'no';
      case 'ayuda': return 'ayuda';
      case 'agua': return 'agua';
      case 'comida': return 'comida';
      case 'casa': return 'casa';
      case 'familia': return 'familia';
      case 'amigo': return 'amigo';

      default:
        // Fallback: return the raw label as-is with underscores → spaces.
        return label.replaceAll('_', ' ');
    }
  }

  /// Rule-based multi-gesture decoder.
  ///
  /// Heuristics:
  /// - All single-letter gestures → joined as a word (uppercase).
  /// - Mixed / word gestures → space-separated phrase.
  ///
  /// TODO: Replace with LSTM model inference for proper grammar.
  String _ruleBasedDecode(List<Gesture> buffer) {
    final meanings = buffer.map((g) => _gestureToText(g.label)).toList();

    final allLetters = meanings.every((m) => m.length == 1);

    if (allLetters && meanings.length <= 20) {
      // Join single letters as a word.
      return meanings.join('').toUpperCase();
    }

    // Default: space-separated words.
    return meanings.join(' ');
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Releases resources (timer + stream controller).
  void dispose() {
    _windowTimer?.cancel();
    _outputController.close();
    _buffer.clear();
    debugPrint('SequenceTranslator: disposed');
  }
}
