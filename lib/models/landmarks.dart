/// A single hand landmark point in normalized coordinates.
///
/// Dart 3 record type for zero-cost destructuring.
/// All fields are in [0..1] range (relative to frame width/height) except
/// [z] which is landmark depth in wrist-relative metric space.
typedef Landmark = (double x, double y, double z, double visibility);

/// Landmarks extracted from both hands via MediaPipe Hand Landmarker.
///
/// Each hand produces 21 landmarks in MediaPipe's canonical order:
///   0  = wrist
///   1‑4  = thumb (CMC, MCP, IP, tip)
///   5‑8  = index finger (MCP, PIP, DIP, tip)
///   9‑12 = middle finger (MCP, PIP, DIP, tip)
///   13‑16 = ring finger (MCP, PIP, DIP, tip)
///   17‑20 = pinky (MCP, PIP, DIP, tip)
///
/// [left] and [right] are nullable — the spec requires graceful handling of
/// zero‑hand and one‑hand scenarios without crashing.
class HandLandmarks {
  /// Landmarks for the left hand, or `null` if not detected.
  final List<Landmark>? left;

  /// Landmarks for the right hand, or `null` if not detected.
  final List<Landmark>? right;

  const HandLandmarks({this.left, this.right});

  /// Whether at least one hand was detected.
  bool get hasAnyHand => left != null || right != null;

  /// Flatten both hands into a single 126‑element list of normalized floats.
  ///
  /// Ordering: [left (63)] + [right (63)].
  /// Each hand: 21 landmarks × 3 coordinates (x, y, z) — visibility is
  /// excluded from the feature vector as the MLP/LSTM don't use it.
  ///
  /// Missing hands are encoded as zeros (21 landmarks × 3 coords = 63 zeros).
  List<double> toNormalizedList() {
    final result = <double>[];
    result.addAll(_flatten(left));
    result.addAll(_flatten(right));
    assert(result.length == 126);
    return result;
  }

  /// Flatten 21 landmarks into 63 doubles (x, y, z per landmark).
  List<double> _flatten(List<Landmark>? hand) {
    if (hand == null || hand.length != 21) {
      return List.filled(63, 0.0);
    }
    return [
      for (final l in hand) ...[l.$1, l.$2, l.$3],
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HandLandmarks &&
          _listEq(left, other.left) &&
          _listEq(right, other.right);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(left ?? []),
        Object.hashAll(right ?? []),
      );

  static bool _listEq(List<Landmark>? a, List<Landmark>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final la = a[i];
      final lb = b[i];
      if (la.$1 != lb.$1 ||
          la.$2 != lb.$2 ||
          la.$3 != lb.$3 ||
          la.$4 != lb.$4) {
        return false;
      }
    }
    return true;
  }
}
