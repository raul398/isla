/// A translation output from the sequence translator (LSTM).
///
/// Follows the spec's streaming contract:
/// - [partialText] emits the current best-guess phrase as gestures arrive.
/// - [confirmedText] accumulates phrases that have been finalized either by
///   window expiry (>2s gap) or explicit flush.
/// - [isFinal] is true when the current sequence window has closed and the
///   partial text has been promoted to confirmed.
class Translation {
  /// The running partial text for the current gesture window.
  ///
  /// Gray in the UI (not yet confirmed).
  final String partialText;

  /// The accumulated confirmed text from closed windows.
  ///
  /// White in the UI (confirmed by sequence completion or timeout).
  final String confirmedText;

  /// Whether the current window has been finalized.
  ///
  /// When `true`, the UI promotes partial → confirmed and resets partial.
  final bool isFinal;

  const Translation({
    required this.partialText,
    required this.confirmedText,
    required this.isFinal,
  });

  /// Empty initial state before any gestures arrive.
  factory Translation.empty() => const Translation(
        partialText: '',
        confirmedText: '',
        isFinal: false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Translation &&
          partialText == other.partialText &&
          confirmedText == other.confirmedText &&
          isFinal == other.isFinal;

  @override
  int get hashCode => Object.hash(partialText, confirmedText, isFinal);

  @override
  String toString() =>
      'Translation(partial: "$partialText", confirmed: "$confirmedText", '
      'isFinal: $isFinal)';
}
