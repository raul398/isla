/// A classified gesture produced by the MLP classifier.
///
/// [label] is the gesture name (e.g. "A", "gracias", "hola").
/// [confidence] is the model's softmax score for this label (0..1).
/// [timestamp] marks when the classification was produced.
class Gesture {
  /// Gesture label string (e.g. "A", "hola", "gracias").
  final String label;

  /// Model confidence score in the [0..1] range.
  ///
  /// The classifier applies a >60% threshold per spec — any prediction below
  /// that is replaced with "unknown".
  final double confidence;

  /// When this classification was produced by the MLP.
  final DateTime timestamp;

  const Gesture({
    required this.label,
    required this.confidence,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Gesture &&
          label == other.label &&
          confidence == other.confidence &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(label, confidence, timestamp);

  @override
  String toString() =>
      'Gesture(label: $label, confidence: ${confidence.toStringAsFixed(3)}, '
      'timestamp: $timestamp)';
}
